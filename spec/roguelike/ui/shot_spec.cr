require "../../spec_helper"

Spectator.describe "drawing a shot crossing the floor" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Palette = Roguelike::Ui::Palette

  # One lit hall with the character at the west end and room to shoot east.
  HALL = [
    "############",
    "#<.........#",
    "############",
  ]

  # Where the character stands.
  HERE = {1, 1}

  # A run with the character carrying *items*, on a clock a spec fires by
  # hand.
  #
  # Without a clock the shot lands at once, which is what every other spec in
  # the suite wants. These examples are about the frames in between.
  def hall(items : Array(Item) = [] of Item,
           clock : Bool = true) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)

    player = Roguelike::Player.new "hall", *HERE, hit_points: 500
    items.each { |item| player.inventory.add item }

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}), player),
      80, 24, clock: clock
  end

  # A run with a bow readied and arrows in the quiver.
  def archer(clock : Bool = true) : Playing::Run
    run = hall [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 12)],
      clock: clock
    run.press "w", "a"
    run.press "w", "b"
    run
  end

  # Looses a shot at *steps* squares east of the character.
  #
  # *letter* picks the item out of the list `t` and `z` put up. `f` shoots
  # what is quivered and asks nothing.
  def shoot(run : Playing::Run, key : String, steps : Int32,
            letter : String? = nil) : Nil
    run.press key
    letter.try { |picked| run.press picked }
    steps.times { run.press "l" }
    run.press "Enter"
  end

  # The square the missile is drawn on, or `nil` when none is.
  #
  # The character's own mark is not one: `#refresh` puts that back on every
  # frame whether or not anything is in the air.
  def missile_at(run : Playing::Run) : {Int32, Int32}?
    run.map.marks.each do |spot, _look|
      return spot unless spot == run.at
    end

    nil
  end

  # What the missile in the air is drawn as, or a failure saying there is
  # none in the air.
  def missile_look(run : Playing::Run) : Roguelike::Ui::Look
    spot = missile_at run
    raise "nothing is in the air" unless spot

    found = run.map.mark? spot[0], spot[1]
    raise "nothing is drawn at #{spot}" unless found

    found
  end

  describe "an arrow" do
    it "is drawn on the first square of its path" do
      run = archer
      shoot run, "f", 5

      expect(missile_at run).to eq({2, 1})
    end

    it "moves one square for each tick of the clock" do
      run = archer
      shoot run, "f", 5

      run.tick
      expect(missile_at run).to eq({3, 1})

      run.tick
      expect(missile_at run).to eq({4, 1})
    end

    it "is drawn with its own glyph" do
      run = archer
      shoot run, "f", 5

      expect(missile_look run).to eq Palette.flying(Item.new Kind::Arrow)
    end

    it "is gone once the clock has run out" do
      run = archer
      shoot run, "f", 5
      run.run_timers

      expect(missile_at run).to be_nil
      expect(run.armed).to be_empty
    end

    it "arms one frame a square" do
      run = archer
      shoot run, "f", 5

      # The first square is drawn by the press. The rest are frames.
      expect(run.run_timers).to eq 5
    end

    # The arrow has already landed by the time the first frame is drawn. The
    # picture is a replay, so the run is over either way.
    it "leaves the arrow lying where it stopped" do
      run = archer
      shoot run, "f", 5
      run.run_timers

      expect(run.game.floor.items(6, 1).map &.kind).to contain Kind::Arrow
    end
  end

  describe "a thrown rock" do
    it "is drawn crossing the floor as well" do
      run = hall [Item.new(Kind::Rock, count: 3)]
      shoot run, "t", 4, letter: "a"

      expect(missile_at run).to eq({2, 1})
    end
  end

  describe "a bolt from a wand" do
    it "is drawn as a spark" do
      run = hall [Item.new(Kind::StrikingWand)]
      shoot run, "z", 4, letter: "a"

      expect(missile_look(run).glyph).to eq Palette::BOLT
    end
  end

  describe "a command that let nothing fly" do
    # Reading a scroll at a square sends nothing across the floor, and the
    # shot before it must not be drawn again.
    it "draws nothing" do
      run = archer
      shoot run, "f", 5
      run.run_timers

      run.game.player.inventory.add Item.new(Kind::TeleportScroll)
      run.play.refresh
      run.press "r", "c"
      run.press "Enter"

      expect(missile_at run).to be_nil
    end
  end

  describe "with no clock to arm a frame on" do
    it "lands the shot at once and draws no missile" do
      run = archer clock: false
      shoot run, "f", 5

      expect(missile_at run).to be_nil
      expect(run.game.floor.items(6, 1).map &.kind).to contain Kind::Arrow
    end
  end

  describe "a turn taken while a shot is in the air" do
    it "stops the shot being drawn" do
      run = archer
      shoot run, "f", 5
      run.tick

      run.press "j"
      run.run_timers

      expect(missile_at run).to be_nil
    end
  end
end
