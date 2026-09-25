require "../../spec_helper"

Spectator.describe "aiming" do
  alias Aiming = Roguelike::Ui::Aiming
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Palette = Roguelike::Ui::Palette
  alias Species = Roguelike::Species

  # One lit hall with the character at the west end.
  #
  # The pillar on row 3 is what a shot with something in the way meets. Row 1
  # is clear the whole way.
  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "#....#.....#",
    "#..........#",
    "############",
  ]

  # Where the character stands.
  HERE = {1, 1}

  # A run with the character carrying *items* and *monsters* on the floor.
  def hall(items : Array(Item) = [] of Item,
           monsters : Array(Monster) = [] of Monster) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)
    monsters.each { |creature| floor.place creature }

    player = Roguelike::Player.new "hall", *HERE, hit_points: 500
    items.each { |item| player.inventory.add item }

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}), player)
  end

  # A goblin standing at *at*, asleep.
  def goblin(at : {Int32, Int32}) : Monster
    Monster.new Species::Goblin, at[0], at[1], "band-#{at[0]}", hit_points: 200
  end

  # A run with a bow readied and arrows in the quiver.
  #
  # Any *monsters* go on the floor after the turns readying costs. A creature
  # placed before them would have walked two squares by the time the first
  # shot goes.
  def archer(monsters : Array(Monster) = [] of Monster) : Playing::Run
    run = hall [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 12)]
    run.press "w", "a"
    run.press "w", "b"

    monsters.each { |creature| run.game.floor.place creature }
    run.play.refresh
    run.render
    run
  end

  describe "f" do
    it "says so when nothing is readied to shoot with" do
      run = hall [Item.new(Kind::Arrow, count: 5)]

      run.press "f"

      expect(run.said).to contain "nothing readied"
      expect(run.play.aiming).to be_nil
    end

    it "says so when the quiver is empty, and costs no turn" do
      run = hall [Item.new(Kind::Bow)]
      run.press "w", "a"
      before = run.turn

      run.press "f"

      expect(run.said).to contain "quiver is empty"
      expect(run.turn).to eq before
      expect(run.play.aiming).to be_nil
    end

    it "puts the targeting cursor on the map" do
      run = archer

      run.press "f"

      expect(run.play.aiming).to eq Aiming::Fire
      expect(run.examiner.cursoring?).to be_true
    end

    it "starts on the character when there is nothing to shoot at" do
      run = archer

      run.press "f"

      expect(run.examiner.spot).to eq HERE
    end

    it "starts on the nearest monster in sight" do
      run = archer [goblin({8, 1}), goblin({4, 1})]

      run.press "f"

      expect(run.examiner.spot).to eq({4, 1})
    end
  end

  describe "the line it draws" do
    it "colors every square the shot would cross" do
      run = archer
      run.press "f"
      4.times { run.press "l" }

      expect(run.map.flight.keys).to contain({2, 1})
      expect(run.map.flight.keys).to contain({5, 1})
    end

    it "colors the square the shot stops on differently" do
      run = archer
      run.press "f"
      4.times { run.press "l" }

      expect(run.map.flight[{5, 1}]?).to eq Palette::IMPACT
      expect(run.map.flight[{4, 1}]?).to eq Palette::FLIGHT
    end

    it "says the shot is clear" do
      run = archer
      run.press "f"
      4.times { run.press "l" }

      expect(run.examine.aim.text).to contain "clear"
    end

    # The pillar stands at column 5 of row 3. A shot along that row from the
    # west wall meets it.
    it "says so when a wall is in the way" do
      run = archer
      2.times { run.press "j" }
      run.press "f"
      6.times { run.press "l" }

      expect(run.examine.aim.text).to contain "in the way"
    end

    it "says so when a monster is in the way" do
      run = archer [goblin({4, 1})]
      run.press "f"
      6.times { run.press "l" }

      expect(run.examine.aim.text).to contain "goblin is in the way"
    end

    it "takes the line off when the cursor comes off the map" do
      run = archer
      run.press "f"
      run.press "Escape"

      expect(run.map.flight.empty?).to be_true
      expect(run.examine.aim.hidden?).to be_true
    end
  end

  # A creature made out only as a shape can still be shot at. A person can
  # see something standing in a doorway without being told what it is.
  describe "aiming at a shape against the light" do
    # The hall with no light of its own and a lit square at the east end.
    DARK = [
      "############",
      "#<.....g..*#",
      "############",
    ]

    # A run on `DARK` with a bow readied, and nothing lighting the character.
    def in_the_dark : Playing::Run
      floor = Roguelike::Floor.parse "dark", DARK
      player = Roguelike::Player.new floor.id, 1, 1, hit_points: 500
      [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 12)].each do |item|
        player.inventory.add item
      end

      run = Playing.open Roguelike::Game.new(
        Roguelike::World.new(Playing::SEED, {floor.id => floor}), player)
      run.press "w", "a"
      run.press "w", "b"

      run.game.floor.place Monster.new(Species::Goblin, 7, 1, "band-one",
        hit_points: 200)
      run.play.refresh
      run.render
      run
    end

    it "is drawn as a shape rather than as a goblin" do
      run = in_the_dark

      expect(run.game.sight.includes? 7, 1).to be_false
      expect(run.game.sight.backlit? run.game.floor, 7, 1).to be_true
      expect(run.row(1)[7]).to eq Roguelike::Size::Small.glyph
    end

    it "is what f aims at" do
      run = in_the_dark

      run.press "f"

      expect(run.examiner.spot).to eq({7, 1})
    end

    it "is what Tab cycles to" do
      run = in_the_dark
      run.press "f"
      run.press "l"

      run.press "Tab"

      expect(run.examiner.spot).to eq({7, 1})
    end

    it "takes the arrow" do
      run = in_the_dark

      run.press "f"
      run.press "Enter"

      expect(run.log.join " ").to match /arrow (hits|misses) the goblin/
      expect(run.game.player.quivered.try &.count).to eq 11
    end

    it "takes a thrown rock as well" do
      run = in_the_dark
      run.game.player.inventory.add Item.new(Kind::Rock, count: 3)
      # Anything put into a run by hand has no id until this runs, and an
      # action names an item by its id.
      run.game.enrol
      run.play.refresh

      run.press "t", "c"
      run.press "Enter"

      expect(run.log.join " ").to match /rock (hits|misses) the goblin/
    end
  end

  describe "the movement keys while aiming" do
    it "moves the cursor rather than the character" do
      run = archer
      run.press "f"
      run.press "l"

      expect(run.examiner.spot).to eq({2, 1})
      expect(run.at).to eq HERE
    end
  end

  describe "Tab" do
    it "does nothing while nothing is being aimed" do
      run = archer [goblin({4, 1})]

      run.press "Tab"

      expect(run.examiner.cursoring?).to be_false
    end

    it "moves to the next monster in sight" do
      run = archer [goblin({4, 1}), goblin({8, 1})]

      run.press "f"
      run.press "Tab"

      expect(run.examiner.spot).to eq({8, 1})
    end

    it "comes round to the first one again" do
      run = archer [goblin({4, 1}), goblin({8, 1})]

      run.press "f"
      run.press "Tab", "Tab"

      expect(run.examiner.spot).to eq({4, 1})
    end
  end

  describe "Enter" do
    it "does nothing while nothing is being aimed" do
      run = archer
      before = run.turn

      run.press "Enter"

      expect(run.turn).to eq before
    end

    it "looses the shot and takes the cursor off" do
      run = archer
      run.press "f"
      4.times { run.press "l" }
      run.press "Enter"

      expect(run.play.aiming).to be_nil
      expect(run.examiner.cursoring?).to be_false
      expect(run.game.player.quivered.try &.count).to eq 11
    end

    it "puts the arrow on the square the shot stopped on" do
      run = archer
      run.press "f"
      4.times { run.press "l" }
      run.press "Enter"

      expect(run.game.floor.items(5, 1).map &.kind).to contain Kind::Arrow
    end

    it "shoots the monster it is aimed at" do
      run = archer [goblin({4, 1})]
      run.press "f"
      run.press "Enter"

      expect(run.log.join " ").to match /arrow (hits|misses) the goblin/
    end
  end

  describe "f pressed a second time" do
    it "looses the shot" do
      run = archer
      run.press "f"
      4.times { run.press "l" }
      run.press "f"

      expect(run.play.aiming).to be_nil
      expect(run.game.player.quivered.try &.count).to eq 11
    end
  end

  describe "Escape" do
    it "stops aiming and costs no turn" do
      run = archer
      run.press "f"
      before = run.turn

      run.press "Escape"

      expect(run.play.aiming).to be_nil
      expect(run.examiner.cursoring?).to be_false
      expect(run.turn).to eq before
      expect(run.game.player.quivered.try &.count).to eq 12
    end
  end

  describe "t" do
    it "says so when the character is carrying nothing" do
      run = hall

      run.press "t"

      expect(run.said).to contain "nothing to throw"
      expect(run.play.aiming).to be_nil
    end

    it "asks what to throw" do
      run = hall [Item.new(Kind::Dart, count: 4)]

      run.press "t"

      expect(run.menu.showing?).to be_true
    end

    it "aims once something is chosen" do
      run = hall [Item.new(Kind::Dart, count: 4)]

      run.press "t"
      run.press "a"

      expect(run.play.aiming).to eq Aiming::Throw
      expect(run.examiner.cursoring?).to be_true
    end

    it "throws one of the stack" do
      run = hall [Item.new(Kind::Dart, count: 4)]

      run.press "t"
      run.press "a"
      4.times { run.press "l" }
      run.press "Enter"

      expect(run.game.player.inventory['a'].try &.count).to eq 3
      expect(run.game.floor.items(5, 1).map &.kind).to contain Kind::Dart
    end
  end
end
