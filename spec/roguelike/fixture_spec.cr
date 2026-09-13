require "../spec_helper"

Spectator.describe Roguelike::Fixture do
  alias Direction = Roguelike::Direction
  alias Fitting = Roguelike::Fixture
  alias Kind = Roguelike::FixtureKind

  it "starts unlit and standing free" do
    fitting = described_class.new

    expect(fitting.lit?).to be_false
    expect(fitting.attached).to be_nil
    expect(fitting.mounted?).to be_false
    expect(fitting.light).to eq 0
  end

  describe "light" do
    it "throws the whole radius bolted to a wall" do
      fitting = described_class.new Kind::Sconce, true, Direction::North

      expect(fitting.light).to eq Kind::Sconce.light
    end

    # A flame up on a wall clears the furniture. The same flame at ankle
    # height does not.
    it "throws less standing on its own foot" do
      fitting = described_class.new Kind::Sconce, true

      expect(fitting.light).to eq Kind::Sconce.light - Fitting::FLOOR_PENALTY
    end

    it "throws none while it is out" do
      expect(described_class.new(Kind::Sconce, false, Direction::North).light).to eq 0
    end
  end

  describe "#kindle and #douse" do
    it "lights and puts out" do
      fitting = described_class.new

      expect(fitting.kindle).to be_true
      expect(fitting.lit?).to be_true
      expect(fitting.kindle).to be_false

      expect(fitting.douse).to be_true
      expect(fitting.lit?).to be_false
      expect(fitting.douse).to be_false
    end
  end

  describe "the words" do
    it "says whether it is alight" do
      expect(described_class.new.label).to eq "sconce"
      expect(described_class.new(Kind::Sconce, true).label).to eq "lit sconce"
    end

    it "says whether it is on a wall or on the floor" do
      expect(described_class.new(Kind::Sconce, false, Direction::North).description)
        .to contain "bracket on the wall"
      expect(described_class.new.description).to contain "stand"
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      fitting = described_class.new Kind::Sconce, true, Direction::SouthWest
      again = described_class.from_json fitting.to_json

      expect(again).to eq fitting
      expect(again.attached).to eq Direction::SouthWest
    end
  end

  describe "read off a floor file" do
    it "stands on the open square rather than in the wall" do
      floor = Roguelike::Floor.parse "room", ["#####", "#.|.#", "#...#", "#####"]

      expect(floor.terrain 2, 1).to eq Roguelike::Terrain::StoneFloor
      expect(floor.fixture(2, 1).try &.kind).to eq Kind::Sconce
      expect(floor.fixture 2, 0).to be_nil
    end

    it "is bolted to the one wall touching it" do
      floor = Roguelike::Floor.parse "room", ["#####", "#.|.#", "#...#", "#####"]

      expect(floor.fixture(2, 1).try &.attached).to eq Direction::North
    end

    it "stands free where more than one wall touches it" do
      floor = Roguelike::Floor.parse "hall", ["###", "#|#", "#.#", "###"]

      expect(floor.fixture(1, 1).try &.attached).to be_nil
    end

    it "stands free where no wall touches it" do
      floor = Roguelike::Floor.parse "room", ["#####", "#...#", "#.|.#", "#...#", "#####"]

      expect(floor.fixture(1, 2)).to be_nil
      expect(floor.fixture(2, 2).try &.attached).to be_nil
    end

    it "reads the lit mark as one already alight" do
      floor = Roguelike::Floor.parse "room", ["#####", "#.!.#", "#...#", "#####"]

      expect(floor.fixture(2, 1).try &.lit?).to be_true
    end

    # A mark that is not terrain does not say what the square under it is made
    # of, so the square beside it does.
    it "stands on the same floor as the squares beside it" do
      stone = Roguelike::Floor.parse "stone", ["#####", "#.|.#", "#####"]
      dirt = Roguelike::Floor.parse "dirt", ["#####", "#,|,#", "#####"]

      expect(stone.terrain 2, 1).to eq Roguelike::Terrain::StoneFloor
      expect(dirt.terrain 2, 1).to eq Roguelike::Terrain::DirtFloor
    end

    it "does the same for a square that glows" do
      dirt = Roguelike::Floor.parse "dirt", ["#####", "#,*,#", "#####"]

      expect(dirt.terrain 2, 1).to eq Roguelike::Terrain::DirtFloor
      expect(dirt.glow_at 2, 1).to be > 0
    end

    it "falls back to stone where nothing beside it is ground" do
      floor = Roguelike::Floor.parse "odd", ["###", "#|#", "###"]

      expect(floor.terrain 1, 1).to eq Roguelike::Terrain::StoneFloor
    end

    it "writes the plain terrain back out" do
      floor = Roguelike::Floor.parse "dirt", ["#####", "#,|,#", "#####"]

      expect(floor.to_map).to eq ["#####", "#,,,#", "#####"]
    end

    it "keeps the fixtures through JSON" do
      floor = Roguelike::Floor.parse "room", ["#####", "#.!.#", "#...#", "#####"]
      again = Roguelike::Floor.from_json floor.to_json

      expect(again).to eq floor
      expect(again.fixture(2, 1).try &.lit?).to be_true
      expect(again.fixture(2, 1).try &.attached).to eq Direction::North
    end
  end

  describe "on the shipped floor" do
    it "stands every sconce on ground somebody could walk on" do
      floor = Roguelike::Floors.proving_ground

      expect(floor.fixtures.size).to eq 7

      floor.each_fixture do |column, row, _fitting|
        expect(floor.terrain(column, row).floor?).to be_true
      end
    end

    # Six are bolted to a wall. The seventh stands on its own foot in the
    # middle of the long corridor, where a wall touches it on both sides and
    # neither is the one it hangs on.
    it "bolts six of them to a wall and stands one free" do
      floor = Roguelike::Floors.proving_ground
      mounted = [] of {Int32, Int32}
      standing = [] of {Int32, Int32}

      floor.each_fixture do |column, row, fitting|
        (fitting.mounted? ? mounted : standing) << {column, row}
      end

      expect(mounted.size).to eq 6
      expect(standing).to eq [{50, 20}]
    end

    it "stands two of them on the dirt of the second room" do
      floor = Roguelike::Floors.proving_ground
      dirt = [] of {Int32, Int32}

      floor.each_fixture do |column, row, _fitting|
        dirt << {column, row} if floor.terrain(column, row).dirt_floor?
      end

      expect(dirt.size).to eq 2
    end
  end
end
