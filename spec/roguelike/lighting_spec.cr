require "../spec_helper"

Spectator.describe Roguelike::Lighting do
  alias Floor = Roguelike::Floor
  alias Lighting = Roguelike::Lighting
  alias Source = Roguelike::LightSource
  alias Terrain = Roguelike::Terrain

  def spot(lines : Array(String)) : Floor
    Floor.parse "light", lines
  end

  # The light over *floor* from *sources*, drawn as levels.
  def levels(floor : Floor, sources : Array(Source)) : String
    Lighting.over(floor, sources).to_levels(floor).join '\n'
  end

  describe "a floor with nothing on it" do
    it "is dark" do
      floor = spot ["...", "...", "..."]
      lighting = Lighting.over floor, [] of Source

      expect(lighting.lit? 1, 1).to be_false
      expect(lighting.level 1, 1).to eq 0
      expect(lighting.size).to eq 0
    end
  end

  describe "one source" do
    # A square next to the flame gets the whole radius. A square at the edge
    # of the reach gets one.
    it "falls off with distance" do
      floor = Floor.solid "open", 9, 1, Terrain::StoneFloor
      lighting = Lighting.over floor, [Source.new(4, 0, 3)]

      expect(lighting.level 4, 0).to eq 4
      expect(lighting.level 5, 0).to eq 3
      expect(lighting.level 6, 0).to eq 2
      expect(lighting.level 7, 0).to eq 1
      expect(lighting.level 8, 0).to eq 0
    end

    it "throws a round pool rather than a square one" do
      floor = Floor.solid "open", 9, 9, Terrain::StoneFloor
      lighting = Lighting.over floor, [Source.new(4, 4, 3)]

      expect(lighting.lit? 7, 4).to be_true
      expect(lighting.lit? 6, 6).to be_true
      expect(lighting.lit? 7, 7).to be_false
    end

    it "lights nothing at all with no radius" do
      floor = Floor.solid "open", 5, 5, Terrain::StoneFloor

      expect(Lighting.over(floor, [Source.new(2, 2, 0)]).size).to eq 0
    end

    # Light does not go round a corner. A torch in one room does not light
    # the room through the wall.
    it "stops at a wall" do
      floor = spot ["#######", "#..#..#", "#######"]
      lighting = Lighting.over floor, [Source.new(1, 1, 5)]

      expect(lighting.lit? 2, 1).to be_true
      expect(lighting.lit? 3, 1).to be_true
      expect(lighting.lit? 4, 1).to be_false
    end

    it "lights the wall faces around it" do
      floor = spot ["###", "#.#", "###"]
      lighting = Lighting.over floor, [Source.new(1, 1, 3)]

      expect(lighting.lit? 1, 0).to be_true
      expect(lighting.lit? 0, 0).to be_true
    end
  end

  describe "two sources" do
    # Light is accumulated rather than replaced. Two torches in one room make
    # a brighter room than one.
    it "add up where they overlap" do
      floor = Floor.solid "open", 9, 1, Terrain::StoneFloor
      one = Lighting.over floor, [Source.new(3, 0, 3)]
      both = Lighting.over floor, [Source.new(3, 0, 3), Source.new(5, 0, 3)]

      expect(both.level 4, 0).to be > one.level(4, 0)
    end
  end

  describe "a source inside a wall" do
    # A wall sconce is one of those. The scan starts one square out, so the
    # squares facing the room are reached and the wall either side is not.
    # The wall either side of it blocks the scan at the first step, so the
    # light goes out in a widening cone rather than a circle. That is what a
    # bracket on a wall does.
    it "throws a cone into the room it faces" do
      floor = spot [
        "#########",
        "####|####",
        "#.......#",
        "#.......#",
        "#.......#",
        "#########",
      ]
      lighting = Lighting.over floor, [Source.new(4, 1, 6)]

      expect(floor.terrain 4, 1).to eq Terrain::UnlitSconce
      expect(lighting.lit? 4, 2).to be_true
      expect(lighting.lit? 7, 4).to be_true
      expect(lighting.lit? 7, 2).to be_false
    end

    it "draws that cone the way it drew it last time" do
      floor = spot [
        "#########",
        "####|####",
        "#.......#",
        "#.......#",
        "#.......#",
        "#########",
      ]
      drawn = Lighting.over(floor, [Source.new(4, 1, 6)]).to_levels(floor).join '\n'

      expect(drawn).to eq Fixture.expected("light/sconce-cone.txt", drawn)
    end
  end

  describe "a floor that glows on its own" do
    it "lights every glowing square" do
      floor = spot ["#####", "#***#", "#####"]

      expect(floor.glow.size).to eq 3
      expect(Lighting.over(floor, [] of Source).lit? 2, 1).to be_true
    end

    # A lit room whose light stopped at its own floor would have a dark hole
    # where each door is.
    it "spills onto a doorway" do
      floor = spot ["#####", "'***#", "#####"]
      lighting = Lighting.over floor, [] of Source

      expect(lighting.lit? 0, 1).to be_true
    end

    it "does not spill through a shut door" do
      floor = spot ["#####", "+***#", "#####"]

      expect(Lighting.over(floor, [] of Source).lit? 0, 1).to be_false
    end

    it "does not spill through a wall" do
      floor = spot ["#####", "#***#", "#####"]

      expect(Lighting.over(floor, [] of Source).lit? 0, 1).to be_false
    end
  end

  describe "a floor with an ambient level" do
    it "lights every square whatever else happens" do
      floor = spot ["###", "#.#", "###"]
      floor.ambient = 1
      lighting = Lighting.over floor, [] of Source

      expect(lighting.lit? 1, 1).to be_true
      expect(lighting.lit? 0, 0).to be_true
      expect(lighting.size).to eq 0
    end

    it "adds to what a source throws" do
      floor = Floor.solid "open", 7, 1, Terrain::StoneFloor
      floor.ambient = 2
      lighting = Lighting.over floor, [Source.new(2, 0, 2)]

      expect(lighting.level 2, 0).to eq 5
      expect(lighting.level 6, 0).to eq 2
    end
  end

  describe "drawn" do
    it "draws what it drew last time for a torch in a room" do
      floor = spot [
        "###########",
        "#.........#",
        "#.........#",
        "#....#....#",
        "#.........#",
        "###########",
      ]
      drawn = Lighting.over(floor, [Source.new(3, 2, 4)]).to_levels(floor).join '\n'

      expect(drawn).to eq Fixture.expected("light/torch-levels.txt", drawn)
    end

    it "draws what it drew last time for the shipped floor with every sconce lit" do
      floor = Roguelike::Floors.proving_ground
      sources = [] of Source

      floor.each do |column, row, tile|
        next unless tile.terrain.sconce?

        floor.set column, row, Terrain::LitSconce
        sources << Source.new(column, row, Roguelike::Terrains::SCONCE_LIGHT)
      end

      drawn = Lighting.over(floor, sources).to_map(floor).join '\n'

      expect(drawn).to eq Fixture.expected("light/sconces.txt", drawn)
    end
  end
end
