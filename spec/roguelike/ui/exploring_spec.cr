require "../../spec_helper"
require "../../support/recording"

Spectator.describe "exploring and travelling from the keyboard" do
  alias Game = Roguelike::Game

  # A lit room with a corridor east of it through an open door. The corridor
  # turns south at its east end, out of sight from the staircase.
  ROOMS = [
    "#################",
    "#....############",
    "#<...'.........##",
    "#....#########.##",
    "##############.##",
    "##############.##",
    "#################",
  ]

  # A short corridor running north into a long one running east. Nothing of
  # the east corridor is in sight from the staircase.
  MEETING = [
    "#########################",
    "#.......................#",
    "########.################",
    "########.################",
    "########<################",
    "#########################",
  ]

  # A run on *lines* with the character on the up staircase.
  def walking(lines : Array(String) = ROOMS) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("rooms", lines)
    run = Playing.open Game.new(
      Roguelike::World.new(Playing::SEED, {"rooms" => floor}),
      Roguelike::Player.new("rooms", *Game.entrance(floor), hit_points: 40)), 60, 20
    run.clear_monsters
    run
  end

  describe "X" do
    it "walks until nothing is left to see" do
      run = walking

      run.press "X"

      expect(run.game.knowledge.seen? 14, 5).to be_true
      expect(run.turn).to be > 0
      expect(run.said).to eq "There is nothing left to see on this floor."
    end

    it "takes no turn where nothing is left to see" do
      run = walking ["######", "#<...#", "######"]

      run.press "X"

      expect(run.turn).to eq 0
      expect(run.said).to eq "There is nothing left to see on this floor."
    end

    it "leaves x as the examine key" do
      run = walking

      run.press "x"

      expect(run.play.examiner.cursoring?).to be_true
      expect(run.turn).to eq 0
    end
  end

  describe "v" do
    # A run on *lines* stopped by `X` when *items* came into sight.
    def sighted(items : Hash({Int32, Int32}, Roguelike::ItemKind),
                lines : Array(String) = ROOMS) : Playing::Run
      run = walking lines
      items.each { |spot, kind| run.game.floor.drop *spot, Roguelike::Item.new(kind) }
      run.game.enroll
      run.press "X"
      run
    end

    it "walks to the item an explore stopped for" do
      run = sighted({ {14, 5} => Roguelike::ItemKind::Dagger })
      expect(run.said).to eq "A dagger comes into sight."

      run.press "v"

      expect(run.at).to eq({14, 5})
    end

    it "walks to two items on two presses, nearest first" do
      run = sighted({ {23, 1} => Roguelike::ItemKind::Dagger, {22, 1} => Roguelike::ItemKind::Mace },
        MEETING)
      expect(run.said).to eq "A mace and a dagger come into sight."

      run.press "v"
      first = run.at
      run.press "v"

      expect(first).to eq({22, 1})
      expect(run.at).to eq({23, 1})
    end

    it "says so once every square has been walked to" do
      run = sighted({ {14, 5} => Roguelike::ItemKind::Dagger })
      run.press "v"
      turn = run.turn

      run.press "v"

      expect(run.said).to eq "There is nothing more to walk to."
      expect(run.turn).to eq turn
    end

    it "says so when explore did not stop for an item" do
      run = walking

      run.press "X", "v"

      expect(run.said).to eq "There is nothing more to walk to."
    end

    it "is listed with X and _ on the help screen" do
      section = walking.play.sections.find! { |found| found.title == "getting about" }

      expect(section.bindings.bindings.map &.to_s).to contain "v"
    end
  end
  describe "_" do
    it "puts the cursor on the map and asks for a square" do
      run = walking

      run.press "_"

      expect(run.play.examiner.cursoring?).to be_true
      expect(run.said).to eq "Pick a square with the movement keys. Enter goes there, Escape stops."
    end

    it "lights the way to the square under the cursor" do
      run = walking

      run.press "_", "l", "l", "l"

      expect(run.map.highlighted? 4, 2).to be_true
      expect(run.map.highlighted? 3, 2).to be_true
      expect(run.turn).to eq 0
    end

    it "walks there on Enter" do
      run = walking

      run.press "_", "l", "l", "l", "j", "Enter"

      expect(run.at).to eq({4, 3})
      expect(run.said).to eq "You arrive."
      expect(run.play.examiner.cursoring?).to be_false
    end

    it "takes the cursor off on Escape" do
      run = walking

      run.press "_", "l", "Escape"

      expect(run.play.examiner.cursoring?).to be_false
      expect(run.at).to eq({1, 2})
      expect(run.turn).to eq 0
    end

    it "takes the cursor off on a second _" do
      run = walking

      run.press "_", "l", "_"

      expect(run.play.examiner.cursoring?).to be_false
      expect(run.said).to eq "Never mind."
      expect(run.turn).to eq 0
    end

    it "records each step as a travel" do
      where = (Recording.directory / "keyboard-#{Random.rand UInt32}.jsonl").to_s

      Recording.recording where do
        run = walking
        run.press "_", "l", "l", "Enter"
        expect(run.at).to eq({3, 2})
        run.game
      end

      acts = Recording.read(where, fingerprints: false).records.compact_map &.as?(Roguelike::Replay::Act)
      expect(acts.map &.action.to_json).to eq [%({"t":"travel","target":[3,2]})] * 2
    end
  end
end
