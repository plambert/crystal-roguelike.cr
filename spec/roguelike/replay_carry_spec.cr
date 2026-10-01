require "../spec_helper"
require "../support/recording"

# One run recorded across a save and a load, the way a test build records it.
Spectator.describe "a replay log carried across a save" do
  alias Log = Roguelike::Replay::Log
  alias Replay = Roguelike::Replay
  alias Verifier = Roguelike::Replay::Verifier
  alias Game = Roguelike::Game
  alias Rng = Roguelike::Rng
  alias Save = Roguelike::Save

  NAME = "carrier"

  # A directory of logs nothing else writes to.
  def logs : Path
    made = Recording.directory / "carry-#{Random.rand UInt32}"
    Dir.mkdir_p made
    made
  end

  # Plays *count* actions drawn from `Game#legal`, on a stream of *salt*.
  def play(game : Game, count : Int32, salt : UInt64) : Game
    rng = Rng.new Recording::SEED, salt

    count.times do
      break if game.over?

      wanted = game.legal.reject Roguelike::Action::Ascend
      break if wanted.empty?

      game.perform wanted.sample(rng)
    end

    game
  end

  # A fresh run on the spec seed, under `NAME`.
  def fresh : Game
    game = Game.dug Rng.new(Recording::SEED)
    game.player.name = NAME
    game
  end

  # The character in *store*, loaded the way the name question loads one.
  def loaded(store : Save::Store) : Game
    held = store.held NAME
    raise "#{store.directory} holds no character called #{NAME}" unless held

    held.carried store.path(NAME)
  end

  # The one file in *where*.
  def only(where : Path) : Path
    found = Dir.children where
    raise "#{where} holds #{found.size} files" unless found.size == 1

    where / found.first
  end

  # Runs *block* recording to *where*, and puts the settings back.
  def recording(where : Path, &) : Nil
    Log.pattern = where.to_s
    yield
  ensure
    Log.ended nil
    Log.pattern = nil
  end

  it "plays, saves, loads, plays on, and verifies as one run" do
    where = logs
    store = Playing.store

    recording(where) do
      game = play fresh, 30, 1_u64
      store.write game
      Log.ended nil

      play loaded(store), 30, 2_u64
    end

    file = only where
    read = Recording.read file
    report = Verifier.check file

    expect(report.trouble).to be_nil
    expect(report.resumes).to eq 1
    expect(read.pauses).to eq 1
    expect(read.resumes).to eq 1
    expect(read.header.run).to be_nil
    expect(read.rewound).to be_empty
    expect(report.acts).to eq read.acts
  end

  it "names the log and the pause in the save" do
    where = logs
    store = Playing.store

    recording(where) do
      store.write play(fresh, 10, 1_u64)
    end

    mark = store.held(NAME).try &.replay
    expect(mark.try &.log).to eq only(where).to_s
    expect(mark.try &.pause).to eq 1
  end

  it "leaves a paused log with no footer" do
    where = logs
    store = Playing.store

    recording(where) do
      store.write play(fresh, 10, 1_u64)
    end

    read = Recording.read only(where)
    expect(read.footer).to be_nil
    expect(read.pauses).to eq 1
  end

  it "keeps the checkpoints on their turns across the load" do
    where = logs
    store = Playing.store
    Log.every = 5

    recording(where) do
      store.write play(fresh, 23, 1_u64)
      Log.ended nil

      play loaded(store), 30, 2_u64
    end
    Log.every = Log::EVERY

    read = Recording.read only(where)
    turns = read.records.compact_map { |line| line.as?(Replay::Check).try &.turn }

    expect(read.header.every).to eq 5
    expect(turns.size).to be > 4
    turns.each_cons_pair { |one, two| expect(two // 5).to be > one // 5 }
    expect(Verifier.check(only where).trouble).to be_nil
  end

  it "verifies a run saved twice and loaded from the second" do
    where = logs
    store = Playing.store

    recording(where) do
      game = play fresh, 15, 1_u64
      store.write game
      play game, 15, 3_u64
      store.write game
      Log.ended nil

      play loaded(store), 20, 2_u64
    end

    read = Recording.read only(where)
    expect(read.pauses).to eq 2
    expect(read.records.compact_map(&.as?(Replay::Resume)).map &.pause).to eq [2]
    expect(Verifier.check(only where).trouble).to be_nil
  end

  # The process played on after the save and went away without another.
  # The save does not hold those actions, so the load goes back to the pause.
  it "goes back to the save past actions written after it" do
    where = logs
    store = Playing.store

    recording(where) do
      game = play fresh, 20, 1_u64
      store.write game
      play game, 20, 3_u64
      Log.ended Exception.new("crashed")

      play loaded(store), 20, 2_u64
    end

    file = only where
    read = Recording.read file

    expect(read.rewound).to eq Set{1}
    expect(read.footer.try &.outcome).to eq "truncated"
    expect(Verifier.check(file).trouble).to be_nil
    expect(Roguelike::Replay::Export.run(file, IO::Memory.new).trouble).to be_nil

    viewer = Roguelike::Replay::Viewer.open file
    viewer.goto viewer.size
    expect(viewer.trouble).to be_nil
    viewer.goto 0
    viewer.goto viewer.size
    expect(viewer.trouble).to be_nil
    viewer.close
  end

  it "notices a run that is not the one it saved" do
    where = logs
    store = Playing.store

    recording(where) do
      game = play fresh, 10, 1_u64
      store.write game
      Log.ended nil

      found = loaded store
      found.player.hurt 2
      play found, 10, 2_u64
    end

    expect(Verifier.check(only where).trouble.to_s).to contain "the loaded run differs"
  end

  it "starts a log of its own, naming the save, when the log is gone" do
    where = logs
    store = Playing.store

    recording(where) do
      store.write play(fresh, 20, 1_u64)
      Log.ended nil
      File.delete only(where)

      play loaded(store), 20, 2_u64
    end

    read = Recording.read only(where)
    continued = read.header.continued

    expect(continued.try &.save).to eq store.path(NAME).to_s
    expect(continued.try &.pause).to eq 1
    expect(read.header.run).not_to be_nil
    expect(Verifier.check(only where).trouble).to be_nil
  end

  it "cuts off a last line written part way before it carries on" do
    where = logs
    store = Playing.store

    recording(where) do
      game = play fresh, 10, 1_u64
      store.write game
      play game, 5, 3_u64
      Log.ended nil

      file = only where
      text = File.read file
      File.write file, text[0, text.size - 20]

      play loaded(store), 10, 2_u64
    end

    expect(Verifier.check(only where).trouble).to be_nil
  end

  it "writes the same run again with upgrade" do
    where = logs
    store = Playing.store

    recording(where) do
      game = play fresh, 20, 1_u64
      store.write game
      play game, 10, 3_u64
      Log.ended nil

      play loaded(store), 20, 2_u64
    end

    source = only where
    target = Recording.directory / "upgraded-#{Random.rand UInt32}.jsonl"
    report = Roguelike::Replay::Upgrade.run source, target
    read = Recording.read target

    expect(report.trouble).to be_nil
    expect(report.resumes).to eq 1
    expect(read.pauses).to eq 1
    expect(read.rewound).to eq Set{1}
  end

  it "writes a footer naming a signal" do
    where = logs

    recording(where) do
      play fresh, 10, 1_u64
      Log.signalled
    end

    expect(Recording.read(only where).footer.try &.cause).to eq "signal"
  end

  describe ".pattern_for" do
    after { Log.always = nil }

    it "takes --replay-log when it is given" do
      Log.always = logs
      expect(Log.pattern_for "given.jsonl").to eq "given.jsonl"
    end

    it "records nothing in an ordinary build without it" do
      expect(Log.pattern_for nil).to be_nil
    end

    it "makes the test logs directory and records into it" do
      wanted = logs / "test_logs"
      Log.always = wanted

      expect(Log.pattern_for nil).to eq wanted.to_s
      expect(Dir.exists? wanted).to be_true
    end
  end
end
