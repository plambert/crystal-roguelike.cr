require "../spec_helper"

Spectator.describe Roguelike::Terrain do
  describe "the table" do
    it "says what every member is" do
      described_class.each do |terrain|
        expect(Roguelike::Terrains::KINDS.has_key?(terrain)).to be_true
      end
    end

    it "writes every member as a different character" do
      marks = described_class.values.map &.mark

      expect(marks.uniq.size).to eq marks.size
    end

    it "gives every member a label and a description" do
      described_class.each do |terrain|
        expect(terrain.label).not_to be_empty
        expect(terrain.description).not_to be_empty
      end
    end
  end

  describe ".from_mark" do
    it "reads back what every member writes" do
      described_class.each do |terrain|
        expect(described_class.from_mark(terrain.mark)).to eq terrain
      end
    end

    it "reads a blank as rock, so trimming a line cannot change a level" do
      expect(described_class.from_mark(Roguelike::Terrains::FILL))
        .to eq Roguelike::Terrain::Granite
    end

    # A character nobody meant is a mistake in a level. One that quietly
    # became floor would be a hole in a wall that reading the file could not
    # find.
    it "refuses a character nothing is written as" do
      expect { described_class.from_mark('Z') }.to raise_error ArgumentError, /no terrain/
    end

    it "answers nothing rather than raising when asked to" do
      expect(described_class.from_mark?('Z')).to be_nil
    end
  end

  describe "what gets in the way" do
    it "stops movement and sight through every rock" do
      [Roguelike::Terrain::Granite, Roguelike::Terrain::Sandstone, Roguelike::Terrain::Shale].each do |rock|
        expect(rock.blocks_move?).to be_true
        expect(rock.blocks_sight?).to be_true
        expect(rock.passable?).to be_false
        expect(rock.rock?).to be_true
      end
    end

    it "lets both floors through" do
      [Roguelike::Terrain::StoneFloor, Roguelike::Terrain::DirtFloor].each do |floor|
        expect(floor.passable?).to be_true
        expect(floor.blocks_sight?).to be_false
        expect(floor.floor?).to be_true
      end
    end

    it "shuts a closed door and opens an open one" do
      expect(Roguelike::Terrain::ClosedDoor.passable?).to be_false
      expect(Roguelike::Terrain::ClosedDoor.blocks_sight?).to be_true
      expect(Roguelike::Terrain::OpenDoor.passable?).to be_true
      expect(Roguelike::Terrain::OpenDoor.blocks_sight?).to be_false
    end

    it "lets both staircases be stood on" do
      expect(Roguelike::Terrain::StairsUp.passable?).to be_true
      expect(Roguelike::Terrain::StairsDown.passable?).to be_true
    end
  end

  describe "the groups" do
    it "knows a door from anything else" do
      expect(Roguelike::Terrain::ClosedDoor.door?).to be_true
      expect(Roguelike::Terrain::OpenDoor.door?).to be_true
      expect(Roguelike::Terrain::StoneFloor.door?).to be_false
    end

    it "knows a staircase from anything else" do
      expect(Roguelike::Terrain::StairsUp.stairs?).to be_true
      expect(Roguelike::Terrain::StairsDown.stairs?).to be_true
      expect(Roguelike::Terrain::Granite.stairs?).to be_false
    end
  end
end
