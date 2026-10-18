require "compress/gzip"
require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Replay::Backfill do
  alias Backfill = Roguelike::Replay::Backfill
  alias Game = Roguelike::Game
  alias Log = Roguelike::Replay::Log
  alias Resume = Roguelike::Replay::Resume
  alias Rng = Roguelike::Rng
  alias Writer = Roguelike::Events::Writer

  # A directory of logs nothing else writes to.
  def logs : Path
    made = Recording.directory / "backfill-#{Random.rand UInt32}"
    Dir.mkdir_p made
    made
  end

  # The one replay log in *where*.
  def log_in(where : Path) : Path
    found = Dir.children(where).select(&.ends_with? ".jsonl")
    raise "#{where} holds #{found.size} logs" unless found.size == 1

    where / found.first
  end

  # Every line of the events file at *path*, unpacked.
  def lines(path : Path) : Array(String)
    File.open path do |file|
      Compress::Gzip::Reader.open(file, &.gets_to_end).lines
    end
  end

  # The `type` of each line of *found* that has one.
  def types(found : Array(String)) : Array(String)
    found.compact_map { |line| JSON.parse(line)["type"]?.try(&.as_s) }
  end

  # Plays *count* actions drawn from `Game#legal`, on a stream of *salt*.
  def play(game : Game, count : Int32, salt : UInt64) : Game
    rng = Rng.new Recording::SEED, salt
    count.times do
      break if game.over?

      game.perform game.legal.reject(Roguelike::Action::Ascend).sample(rng)
    end
    game
  end

  NAME = "backfiller"

  # A run recorded into *where*, saved after twenty actions and carried on
  # from the save for twenty more. Answers the save.
  def spanning(where : Path) : Path
    store = Playing.store
    Log.pattern = where.to_s
    begin
      game = Game.dug Rng.new(Recording::SEED)
      game.player.name = NAME
      play game, 20, 1_u64
      store.write game
      Log.ended nil

      held = store.held NAME
      raise "#{store.directory} holds no #{NAME}" unless held

      play held.carried(store.path(NAME)), 20, 2_u64
    ensure
      Log.ended nil
      Log.pattern = nil
    end
    store.path NAME
  end

  it "writes the file the live game wrote" do
    where = logs
    Recording.played where.to_s, turns: 60
    log = log_in where
    target = where / "rebuilt.gz"

    report = Backfill.run log, target
    expect(report.status).to eq(Backfill::DONE)
    expect(lines(target)).to eq(lines(Writer.path_for(log)))
  end

  it "writes beside the log when no path is given" do
    where = logs
    Recording.played where.to_s, turns: 10
    log = log_in where
    live = lines Writer.path_for(log)
    File.delete Writer.path_for(log)

    expect(Backfill.run(log).ok?).to be_true
    expect(lines(Writer.path_for(log))).to eq(live)
  end

  it "says which turn differs when a checkpoint does not match" do
    where = logs
    Recording.played where.to_s, turns: 60
    log = log_in where
    tampered = File.read_lines(log).map do |line|
      next line unless line.includes? %("type":"check")

      line.sub(/"state":"[^"]*"/, %("state":"0000000000000000"))
    end
    File.write log, tampered.join('\n') + '\n'

    report = Backfill.run log, where / "rebuilt.events.jsonl.gz"
    expect(report.status).to eq(Backfill::DIFFERS)
    expect(report.message.to_s).to contain("turn #{report.turn}")
  end

  describe "a run that spans versions" do
    it "stops at a resume from another version, and the save carries it on" do
      where = logs
      save = spanning where
      log = log_in where
      live = lines Writer.path_for(log)
      expect(types(live)).to eq(["header", "pause", "resume", "footer"])

      resume = Roguelike::Replay::Reading.read(log).records.compact_map(&.as?(Resume)).first
      other = where / "other.jsonl.txt"
      moved = File.read_lines(log).map do |line|
        next line unless line.includes? %("type":"resume")

        line.sub(%("game_version":"#{resume.game_version}"), %("game_version":"0.0.1+gdeadbee"))
      end
      File.write other, moved.join('\n') + '\n'

      target = where / "rebuilt.events.jsonl.gz"
      first = Backfill.run other, target
      expect(first.status).to eq(Backfill::ELSEWHERE)
      expect(first.turn).to eq(resume.turn)
      expect(first.message.to_s).to contain("turn #{resume.turn}")
      expect(first.message.to_s).to contain("0.0.1+gdeadbee")
      expect(types(lines(target))).to eq(["header", "pause"])

      second = Backfill.run log, target, save, resume.turn
      expect(second.status).to eq(Backfill::DONE)
      found = lines target
      expect(types(found)).to eq(["header", "pause", "resume", "footer"])
      expect(found).to eq(live)
    end

    it "names the builds that recorded the header and the resume" do
      where = logs
      spanning where
      log = log_in where
      built = Writer.version
      header = "#{Roguelike::VERSION}+gfeedfac"
      resumed = "#{Roguelike::VERSION}+gc0ffee0"
      other = where / "other.jsonl.txt"
      moved = File.read_lines(log).map do |line|
        if line.includes? %("type":"header")
          line.sub(%("game_version":"#{built}"), %("game_version":"#{header}"))
        elsif line.includes? %("type":"resume")
          line.sub(%("game_version":"#{built}"), %("game_version":"#{resumed}"))
        else
          line
        end
      end
      File.write other, moved.join('\n') + '\n'

      target = where / "named.events.jsonl.gz"
      expect(Backfill.run(other, target).ok?).to be_true
      versions = lines(target).compact_map do |line|
        found = JSON.parse(line)
        found["game_version"]?.try { |version| {found["type"].as_s, version.as_s} }
      end
      expect(versions).to eq([{"header", header}, {"resume", resumed}])
    end

    it "plays straight through a resume from this version" do
      where = logs
      spanning where
      log = log_in where
      target = where / "whole.events.jsonl.gz"

      expect(Backfill.run(log, target).ok?).to be_true
      expect(lines(target)).to eq(lines(Writer.path_for(log)))
    end
  end

  describe ".leaving_ours" do
    let(ours) { "#{Roguelike::VERSION}+gabc" }
    let(other) { "9.9.9+gabc" }

    def stops(lines : Array(String)) : Array(Bool)
      asks = Backfill.leaving_ours
      lines.map { |line| asks.call line }
    end

    it "stops at the first resume from another version" do
      found = stops [
        %({"type":"header","game_version":"#{ours}"}),
        %({"type":"act","turn":0}),
        %({"type":"resume","game_version":"#{ours}"}),
        %({"type":"resume","game_version":"#{other}"}),
        %({"type":"act","t":"travel"}),
      ]
      expect(found).to eq([false, false, false, true, false])
    end

    it "reads on past a header and resumes of another version" do
      found = stops [
        %({"type":"header","game_version":"#{other}"}),
        %({"type":"resume","game_version":"#{other}"}),
        %({"type":"resume","game_version":"#{ours}"}),
        %({"type":"resume","game_version":"#{other}"}),
      ]
      expect(found).to eq([false, false, false, true])
    end

    it "does not stop on a line that is not JSON" do
      expect(stops(["{\"type\":"])).to eq([false])
    end
  end
end
