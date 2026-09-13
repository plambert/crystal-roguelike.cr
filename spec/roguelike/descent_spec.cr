require "../spec_helper"

Spectator.describe Roguelike::Descent do
  alias Descent = Roguelike::Descent
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Knowledge = Roguelike::Knowledge

  # A room split by a wall, with the way round it at the bottom.
  #
  # The goal sits in the top left. Everything on the right of the wall is
  # reached by walking down, round the end of it, and back up.
  SPLIT = [
    "#########",
    "#...#...#",
    "#...#...#",
    "#...#...#",
    "#.......#",
    "#########",
  ]

  # A floor, and knowledge of every square of it.
  def known(lines : Array(String) = SPLIT) : {Floor, Knowledge}
    floor = Floor.parse "test", lines
    knowledge = Knowledge.new floor.id
    floor.each { |column, row, _tile| knowledge.see floor, column, row }

    {floor, knowledge}
  end

  # Knowledge of only the squares named.
  def partial(lines : Array(String),
              squares : Array({Int32, Int32})) : {Floor, Knowledge}
    floor = Floor.parse "test", lines
    knowledge = Knowledge.new floor.id
    squares.each { |spot| knowledge.see floor, spot[0], spot[1] }

    {floor, knowledge}
  end

  describe ".toward" do
    it "puts nothing on the goal" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}

      expect(map[1, 1]).to eq 0
      expect(map.goal).to eq({1, 1})
    end

    it "counts one for each square out" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}

      expect(map[2, 1]).to eq 1
      expect(map[3, 1]).to eq 2
      expect(map[2, 2]).to eq 1
    end

    # Eight ways, so a diagonal costs what a straight step costs.
    it "counts a diagonal as one step" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}

      expect(map[2, 2]).to eq 1
      expect(map[3, 3]).to eq 2
    end

    it "goes round a wall rather than through it" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}

      # Straight through the wall is five squares. Round the bottom of it is
      # further, and that is what the map holds.
      round = map[5, 1] || 0

      expect(map[4, 1]).to be_nil
      expect(round).to be > 5
    end

    it "leaves out what nobody has seen" do
      _floor, knowledge = partial SPLIT, [{1, 1}, {2, 1}, {3, 1}]
      map = Descent.toward knowledge, {1, 1}

      expect(map[3, 1]).to eq 2
      expect(map[3, 2]).to be_nil
    end

    it "stops at the limit it was given" do
      _floor, knowledge = known
      near = Descent.toward knowledge, {1, 1}, limit: 2
      whole = Descent.toward knowledge, {1, 1}

      expect(near.size).to be < whole.size
      expect(near.steps.values.max).to eq 2
    end

    # A band chasing something across a floor it knows well would otherwise
    # flood every square it has ever walked on.
    it "never floods further than its own limit" do
      wide = Array.new(30) { |row| row.zero? || row == 29 ? "#" * 60 : "#" + "." * 58 + "#" }
      _floor, knowledge = known wide

      map = Descent.toward knowledge, {1, 1}

      expect(map.steps.values.max).to be <= Descent::LIMIT
    end
  end

  describe "#toward" do
    it "answers the way downhill" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}

      expect(map.toward 3, 3).to eq Direction::NorthWest
      expect(map.toward 3, 1).to eq Direction::West
    end

    it "answers nothing on the goal" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}

      expect(map.toward 1, 1).to be_nil
    end

    it "answers nothing from a square it never reached" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}

      expect(map.toward 4, 1).to be_nil
    end

    it "walks round a square something is standing on" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}
      blocked = Set({Int32, Int32}).new
      blocked << {2, 2}

      expect(map.toward 3, 3).to eq Direction::NorthWest
      expect(map.toward(3, 3, blocked)).not_to eq Direction::NorthWest
    end

    it "waits when every way down is taken" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}
      penned = Set({Int32, Int32}).new
      [{1, 1}, {1, 2}, {2, 1}].each { |spot| penned << spot }

      expect(map.toward(2, 2, penned)).to be_nil
    end

    # Walking downhill from anywhere reaches the goal, and takes the number
    # of steps the map says it will.
    it "leads to the goal from every square it reached" do
      _floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}

      map.steps.each do |spot, away|
        at = spot
        taken = 0

        loop do
          direction = map.toward at[0], at[1]
          break unless direction

          at = direction.from at[0], at[1]
          taken += 1
          break if taken > away
        end

        expect(at).to eq({1, 1})
        expect(taken).to eq away
      end
    end
  end

  # The whole map over one floor, written out.
  #
  # Each square holds how many steps it is from the goal, in base thirty-six
  # so that every square is one character wide. A change to the flood shows
  # as a diff.
  describe "drawn" do
    it "floods what it flooded last time" do
      floor, knowledge = known
      map = Descent.toward knowledge, {1, 1}
      drawn = map.to_map(floor.columns, floor.rows).join "\n"

      expect(drawn).to eq Fixture.expected("descent/split.txt", drawn)
    end

    it "floods the shipped floor the same way" do
      floor = Roguelike::Floors.proving_ground
      knowledge = Knowledge.new floor.id
      floor.each { |column, row, _tile| knowledge.see floor, column, row }

      map = Descent.toward knowledge, {6, 5}
      drawn = map.to_map(floor.columns, floor.rows).join "\n"

      expect(drawn).to eq Fixture.expected("descent/proving-ground.txt", drawn)
    end
  end
end
