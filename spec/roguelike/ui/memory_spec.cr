require "../../spec_helper"

Spectator.describe "what the character remembers" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Ui = Roguelike::Ui

  # Two rooms joined by a corridor longer than a torch reaches. The character
  # starts in the left room with a lit torch.
  HALL = [
    "##################",
    "#...##############",
    "#.<.+............#",
    "#...##############",
    "##################",
  ]

  # Walking east from the up staircase. The second press opens the door and
  # takes a turn without moving, so a walk of *steps* squares needs one more
  # press than that.
  def walk_east(run : Playing::Run, steps : Int32) : Nil
    (steps + 1).times { run.press "l" }
  end

  # The style one cell of the buffer was drawn in. `Cell#style` is an id into
  # the buffer's own table.
  def drawn_style(run : Playing::Run, x : Int32, y : Int32) : TermBuf::Style
    found = run.buffer.hit x, y
    raise "nothing is drawn at #{x},#{y}" unless found

    run.buffer.styles[found.cell.style]
  end

  def walking(lines : Array(String) = HALL) : Playing::Run
    floor = Roguelike::Floor.parse "hall", lines
    player = Roguelike::Player.new "hall", *Roguelike::Game.entrance(floor)
    player.inventory.add Playing.torch

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}), player), 40, 16
  end

  # A corridor with a door in it and no light anywhere.
  #
  # The character carries a torch and puts it out. Nothing is lit after
  # that, so the map holds what they remember and nothing else.
  DARK = [
    "###########",
    "#.<..'....#",
    "###########",
  ]

  def dark_corridor : Playing::Run
    floor = Roguelike::Floor.parse "corridor", DARK
    player = Roguelike::Player.new "corridor", *Roguelike::Game.entrance(floor)
    player.inventory.add Playing.torch

    run = Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"corridor" => floor}), player), 40, 16
    run.press "l"
    run.press "l"
    run.press "a"
    run
  end

  # Where the door stands.
  DOOR = {5, 1}

  describe "a door worked by hand" do
    it "is remembered shut once it has been shut" do
      run = dark_corridor
      expect(run.game.knowledge[DOOR].try &.terrain).to eq Roguelike::Terrain::OpenDoor

      run.press "c"

      expect(run.game.sight.includes?(*DOOR)).to be_false
      expect(run.game.knowledge[DOOR].try &.terrain).to eq Roguelike::Terrain::ClosedDoor
    end

    it "is remembered open once it has been opened again" do
      run = dark_corridor
      run.press "c"
      run.press "o"

      expect(run.game.knowledge[DOOR].try &.terrain).to eq Roguelike::Terrain::OpenDoor
    end

    it "draws the shut door on the map" do
      run = dark_corridor
      run.press "c"
      run.render

      spot = run.map.screen_of(*DOOR)
      raise "the door is off the window" unless spot

      expect(run.rows[spot[1]][spot[0]]).to eq '+'
    end

    # Working a latch says nothing about what is on the floor the other side
    # of it.
    it "learns nothing of what is lying on the square" do
      run = dark_corridor
      run.game.floor.drop DOOR[0], DOOR[1], Item.new Kind::LongSword

      run.press "c"

      expect(run.game.knowledge[DOOR].try &.item).to be_nil
    end
  end

  describe "a sconce worked by hand" do
    SCONCE = [
      "#######",
      "#.<.|.#",
      "#######",
    ]

    def beside_it : Playing::Run
      floor = Roguelike::Floor.parse "room", SCONCE
      player = Roguelike::Player.new "room", *Roguelike::Game.entrance(floor)
      player.inventory.add Playing.torch

      run = Playing.open Roguelike::Game.new(
        Roguelike::World.new(Playing::SEED, {"room" => floor}), player), 40, 16
      run.press "l"
      run
    end

    # The character carries a torch and stands beside a sconce, so `a` has
    # two things to offer and puts a menu up. The torch is the first row and
    # the sconce the second.
    def work_the_torch(run : Playing::Run) : Nil
      run.press "a"
      run.press "a"
    end

    # :ditto:
    def work_the_sconce(run : Playing::Run) : Nil
      run.press "a"
      run.press "b"
    end

    it "is remembered alight once it has been lit" do
      run = beside_it
      work_the_sconce run

      fitting = run.game.knowledge[{4, 1}].try &.fixture
      expect(fitting.try &.lit?).to be_true
    end

    # This is the one the light cannot do on its own. The square goes dark
    # the moment the sconce does, so nothing looks at it again.
    it "is remembered out once it has been put out" do
      run = beside_it
      work_the_torch run
      work_the_sconce run
      work_the_sconce run

      expect(run.game.floor.fixture(4, 1).try &.lit?).to be_false
      expect(run.game.sight.includes? 4, 1).to be_false

      fitting = run.game.knowledge[{4, 1}].try &.fixture
      expect(fitting.try &.lit?).to be_false
    end
  end

  describe "a room walked through" do
    # Its shape stays on the map after the character has gone.
    it "keeps its shape on the map" do
      run = walking

      walk_east run, 14

      expect(run.at).to eq({16, 2})
      expect(run.game.sight.includes?(1, 1)).to be_false
      expect(run.game.knowledge.seen?(1, 1)).to be_true
      expect(run.row(1)[1]).to eq '.'
    end

    # The gap between remembered and the dimmest lit square has to be wider
    # than any gap inside the lit range. A square drawn from memory is not a
    # dimly lit square, and it has to read as something else at a glance.
    it "is drawn further from the dimmest lit square than one lit step" do
      base = Ui::Palette::STONE
      shades = (0..Ui::Palette::RAMP.top).map do |step|
        Ui::Palette::RAMP[base, step].foreground.red
      end

      remembered = shades[1] - shades[0]
      inside = (1...shades.size - 1).map { |step| shades[step + 1] - shades[step] }

      expect(remembered).to be > inside.max
    end

    # A torch reaches the top, so the colour at the top of the ramp is one
    # somebody sees rather than one nothing ever draws.
    it "is drawn at the top of the ramp beside a torch" do
      expect(Ui::Palette.step 6).to eq Ui::Palette::RAMP.top
      expect(Ui::Palette.step 1).to eq Ui::Palette::REMEMBERED + 1
      expect(Ui::Palette.step 0).to eq Ui::Palette::REMEMBERED
    end

    it "is drawn dimmer than the square the character stands on" do
      run = walking

      walk_east run, 14

      here = drawn_style run, 16, 2
      away = drawn_style run, 1, 1

      expect(away).not_to eq here
      expect(away.foreground.red).to be < here.foreground.red

      # Far enough apart to tell at a glance rather than by measuring.
      expect(here.foreground.red - away.foreground.red).to be > 30
    end

    it "draws nothing for a square never seen" do
      run = walking

      expect(run.game.knowledge.seen?(16, 2)).to be_false
      expect(run.row(2)[16]?).to be_nil
    end
  end

  describe "an item in a room walked out of" do
    # It is remembered as it was and not updated while out of sight.
    it "stays where it was after it is taken away" do
      run = walking
      run.game.floor.drop 1, 1, Item.new Kind::Dagger
      run.play.refresh
      run.render

      walk_east run, 14
      expect(run.row(1)[1]).to eq ')'

      run.game.floor.clear_items 1, 1
      run.play.refresh
      run.render

      expect(run.game.floor.items(1, 1)).to be_empty
      expect(run.row(1)[1]).to eq ')'
    end

    it "is forgotten once the character sees it gone" do
      run = walking
      run.game.floor.drop 1, 1, Item.new Kind::Dagger
      run.play.refresh
      run.render
      expect(run.row(1)[1]).to eq ')'

      run.game.floor.clear_items 1, 1
      run.play.refresh
      run.render

      expect(run.row(1)[1]).to eq '.'
    end
  end

  describe "a door shut behind the character" do
    it "is remembered open until it is seen again" do
      run = walking

      walk_east run, 14
      run.game.floor.set 4, 2, Roguelike::Terrain::ClosedDoor
      run.play.refresh
      run.render

      expect(run.game.knowledge[4, 2].try &.terrain).to eq Roguelike::Terrain::OpenDoor
      expect(run.row(2)[4]).to eq '\''
    end
  end

  # A blend computing a colour per cell interns a style per cell, and a style
  # table only grows. The ramp answers the same style for the same step every
  # time, so the table settles.
  describe "the style table" do
    it "stops growing once the walk has covered the map once" do
      run = walking [
        "####################",
        "#..................#",
        "#.<................#",
        "#..................#",
        "####################",
      ]

      # One pass each way puts every look at every step it will ever reach.
      18.times { run.press "l" }
      18.times { run.press "h" }
      settled = run.buffer.styles.size

      4.times do
        18.times { run.press "l" }
        18.times { run.press "h" }
      end

      expect(run.buffer.styles.size).to eq settled
    end

    it "settles at a size a person could count" do
      run = walking

      walk_east run, 14

      expect(run.buffer.styles.size).to be < 60
    end
  end

  describe "Game#look" do
    it "records what it answers" do
      run = walking
      run.game.knowledge.forget

      seen = run.game.look

      expect(run.game.knowledge.size).to eq seen.size
    end

    it "stamps the turn a square was seen on" do
      run = walking

      run.press "o"
      run.press "l"

      expect(run.game.knowledge[3, 2].try &.turn).to eq run.turn
    end
  end

  describe "Game#sight" do
    # A spec reading the field of view should not change what is remembered.
    it "records nothing" do
      run = walking
      run.game.knowledge.forget

      run.game.sight

      expect(run.game.knowledge.empty?).to be_true
    end
  end

  describe "the examine pane" do
    it "says what a remembered square looked like" do
      run = walking
      walk_east run, 14

      run.hover 1, 1

      expect(run.examine.what.text).to eq "stone floor"
      expect(run.examine.detail.text).to eq Ui::ExaminePane::REMEMBERED
    end

    it "names what was lying there when it was last seen" do
      run = walking
      run.game.floor.drop 1, 1, Item.new Kind::Dagger
      run.play.refresh
      walk_east run, 14
      run.game.floor.clear_items 1, 1
      run.play.refresh
      run.render

      run.hover 1, 1

      expect(run.examine.litter.hidden?).to be_false
      expect(run.examine.litter.text).to contain "dagger"
    end

    it "still refuses a square the character has never seen" do
      run = walking

      run.hover 16, 2

      expect(run.examine.what.text).to eq Ui::ExaminePane::UNSEEN
      expect(run.examine.detail.text).to be_empty
    end

    it "says what is there now for a square in sight" do
      run = walking

      run.hover 2, 2

      expect(run.examine.what.text).to eq "staircase up"
      expect(run.examine.detail.text).not_to eq Ui::ExaminePane::REMEMBERED
    end
  end

  describe "drawn" do
    it "draws what it drew last time from the far room" do
      run = walking
      walk_east run, 14
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/remembered.txt", drawn)
    end
  end
end
