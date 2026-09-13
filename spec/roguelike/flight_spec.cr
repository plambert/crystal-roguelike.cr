require "../spec_helper"

Spectator.describe Roguelike::Flight do
  alias Flight = Roguelike::Flight
  alias Floor = Roguelike::Floor
  alias Landing = Roguelike::Landing
  alias Monster = Roguelike::Monster
  alias Species = Roguelike::Species

  # One room with a pillar in the middle of it.
  #
  # A shot from the west wall to the east wall runs along row 3 and meets the
  # pillar at column 5. A shot along row 1 or row 5 passes it.
  ROOM = [
    "###########",
    "#.........#",
    "#.........#",
    "#....#....#",
    "#.........#",
    "#.........#",
    "###########",
  ]

  # How far a shot goes in an example that is not about reach.
  FAR = 40

  def room : Floor
    Floor.parse "room", ROOM
  end

  # A floor with one goblin standing at *at*.
  def guarded(at : {Int32, Int32}) : Floor
    floor = room
    floor.place Monster.new(Species::Goblin, at[0], at[1], "band-one")
    floor
  end

  describe ".toward" do
    it "crosses every square between the two ends" do
      shot = Flight.toward room, {1, 1}, {5, 1}, FAR

      expect(shot.path).to eq [{2, 1}, {3, 1}, {4, 1}, {5, 1}]
    end

    it "leaves the square it was let go from out of the path" do
      shot = Flight.toward room, {1, 1}, {5, 1}, FAR

      expect(shot.path.includes?({1, 1})).to be_false
    end

    it "reaches a square nothing stands between" do
      shot = Flight.toward room, {1, 1}, {9, 1}, FAR

      expect(shot.landing).to eq Landing::Reached
      expect(shot.at).to eq({9, 1})
      expect(shot.clear?).to be_true
    end

    it "stops at the pillar and lands on the square in front of it" do
      shot = Flight.toward room, {1, 3}, {9, 3}, FAR

      expect(shot.landing).to eq Landing::Blocked
      expect(shot.at).to eq({4, 3})
      expect(shot.clear?).to be_false
    end

    it "stops at the wall behind the square it was aimed at" do
      shot = Flight.toward room, {1, 1}, {11, 1}, FAR

      expect(shot.landing).to eq Landing::Blocked
      expect(shot.at).to eq({9, 1})
    end

    it "stops at a creature standing in the line" do
      shot = Flight.toward guarded({5, 1}), {1, 1}, {9, 1}, FAR

      expect(shot.landing).to eq Landing::Struck
      expect(shot.at).to eq({5, 1})
      expect(shot.struck?).to be_true
      expect(shot.clear?).to be_false
    end

    it "stops at a creature standing on the square it was aimed at" do
      shot = Flight.toward guarded({5, 1}), {1, 1}, {5, 1}, FAR

      expect(shot.landing).to eq Landing::Struck
      expect(shot.clear?).to be_true
    end

    # A creature standing where the shot was let go from is the shooter.
    it "ignores whatever stands on the square it was let go from" do
      shot = Flight.toward guarded({1, 1}), {1, 1}, {9, 1}, FAR

      expect(shot.landing).to eq Landing::Reached
      expect(shot.at).to eq({9, 1})
    end

    it "runs out of reach short of the square it was aimed at" do
      shot = Flight.toward room, {1, 1}, {9, 1}, 3

      expect(shot.landing).to eq Landing::Spent
      expect(shot.at).to eq({4, 1})
      expect(shot.distance).to eq 3
    end

    it "crosses no square at all with no reach" do
      shot = Flight.toward room, {1, 1}, {9, 1}, 0

      expect(shot.landing).to eq Landing::Spent
      expect(shot.at).to eq({1, 1})
      expect(shot.path.empty?).to be_true
    end

    it "goes nowhere when it is aimed at the square it was let go from" do
      shot = Flight.toward room, {1, 1}, {1, 1}, FAR

      expect(shot.at).to eq({1, 1})
      expect(shot.clear?).to be_true
    end

    it "runs the same squares the line does" do
      shot = Flight.toward room, {1, 1}, {5, 5}, FAR
      walked = Roguelike::Line.between({1, 1}, {5, 5}).skip 1

      expect(shot.path).to eq walked
    end

    it "stops at a shut door" do
      floor = Floor.parse "hall", ["#####", "#.+.#", "#####"]
      shot = Flight.toward floor, {1, 1}, {3, 1}, FAR

      expect(shot.landing).to eq Landing::Blocked
      expect(shot.at).to eq({1, 1})
    end

    it "passes through an open door" do
      floor = Floor.parse "hall", ["#####", "#.'.#", "#####"]
      shot = Flight.toward floor, {1, 1}, {3, 1}, FAR

      expect(shot.landing).to eq Landing::Reached
      expect(shot.at).to eq({3, 1})
    end

    it "stops at the edge of the floor" do
      shot = Flight.toward room, {1, 1}, {40, 1}, FAR

      expect(shot.landing).to eq Landing::Blocked
      expect(shot.at).to eq({9, 1})
    end
  end
end
