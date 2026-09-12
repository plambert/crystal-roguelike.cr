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

  describe "a source bolted to a wall" do
    # A bracket on a wall throws light away from that wall, not all round it.
    BRACKET = [
      "#########",
      "#...|...#",
      "#.......#",
      "#.......#",
      "#.......#",
      "#########",
    ]

    it "throws light away from the wall and not back into it" do
      floor = spot BRACKET
      lighting = Lighting.over floor,
        [Source.new(4, 1, 6, facing: Roguelike::Direction::North)]

      expect(lighting.lit? 4, 4).to be_true
      expect(lighting.lit? 1, 4).to be_true
      expect(lighting.lit? 8, 0).to be_false
    end

    # The squares touching the bracket are lit either way, the wall it is
    # bolted to included. A dark bracket on a lit wall would read as a hole.
    it "lights the wall it is bolted to" do
      floor = spot BRACKET
      lighting = Lighting.over floor,
        [Source.new(4, 1, 6, facing: Roguelike::Direction::North)]

      expect(lighting.lit? 4, 0).to be_true
      expect(lighting.lit? 3, 0).to be_true
    end

    it "throws light every way with no wall behind it" do
      floor = spot BRACKET

      expect(Lighting.over(floor, [Source.new(4, 1, 6)]).lit? 8, 0).to be_true
    end

    it "draws that half the way it drew it last time" do
      floor = spot BRACKET
      drawn = Lighting.over(floor,
        [Source.new(4, 1, 6, facing: Roguelike::Direction::North)])
        .to_levels(floor).join '\n'

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

    # A room lights its own walls and its own doors. Standing in a lit room,
    # a person sees where the room ends.
    it "lights a shut door in its own wall" do
      floor = spot ["#####", "+***#", "#####"]

      expect(Lighting.over(floor, [] of Source).lit? 0, 1).to be_true
    end

    it "lights its own walls" do
      floor = spot ["#####", "#***#", "#####"]
      lighting = Lighting.over floor, [] of Source

      expect(lighting.lit? 0, 1).to be_true
      expect(lighting.lit? 1, 0).to be_true
      expect(lighting.lit? 4, 2).to be_true
    end

    # The spill reaches one square. The corridor behind the wall stays dark.
    it "does not reach past its own wall" do
      floor = spot ["#######", "#***#.#", "#######"]
      lighting = Lighting.over floor, [] of Source

      expect(lighting.lit? 4, 1).to be_true
      expect(lighting.lit? 5, 1).to be_false
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

      floor.each_fixture do |column, row, fitting|
        fitting.kindle
        sources << Source.new(column, row, fitting.light, facing: fitting.attached)
      end

      drawn = Lighting.over(floor, sources).to_map(floor).join '\n'

      expect(drawn).to eq Fixture.expected("light/sconces.txt", drawn)
    end
  end
end
