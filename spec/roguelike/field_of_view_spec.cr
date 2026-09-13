require "../spec_helper"

Spectator.describe Roguelike::FieldOfView do
  alias Floor = Roguelike::Floor
  alias Sight = Roguelike::FieldOfView

  # A floor built from *lines*, with no id worth naming.
  def spot(lines : Array(String)) : Floor
    Floor.parse "sight", lines
  end

  # Every square of *floor* that can be seen from *x*, *y*, drawn as a map.
  def seen(floor : Floor, x : Int32, y : Int32) : String
    Sight.from(floor, x, y).to_map(floor).join '\n'
  end

  describe "an open field" do
    it "sees every square" do
      floor = Floor.solid "open", 9, 5, Roguelike::Terrain::StoneFloor

      expect(Sight.from(floor, 4, 2).size).to eq 45
    end

    it "sees nothing off the floor" do
      floor = Floor.solid "open", 9, 5, Roguelike::Terrain::StoneFloor

      Sight.from(floor, 4, 2).each do |square|
        expect(floor.contains? square[0], square[1]).to be_true
      end
    end
  end

  # Standing inside solid rock is not a position the game puts anybody in.
  # The answer is still the one the rule gives: the eight walls touching the
  # square are seen, and nothing behind them is.
  it "always sees the square it stands on" do
    floor = Floor.solid "rock", 5, 5

    sight = Sight.from floor, 2, 2
    expect(sight.includes? 2, 2).to be_true
    expect(sight.size).to eq 9
  end

  # If A can see B then B can see A. Without it a monster could shoot from a
  # square the character cannot shoot back at.
  describe "symmetry" do
    it "holds over every pair of squares on a floor with walls in it" do
      floor = spot [
        "#########",
        "#...#...#",
        "#...#...#",
        "#.......#",
        "#...#...#",
        "#########",
      ]

      floor.each do |column, row, here|
        next unless here.passable?

        looking = Sight.from floor, column, row

        floor.each do |other_column, other_row, there|
          next unless there.passable?

          back = Sight.from(floor, other_column, other_row).includes? column, row
          next if looking.includes?(other_column, other_row) == back

          raise "#{column},#{row} and #{other_column},#{other_row} " \
                "do not see each other alike"
        end
      end
    end
  end

  describe "a wall" do
    it "stops sight at the far face" do
      floor = spot [
        "#####",
        "#...#",
        "#####",
      ]

      sight = Sight.from floor, 2, 1
      expect(sight.includes? 2, 0).to be_true
      expect(sight.includes? 2, 2).to be_true
      expect(sight.size).to eq 15
    end

    it "hides what is directly behind it" do
      floor = spot [
        "#######",
        "#..#..#",
        "#######",
      ]

      sight = Sight.from floor, 1, 1
      expect(sight.includes? 3, 1).to be_true
      expect(sight.includes? 4, 1).to be_false
      expect(sight.includes? 5, 1).to be_false
    end
  end

  describe "a door" do
    it "stops sight while it is shut" do
      floor = spot [
        "#######",
        "#..+..#",
        "#######",
      ]

      sight = Sight.from floor, 1, 1
      expect(sight.includes? 3, 1).to be_true
      expect(sight.includes? 4, 1).to be_false
    end

    it "lets sight through once it is open" do
      floor = spot [
        "#######",
        "#..+..#",
        "#######",
      ]
      floor.set 3, 1, Roguelike::Terrain::OpenDoor

      sight = Sight.from floor, 1, 1
      expect(sight.includes? 5, 1).to be_true
    end

    # Standing beside a shut door, a person sees the room they are in and
    # nothing of the room beyond. Opening it shows the room beyond and not
    # the walls either side of the doorway.
    it "shows only the doorway from across a room" do
      floor = spot [
        "#########",
        "#...+...#",
        "#...#...#",
        "#########",
      ]
      floor.set 4, 1, Roguelike::Terrain::OpenDoor

      sight = Sight.from floor, 1, 1
      expect(sight.includes? 5, 1).to be_true
      expect(sight.includes? 5, 2).to be_false
    end
  end

  describe "a corridor" do
    it "runs its length" do
      floor = spot [
        "##########",
        "#........#",
        "##########",
      ]

      sight = Sight.from floor, 1, 1
      (1..8).each { |column| expect(sight.includes? column, 1).to be_true }
    end

    it "stops at the corner" do
      floor = spot [
        "#########",
        "#.......#",
        "#######.#",
        "      #.#",
        "      #.#",
        "      ###",
      ]

      sight = Sight.from floor, 1, 1
      expect(sight.includes? 7, 1).to be_true
      expect(sight.includes? 7, 3).to be_false
      expect(sight.includes? 7, 4).to be_false
    end
  end

  # Symmetric shadowcasting is strict about this and it is worth knowing
  # rather than rediscovering. A one-wide corridor cuts the view to a narrow
  # wedge, and a floor square needs its centre inside that wedge. An opening
  # in the corridor's side wall a few squares along falls outside it.
  #
  # The rule holds both ways, so somebody standing in that opening cannot
  # see along the corridor either.
  describe "an opening in the side wall of a corridor" do
    it "is out of sight from along the corridor" do
      floor = spot [
        "#############",
        "#...........#",
        "#####.#######",
      ]

      expect(Sight.from(floor, 1, 1).includes?(5, 2)).to be_false
    end

    it "is in sight from beside it" do
      floor = spot [
        "#############",
        "#...........#",
        "#####.#######",
      ]

      expect(Sight.from(floor, 4, 1).includes?(5, 2)).to be_true
    end

    # A shut door is a wall, and a wall is seen whenever the scan reaches it.
    it "is in sight while it is a shut door" do
      floor = spot [
        "#############",
        "#...........#",
        "#####+#######",
      ]

      expect(Sight.from(floor, 1, 1).includes?(5, 2)).to be_true
    end
  end

  describe "#to_map" do
    it "writes the terrain where it is seen and the unseen mark elsewhere" do
      floor = spot [
        "#####",
        "#.#.#",
        "#####",
      ]

      expect(seen(floor, 1, 1)).to eq "###??\n#.#??\n###??"
    end

    it "takes the unseen mark as an argument" do
      floor = spot ["#.#..#"]

      expect(Sight.from(floor, 1, 0).to_map(floor, '~')).to eq ["#.#~~~"]
    end
  end

  describe "the shipped floor" do
    # Standing on the up staircase, the room is visible and the corridor
    # behind each shut door is not.
    it "sees the first room from the up staircase" do
      floor = Roguelike::Floors.proving_ground
      drawn = seen floor, 6, 5

      expect(drawn).to eq Fixture.expected("sight/room.txt", drawn)
    end

    it "sees along the east corridor and stops at the shut door" do
      floor = Roguelike::Floors.proving_ground
      drawn = seen floor, 30, 20

      expect(drawn).to eq Fixture.expected("sight/corridor.txt", drawn)
    end

    # Two shut doors and one open one meet here. Sight goes through the open
    # one and stops at the shut ones.
    it "sees the junction and the closet behind it" do
      floor = Roguelike::Floors.proving_ground
      drawn = seen floor, 10, 12

      expect(drawn).to eq Fixture.expected("sight/junction.txt", drawn)
    end

    it "sees the room around the down staircase" do
      floor = Roguelike::Floors.proving_ground
      drawn = seen floor, 62, 19

      expect(drawn).to eq Fixture.expected("sight/down-stairs.txt", drawn)
    end
  end
end
