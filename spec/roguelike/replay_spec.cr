require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Replay do
  alias Log = Roguelike::Replay::Log
  alias Naming = Roguelike::Replay::Naming
  alias Verifier = Roguelike::Replay::Verifier
  alias Game = Roguelike::Game
  alias Rng = Roguelike::Rng

  # A file nothing else in this run of the specs writes to.
  def spot(name : String) : String
    (Recording.directory / "#{name}-#{Random.rand UInt32}.jsonl").to_s
  end

  describe "where the file goes" do
    let(started) { Time.utc 2026, 9, 23, 18, 4, 11 }

    it "puts the character's slug in for %s" do
      expect(Naming.resolve "/tmp/%s.jsonl", "Ada Lovelace", 7_u64, started)
        .to eq Path["/tmp/Ada-Lovelace.jsonl"]
    end

    it "puts a word in for a character with no name" do
      expect(Naming.resolve "/tmp/%s.jsonl", "", 7_u64, started)
        .to eq Path["/tmp/#{Naming::NOBODY}.jsonl"]
    end

    it "leaves one per cent sign for %%" do
      expect(Naming.resolve "/tmp/100%%.jsonl", "ada", 7_u64, started)
        .to eq Path["/tmp/100%.jsonl"]
    end

    it "starts %d at one" do
      expect(Naming.resolve (Recording.directory / "run-%d.jsonl").to_s,
        "ada", 7_u64, started)
        .to eq Recording.directory / "run-1.jsonl"
    end

    it "pads %02d with zeros" do
      expect(Naming.resolve (Recording.directory / "run-%02d.jsonl").to_s,
        "ada", 7_u64, started)
        .to eq Recording.directory / "run-01.jsonl"
    end

    it "raises the number until the name is free" do
      pattern = (Recording.directory / "taken-%d.jsonl").to_s
      File.write Recording.directory / "taken-1.jsonl", ""
      File.write Recording.directory / "taken-2.jsonl", ""

      expect(Naming.resolve pattern, "ada", 7_u64, started)
        .to eq Recording.directory / "taken-3.jsonl"
    end

    it "takes the spec's own name inside a directory" do
      expect(Naming.resolve Recording.directory.to_s, "Ada", 7_u64, started)
        .to eq Recording.directory / "20260923T180411Z_7_Ada.jsonl"
    end
  end

  describe "a recorded run" do
    it "writes a header, actions, checkpoints and a footer" do
      where = spot "played"
      Recording.played where, turns: 60
      read = Recording.read where

      expect(read.header.seed).to eq Recording::SEED
      expect(read.header.player).to eq Recording::PLAYER
      expect(read.header.streams).to eq Roguelike::Replay::Streams.current
      expect(read.acts).to be > 0
      expect(read.checks).to be > 0
      expect(read.footer).not_to be_nil
    end

    it "rebuilds from the seed, so the header carries no state" do
      where = spot "fresh"
      Recording.played where

      expect(Recording.read(where).header.run).to be_nil
    end

    it "verifies" do
      where = spot "good"
      Recording.played where, turns: 60
      report = Verifier.check where

      expect(report.trouble).to be_nil
      expect(report.ok?).to be_true
      expect(report.acts).to eq Recording.read(where).acts
    end

    it "writes a fingerprint every --replay-every turns" do
      where = spot "often"
      Log.every = 5
      Recording.played where, turns: 30
      Log.every = Log::EVERY
      read = Recording.read where

      expect(read.checks).to be > 3
      expect(Verifier.check(where).ok?).to be_true
    end
  end

  describe "a run the seed does not rebuild" do
    # A character carried on from a save starts from a state that is not a
    # function of the seed. The header carries the state itself for that
    # run. This one reaches the same place by hurting the character before
    # the first action.
    it "carries the whole run in the header, and verifies" do
      where = spot "carried"

      Recording.recording where do
        game = Game.dug Rng.new(Recording::SEED)
        game.player.name = "carried"
        game.player.hurt 3
        6.times { game.perform Roguelike::Action::Wait.new }
        game
      end

      expect(Recording.read(where).header.run).not_to be_nil
      expect(Verifier.check(where).trouble).to be_nil
    end
  end

  describe "a run played at the keyboard" do
    it "verifies" do
      where = spot "keys"

      Recording.recording where do
        run = Playing.open Game.dug(Rng.new(Recording::SEED))
        run.game.player.name = "keyboard"
        run.press "l", "j", "h", "k", ".", "l", "l", "."
        run.game
      end

      expect(Verifier.check(where).trouble).to be_nil
    end

    # One lit room with the character in the middle and a goblin one square
    # east of them.
    ARENA = [
      "#######",
      "#.....#",
      "#.....#",
      "#..<..#",
      "#.....#",
      "#.....#",
      "#######",
    ]

    it "writes a step into a creature as a melee line" do
      where = spot "melee"

      Recording.recording where do
        floor = Playing.daylight Roguelike::Floor.parse("arena", ARENA)
        game = Game.new(
          Roguelike::World.new(Playing::SEED, {"arena" => floor}),
          Roguelike::Player.new("arena", 3, 3, hit_points: 40))
        floor.place Roguelike::Monster.new(
          Roguelike::Species::Goblin, 4, 3, "band-one")

        run = Playing.open game
        run.game.player.name = "melee"
        run.press "l"
        run.game
      end

      swings = File.read_lines(where).count &.includes?(%("t":"melee","target":[4,3]))

      expect(swings).to eq 1
      expect(Verifier.check(where).trouble).to be_nil
    end

    it "gives the same fingerprints with the flames wavering as without" do
      wavering = spot "wavering"
      still = spot "still"

      {wavering => true, still => false}.each do |where, burning|
        Recording.recording where do
          run = Playing.open Game.dug(Rng.new(Recording::SEED))
          run.play.flicker.burning = burning
          run.press "l", "j", "h", "k", ".", "l"
          run.game
        end
      end

      found = {wavering, still}.map do |where|
        Recording.read(where).records.compact_map { |line| line.as?(Roguelike::Replay::Check).try &.state }
      end

      expect(Recording.read(wavering).header.state).to eq Recording.read(still).header.state
      expect(found[0]).to eq found[1]
    end
  end

  describe "a file with no footer" do
    it "verifies up to the last action written" do
      where = spot "cut"
      Recording.played where, turns: 60
      lines = File.read_lines where
      expect(Recording.read(where).footer).not_to be_nil

      shortened = Recording.file lines[0..-2], "shortened"
      report = Verifier.check shortened

      expect(report.trouble).to be_nil
      expect(report.acts).to be > 0
    end

    it "verifies when the last line was cut off part way" do
      where = spot "half"
      Recording.played where, turns: 60
      lines = File.read_lines where
      lines[-1] = lines[-1][0, lines[-1].size // 2]

      report = Verifier.check Recording.file(lines, "halfline")

      expect(report.trouble).to be_nil
      expect(Recording.read(Recording.file lines, "halfline").truncated?).to be_true
    end
  end

  describe "a run that differs" do
    it "names the turn window of the first checkpoint that differs" do
      where = spot "bent"
      Log.every = 5
      Recording.played where, turns: 40
      Log.every = Log::EVERY

      lines = File.read_lines where
      last = lines.rindex! &.includes?(%("type":"check"))
      lines[last] = lines[last].sub(/"state":"sha256:[0-9a-f]+"/,
        %("state":"sha256:#{"0" * 64}"))

      report = Verifier.check Recording.file(lines, "bent")
      trouble = report.trouble

      expect(trouble).not_to be_nil
      expect(trouble.to_s).to contain "the run differs"
      expect(trouble.to_s).to contain "which agreed"
      expect(report.turn).to be < report.acts
    end

    it "refuses a run that does not start from the seed" do
      where = spot "elsewhere"
      Recording.played where, turns: 20

      lines = File.read_lines where
      lines[0] = lines[0].sub %("player":"#{Recording::PLAYER}"), %("player":"somebody")

      report = Verifier.check Recording.file(lines, "elsewhere")

      expect(report.trouble.to_s).to contain "does not start from seed"
    end
  end

  describe "a build whose draw sequences have moved" do
    it "names the parts that moved and refuses" do
      where = spot "stale"
      Recording.played where, turns: 20

      lines = File.read_lines where
      lines[0] = lines[0].sub %("loot":1), %("loot":2)

      report = Verifier.check Recording.file(lines, "stale")

      expect(report.trouble.to_s).to contain "loot"
      expect(report.trouble.to_s).to contain "--force"
    end

    it "checks it anyway with --force" do
      where = spot "forced"
      Recording.played where, turns: 20

      lines = File.read_lines where
      lines[0] = lines[0].sub %("loot":1), %("loot":2)

      expect(Verifier.check(Recording.file(lines, "forced"), force: true).ok?)
        .to be_true
    end
  end

  describe "a file this cannot read" do
    it "reports an empty file rather than raising" do
      where = Recording.file [] of String, "empty"

      expect(Verifier.check(where).trouble.to_s).to contain "empty"
    end

    it "reports a file with no header" do
      where = Recording.file [%({"type":"act","turn":1,"action":{"t":"wait"}})], "headless"

      expect(Verifier.check(where).trouble.to_s).to contain "no header"
    end

    it "reports a file it has never heard of" do
      expect(Verifier.check(Recording.directory / "nothing-here.jsonl").ok?)
        .to be_false
    end
  end

  describe "the replay that ships with the specs" do
    it "verifies" do
      expect(Verifier.check(Recording.golden).trouble).to be_nil
    end
  end

  describe "a line of a kind this does not play back" do
    it "counts it and passes over it" do
      where = spot "noted"
      Recording.played where, turns: 20

      lines = File.read_lines where
      lines.insert 1, %({"type":"note","turn":1,"text":"that ogre felt unfair"})
      read = Recording.read Recording.file(lines, "noted")

      expect(read.ignored).to eq 1
      expect(Verifier.check(Recording.file lines, "noted").ok?).to be_true
    end
  end
end
