require "../../spec_helper"
require "../../support/recording"

Spectator.describe "the save written every few hundred turns" do
  alias Game = Roguelike::Game
  alias Log = Roguelike::Replay::Log
  alias Play = Roguelike::Ui::Play
  alias Save = Roguelike::Save
  alias Submit = Roguelike::Submit
  alias Verifier = Roguelike::Replay::Verifier

  # A closed room with no way out and nothing in it.
  CELL = [
    "#######",
    "#.....#",
    "#..<..#",
    "#.....#",
    "#######",
  ]

  NAME = "Sparky"

  # A named run on `CELL`, saved to *store*.
  def playing(store : Save::Store? = nil, clock : Bool = false) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("cell", CELL)
    player = Roguelike::Player.new floor.id, *Game.entrance(floor)
    player.name = NAME

    run = Playing.open Game.new(
      Roguelike::World.new(Playing::SEED, {floor.id => floor}), player),
      60, 20, store: store, clock: clock
    run.clear_monsters
    run
  end

  # Waits *turns* turns, the way `.` does.
  def wait(run : Playing::Run, turns : Int32) : Nil
    turns.times { run.play.wait }
  end

  # A directory nothing else writes to.
  def directory : Path
    made = Recording.directory / "autosave-#{Random.rand UInt32}"
    Dir.mkdir_p made
    made
  end

  # The one replay log in *where*. The events file beside it is left out.
  def only(where : Path) : Path
    found = Dir.children(where).select(&.ends_with? ".jsonl")
    raise "#{where} holds #{found.size} files" unless found.size == 1

    where / found.first
  end

  # Runs *block* recording to *logs* with an outbox under *root*, and puts
  # both settings back.
  def recording(logs : Path, root : Path, &) : Nil
    Submit.outbox = Submit::Outbox.new root / "outbox"
    Log.pattern = logs.to_s
    yield
  ensure
    Log.ended nil
    Log.pattern = nil
    Submit.outbox = nil
  end

  # The turn of the save in *store*, or `nil` when it holds none.
  def saved_turn(store : Save::Store) : Int32?
    store.held(NAME).try &.turn
  end

  it "writes one save after 500 turns and puts nothing in the outbox" do
    store = Playing.store
    root = directory
    logs = root / "logs"
    Dir.mkdir_p logs

    recording logs, root do
      run = playing store
      wait run, Play::AUTOSAVE_EVERY - 1
      expect(store.characters).to be_empty

      wait run, 1
      expect(store.characters.size).to eq 1
      expect(saved_turn store).to eq Play::AUTOSAVE_EVERY
      expect(Submit::Outbox.new(root / "outbox").parcels).to be_empty
    end
  end

  it "counts from the last save of any kind" do
    store = Playing.store
    run = playing store
    wait run, 480

    # `>` and `<` save through `#keep` after the staircase action.
    run.play.keep
    wait run, 499
    expect(saved_turn store).to eq 480

    wait run, 1
    expect(saved_turn store).to eq 980
  end

  it "does not stop a rest in progress" do
    store = Playing.store
    run = playing store, clock: true
    wait run, Play::AUTOSAVE_EVERY - 5
    run.game.player.hurt run.game.player.hit_points - 1

    run.press "R"
    while run.play.resting? && run.turn < Play::AUTOSAVE_EVERY
      run.tick
    end

    expect(run.turn).to be >= Play::AUTOSAVE_EVERY
    expect(run.play.resting?).to be_true
    expect(saved_turn store).to eq run.turn
  end

  it "leaves the run as it would have been with no save" do
    kept = playing Playing.store
    unkept = playing

    wait kept, Play::AUTOSAVE_EVERY + 20
    wait unkept, Play::AUTOSAVE_EVERY + 20

    expect(kept.game.turn).to eq unkept.game.turn
    expect(kept.game.fingerprint).to eq unkept.game.fingerprint
  end

  it "writes a pause the next load carries the log on from" do
    store = Playing.store
    root = directory
    logs = root / "logs"
    Dir.mkdir_p logs

    recording logs, root do
      run = playing store
      wait run, Play::AUTOSAVE_EVERY
      Log.ended nil

      held = store.held NAME
      raise "#{store.directory} holds no character called #{NAME}" unless held
      expect(held.replay.try &.pause).to eq 1

      game = held.carried store.path(NAME)
      3.times { game.perform Roguelike::Action::Wait.new }
    end

    file = only logs
    read = Recording.read file
    expect(read.pauses).to eq 1
    expect(read.resumes).to eq 1
    expect(read.rewound).to be_empty
    expect(Verifier.check(file).trouble).to be_nil
  end

  # The periodic save is not sent. A process that goes out from under the
  # run before the next action still sends what was played.
  it "sends the end of the run when the log closes right after it" do
    store = Playing.store
    root = directory
    logs = root / "logs"
    Dir.mkdir_p logs

    recording logs, root do
      run = playing store
      wait run, Play::AUTOSAVE_EVERY
      outbox = Submit::Outbox.new root / "outbox"
      expect(outbox.parcels).to be_empty

      Log.ended nil

      expect(outbox.parcels.map(&.seq)).to eq [2]
      expect(outbox.parcels.first.pieces.map(&.kind)).to eq ["replay", "events", "meta"]
    end

    expect(Recording.read(only logs).footer.try &.outcome).to eq "truncated"
  end

  it "writes nothing when there is no store" do
    root = directory
    logs = root / "logs"
    Dir.mkdir_p logs

    recording logs, root do
      run = playing
      wait run, Play::AUTOSAVE_EVERY
      expect(run.store).to be_nil
    end

    expect(Recording.read(only logs).pauses).to eq 0
  end
end
