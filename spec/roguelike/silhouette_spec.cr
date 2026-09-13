require "../spec_helper"

Spectator.describe "seeing a creature against the light" do
  alias Floor = Roguelike::Floor
  alias Source = Roguelike::LightSource
  alias Vision = Roguelike::Vision

  def spot(lines : Array(String)) : Floor
    Floor.parse "dark", lines
  end

  # A dark corridor running east into a lit room, with a doorway between.
  # The viewer stands at the dark end.
  DOORWAY = [
    "##############",
    "#......'*****#",
    "##############",
  ]

  describe "a creature in a lit doorway" do
    # The room lights its own doorway, so the creature standing in it is lit
    # rather than a shape.
    it "is seen from a dark corridor" do
      floor = spot DOORWAY
      vision = Vision.from floor, 1, 1, [] of Source

      expect(vision.lit? 7, 1).to be_true
      expect(vision.includes? 7, 1).to be_true
      expect(vision.shows? floor, 7, 1).to be_true
    end

    it "is a shape rather than lit one square short of the doorway" do
      floor = spot DOORWAY
      vision = Vision.from floor, 1, 1, [] of Source

      expect(vision.lit? 6, 1).to be_false
      expect(vision.backlit? floor, 6, 1).to be_true
    end
  end

  # The room behind the corridor is lit. A creature standing between the
  # viewer and it shows as a shape.
  LAMPLIGHT = [
    "###############",
    "#.............#",
    "###############",
  ]

  describe "a creature on a dark square" do
    it "is seen when there is light behind them" do
      floor = spot LAMPLIGHT
      vision = Vision.from floor, 1, 1, [Source.new(13, 1, 2)]

      expect(vision.lit? 7, 1).to be_false
      expect(vision.includes? 7, 1).to be_false
      expect(vision.backlit? floor, 7, 1).to be_true
      expect(vision.shows? floor, 7, 1).to be_true
    end

    it "is not seen with nothing behind them" do
      floor = spot LAMPLIGHT
      vision = Vision.from floor, 1, 1, [] of Source

      expect(vision.backlit? floor, 7, 1).to be_false
      expect(vision.shows? floor, 7, 1).to be_false
    end

    # A corner with a wall right behind it has no light to show against.
    it "is not seen in a dark corner" do
      floor = spot [
        "#########",
        "#.......#",
        "#.#####.#",
        "#.#***#.#",
        "#.#####.#",
        "#########",
      ]
      vision = Vision.from floor, 1, 1, [] of Source

      expect(vision.backlit? floor, 7, 4).to be_false
    end

    it "is not seen when a wall stands between them and the light" do
      floor = spot ["###############", "#.....#......*#", "###############"]
      vision = Vision.from floor, 1, 1, [] of Source

      expect(vision.backlit? floor, 4, 1).to be_false
    end

    it "is not seen when the light is too far behind them" do
      floor = Floor.solid "long", 40, 1, Roguelike::Terrain::StoneFloor
      vision = Vision.from floor, 0, 0, [Source.new(38, 0, 2)]

      expect(vision.backlit? floor, 2, 0).to be_false
      expect(Vision::BACKLIGHT).to be < 36
    end

    it "is not seen with no line to them at all" do
      floor = spot ["#########", "#..#***.#", "#########"]
      vision = Vision.from floor, 1, 1, [] of Source

      expect(vision.field.includes?(6, 1)).to be_false
      expect(vision.backlit? floor, 6, 1).to be_false
    end
  end

  describe "a creature on a lit square" do
    # The light on them is enough. There is nothing to show against.
    it "needs no light behind them" do
      floor = spot LAMPLIGHT
      vision = Vision.from floor, 1, 1, [Source.new(7, 1, 3)]

      expect(vision.includes? 7, 1).to be_true
      expect(vision.backlit? floor, 7, 1).to be_false
      expect(vision.shows? floor, 7, 1).to be_true
    end
  end

  describe "the square the viewer stands on" do
    it "is never a silhouette" do
      floor = spot LAMPLIGHT
      vision = Vision.from floor, 1, 1, [Source.new(13, 1, 2)]

      expect(vision.backlit? floor, 1, 1).to be_false
      expect(vision.shows? floor, 1, 1).to be_true
    end
  end

  describe "which square the light is on" do
    # A shape is drawn by the light behind it rather than by any on its own
    # square, so what is drawn has to know which square that is.
    it "answers the first lit square beyond the creature" do
      floor = spot LAMPLIGHT
      vision = Vision.from floor, 1, 1, [Source.new(13, 1, 2)]

      expect(vision.backlight floor, 7, 1).to eq({11, 1})
    end

    it "answers nothing for a creature with no light behind them" do
      floor = spot LAMPLIGHT
      vision = Vision.from floor, 1, 1, [] of Source

      expect(vision.backlight floor, 7, 1).to be_nil
    end

    it "answers nothing for a creature standing in the light" do
      floor = spot DOORWAY
      vision = Vision.from floor, 1, 1, [] of Source

      expect(vision.backlight floor, 7, 1).to be_nil
    end

    it "agrees with Vision#backlit? on every square" do
      floor = spot LAMPLIGHT
      vision = Vision.from floor, 1, 1, [Source.new(13, 1, 3)]

      floor.rows.times do |row|
        floor.columns.times do |column|
          expect(!vision.backlight(floor, column, row).nil?)
            .to eq vision.backlit?(floor, column, row)
        end
      end
    end
  end

  describe "through the game" do
    it "answers for a creature the character could see" do
      floor = Playing.daylight spot(LAMPLIGHT)
      game = Roguelike::Game.new Roguelike::World.new(1_u64, {"dark" => floor}),
        Roguelike::Player.new("dark", 1, 1)

      expect(game.can_see_creature?(7, 1)).to be_true
    end

    it "answers for one it could not" do
      floor = spot LAMPLIGHT
      game = Roguelike::Game.new Roguelike::World.new(1_u64, {"dark" => floor}),
        Roguelike::Player.new("dark", 1, 1)

      expect(game.can_see_creature?(7, 1)).to be_false
    end
  end

  describe "drawn" do
    # A map of what shows and what does not, so a change to the rule reads as
    # a diff of two maps.
    it "draws what it drew last time down a lamplit corridor" do
      floor = spot ["###############", "#.............#", "###############"]
      vision = Vision.from floor, 1, 1, [Source.new(13, 1, 3)]

      drawn = Array.new(floor.rows) do |row|
        String.build(floor.columns) do |io|
          floor.columns.times do |column|
            io << if vision.includes? column, row
              'L'
            elsif vision.backlit? floor, column, row
              'S'
            else
              '.'
            end
          end
        end
      end.join '\n'

      expect(drawn).to eq Fixture.expected("light/silhouettes.txt", drawn)
    end
  end
end
