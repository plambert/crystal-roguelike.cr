require "../spec_helper"

Spectator.describe Roguelike::Floor do
  alias Terrain = Roguelike::Terrain

  # Small enough to read. It holds one square of every terrain that
  # matters.
  SAMPLE = <<-MAP
    #####
    #.<+=
    #,,,%
    ##>##
    MAP

  subject(floor) { described_class.parse "sample", SAMPLE }

  describe ".parse" do
    it "is as wide as its widest row and as tall as it has rows" do
      expect(floor.size).to eq({5, 4})
    end

    it "reads every character as the terrain it is written as" do
      expect(floor.terrain(0, 0)).to eq Terrain::Granite
      expect(floor.terrain(1, 1)).to eq Terrain::StoneFloor
      expect(floor.terrain(2, 1)).to eq Terrain::StairsUp
      expect(floor.terrain(3, 1)).to eq Terrain::ClosedDoor
      expect(floor.terrain(4, 1)).to eq Terrain::Sandstone
      expect(floor.terrain(1, 2)).to eq Terrain::DirtFloor
      expect(floor.terrain(4, 2)).to eq Terrain::Shale
      expect(floor.terrain(2, 3)).to eq Terrain::StairsDown
    end

    it "takes the name it is given" do
      expect(floor.id).to eq "sample"
    end

    # An editor that trims trailing whitespace must not change a floor. It
    # must not turn a wall into an error. It must not turn a wall into
    # something else.
    it "fills a short row out with rock" do
      ragged = described_class.parse "ragged", ["#####", "#.", "#####"]

      expect(ragged.size).to eq({5, 3})
      expect(ragged.terrain(4, 1)).to eq Terrain::Granite
    end

    it "refuses a character nothing is written as" do
      expect { described_class.parse "bad", "##\n#Z" }
        .to raise_error ArgumentError, /no terrain/
    end

    it "refuses a floor with nothing in it" do
      expect { described_class.parse "empty", "" }.to raise_error ArgumentError, /no rows/
    end

    it "ignores the blank lines around a file" do
      spaced = described_class.parse "spaced", "\n##\n##\n\n"

      expect(spaced.size).to eq({2, 2})
    end
  end

  describe ".load" do
    it "takes its name from the file" do
      loaded = described_class.load "data/floors/proving-ground.map"

      expect(loaded.id).to eq "proving-ground"
    end
  end

  describe ".solid" do
    it "is rock all the way through" do
      solid = described_class.solid "quarry", 4, 3

      expect(solid.size).to eq({4, 3})
      expect(solid.terrain(2, 1)).to eq Terrain::Granite
    end
  end

  describe "#contains?" do
    it "knows its own edges" do
      expect(floor.contains?(0, 0)).to be_true
      expect(floor.contains?(4, 3)).to be_true
      expect(floor.contains?(5, 3)).to be_false
      expect(floor.contains?(0, 4)).to be_false
      expect(floor.contains?(-1, 0)).to be_false
    end
  end

  describe "#passable?" do
    it "answers the terrain" do
      expect(floor.passable?(1, 1)).to be_true
      expect(floor.passable?(0, 0)).to be_false
      expect(floor.passable?(3, 1)).to be_false
    end

    # Off the floor is rock as far as anything walking is concerned, so
    # nothing has to check the edges before it checks the square.
    it "says no to somewhere off the floor" do
      expect(floor.passable?(-1, 0)).to be_false
      expect(floor.passable?(99, 99)).to be_false
    end
  end

  describe "#blocks_sight?" do
    it "answers the terrain" do
      expect(floor.blocks_sight?(1, 1)).to be_false
      expect(floor.blocks_sight?(0, 0)).to be_true
    end

    it "says yes to somewhere off the floor" do
      expect(floor.blocks_sight?(-1, 0)).to be_true
    end
  end

  describe "#set" do
    it "changes one square and leaves the rest" do
      floor.set 3, 1, Terrain::OpenDoor

      expect(floor.terrain(3, 1)).to eq Terrain::OpenDoor
      expect(floor.passable?(3, 1)).to be_true
      expect(floor.terrain(2, 1)).to eq Terrain::StairsUp
    end
  end

  describe "#find" do
    it "answers where a terrain is" do
      expect(floor.find(Terrain::StairsUp)).to eq({2, 1})
      expect(floor.find(Terrain::StairsDown)).to eq({2, 3})
    end

    it "answers nothing when there is none" do
      expect(floor.find(Terrain::OpenDoor)).to be_nil
    end
  end

  describe "#each" do
    it "walks every square in reading order" do
      seen = [] of {Int32, Int32}
      floor.each { |column, row, _tile| seen << {column, row} }

      expect(seen.size).to eq 20
      expect(seen.first).to eq({0, 0})
      expect(seen[5]).to eq({0, 1})
      expect(seen.last).to eq({4, 3})
    end
  end

  describe "#to_map" do
    it "writes back what it read" do
      expect(floor.to_map.join('\n')).to eq SAMPLE
    end

    it "writes a changed square as its new terrain" do
      floor.set 3, 1, Terrain::OpenDoor

      expect(floor.to_map[1]).to eq "#.<'="
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      again = described_class.from_json floor.to_json

      expect(again).to eq floor
      expect(again.id).to eq floor.id
      expect(again.to_map).to eq floor.to_map
    end

    it "stores the map as text, one string per row" do
      stored = JSON.parse floor.to_json

      expect(stored["id"]).to eq "sample"
      expect(stored["map"].as_a.map(&.as_s)).to eq SAMPLE.lines
    end

    it "round-trips the floor the game ships" do
      shipped = Roguelike::Floors.proving_ground

      expect(described_class.from_json(shipped.to_json)).to eq shipped
    end
  end

  describe "the floor the game ships" do
    subject(shipped) { Roguelike::Floors.proving_ground }

    it "is the size the file is" do
      expect(shipped.size).to eq({72, 28})
    end

    it "has both staircases" do
      expect(shipped.find(Terrain::StairsUp)).not_to be_nil
      expect(shipped.find(Terrain::StairsDown)).not_to be_nil
    end

    it "has all three rocks in it" do
      seen = Set(Terrain).new
      shipped.each { |_column, _row, tile| seen << tile.terrain }

      expect(seen).to contain Terrain::Granite
      expect(seen).to contain Terrain::Sandstone
      expect(seen).to contain Terrain::Shale
    end

    it "has one of every terrain in it, so nothing goes untried" do
      seen = Set(Terrain).new
      shipped.each { |_column, _row, tile| seen << tile.terrain }

      expect(seen.size).to eq Terrain.values.size
    end

    it "is walled all the way round" do
      columns, rows = shipped.size

      columns.times do |column|
        expect(shipped.passable?(column, 0)).to be_false
        expect(shipped.passable?(column, rows - 1)).to be_false
      end

      rows.times do |row|
        expect(shipped.passable?(0, row)).to be_false
        expect(shipped.passable?(columns - 1, row)).to be_false
      end
    end

    it "is the same as the file it was built from" do
      expect(shipped).to eq described_class.load("data/floors/proving-ground.map")
    end
  end
end
