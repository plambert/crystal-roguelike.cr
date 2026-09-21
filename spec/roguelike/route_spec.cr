require "../spec_helper"

Spectator.describe Roguelike::Route do
  alias Descent = Roguelike::Descent
  alias Floor = Roguelike::Floor
  alias Knowledge = Roguelike::Knowledge
  alias Route = Roguelike::Route
  alias Vision = Roguelike::Vision

  # A room split by a wall, with the way round it at the bottom.
  SPLIT = [
    "#########",
    "#...#...#",
    "#...#...#",
    "#...#...#",
    "#.......#",
    "#########",
  ]

  # Two rooms, joined by a corridor with a door at each end.
  ROOMS = [
    "###########",
    "#...#+#...#",
    "#...+.+...#",
    "#...#.#...#",
    "###########",
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

  # Everything *floor* holds, seen from *spot* by daylight.
  def looking(floor : Floor, spot : {Int32, Int32}) : Vision
    floor.ambient = 1
    Vision.from floor, spot, [] of Roguelike::LightSource
  end

  # A dark hall with one lamp burning at the east end.
  #
  # The character stands in the west end and sees their own square and the
  # lit end. The squares between are dark and have never been walked.
  def lamplit : {Floor, Knowledge, Vision}
    floor = Floor.parse "hall", ["###########",
                                 "#.........#",
                                 "###########"]
    floor.ambient = 0

    seen = Vision.from floor, {1, 1},
      [Roguelike::LightSource.new(9, 1, 2)]

    knowledge = Knowledge.new floor.id
    knowledge.learn floor, seen

    {floor, knowledge, seen}
  end

  describe ".over" do
    it "starts where the flood started" do
      _floor, knowledge = known
      found = Route.over Descent.toward(knowledge, {1, 1}), {3, 3}

      expect(found.first).to eq({1, 1})
    end

    it "ends on the square it was asked for" do
      _floor, knowledge = known
      found = Route.over Descent.toward(knowledge, {1, 1}), {3, 3}

      expect(found.last).to eq({3, 3})
    end

    # Two diagonals, and the square standing on makes three.
    it "counts a diagonal as one step" do
      _floor, knowledge = known
      found = Route.over Descent.toward(knowledge, {1, 1}), {3, 3}

      expect(found.size).to eq 3
    end

    it "steps one square at a time" do
      _floor, knowledge = known
      found = Route.over Descent.toward(knowledge, {1, 1}), {7, 1}

      found.each_cons_pair do |here, next_one|
        expect(Roguelike::Direction.between here, next_one).not_to be_nil
      end
    end

    it "goes the long way round a wall" do
      _floor, knowledge = known
      found = Route.over Descent.toward(knowledge, {1, 1}), {7, 1}

      expect(found).to contain({4, 4})
    end

    it "answers one square for the square it started on" do
      _floor, knowledge = known
      found = Route.over Descent.toward(knowledge, {1, 1}), {1, 1}

      expect(found).to eq [{1, 1}]
    end

    it "answers nothing for a square the flood never reached" do
      _floor, knowledge = known
      found = Route.over Descent.toward(knowledge, {1, 1}), {0, 0}

      expect(found).to be_empty
    end
  end

  describe ".known" do
    it "answers nothing for a square nobody has seen" do
      floor, knowledge = partial SPLIT, [{1, 1}, {2, 1}]
      found = Route.known knowledge, looking(floor, {1, 1}), {7, 1}

      expect(found).to be_empty
    end

    # The way through is a shut door, and a door remembered as shut is not
    # walked through. The line of sight stops at it as well, so there is
    # nothing to infer either.
    it "does not walk through a door remembered as shut" do
      floor, knowledge = known ROOMS
      found = Route.known knowledge, looking(floor, {2, 2}), {8, 2}

      expect(found).to be_empty
    end

    # The character stands in the dark and can see the lit end of the hall.
    # They have looked at none of the squares between, and the light reaching
    # them says none of those squares is a wall.
    it "walks the squares a line of sight crossed" do
      _floor, knowledge, seen = lamplit
      found = Route.known knowledge, seen, {9, 1}

      expect(knowledge.seen? 5, 1).to be_false
      expect(found.first).to eq({1, 1})
      expect(found.last).to eq({9, 1})
    end

    it "leaves what was inferred out of what is remembered" do
      _floor, knowledge, seen = lamplit

      Route.known knowledge, seen, {9, 1}

      expect(knowledge.seen? 5, 1).to be_false
      expect(knowledge.walkable? 5, 1).to be_false
    end

    # The line to a square says the squares before it are open. It says
    # nothing about the square itself: a field of view holds every wall its
    # scan reached, and a wall is not somewhere to walk.
    it "says nothing about the square at the far end of a line" do
      floor = Floor.parse "hall", ["###########",
                                   "#.........#",
                                   "###########"]
      squares = Set({Int32, Int32}).new
      squares << {1, 1} << {5, 1}
      seen = Vision.new Roguelike::FieldOfView.new({1, 1}, squares)
      guess = Route.guessed Knowledge.new(floor.id), seen

      expect(guess.walkable? 4, 1).to be_true
      expect(guess.walkable? 5, 1).to be_false
    end
  end

  describe ".chosen" do
    it "walks the way when there is one" do
      floor, knowledge = known
      found = Route.chosen knowledge, looking(floor, {1, 1}), {7, 1}

      expect(found.last).to eq({7, 1})
    end

    # A wall stands between the two halves of the room, and the goal is on
    # the far side of it. Nothing is known of the way round the end, so the
    # route stops against the wall.
    it "stops at the nearest square it can reach" do
      floor, knowledge = partial SPLIT,
        [{1, 1}, {2, 1}, {3, 1}, {1, 2}, {2, 2}, {3, 2}]

      found = Route.chosen knowledge, Vision.blind(1, 1), {7, 1}
      _ = floor

      expect(found.first).to eq({1, 1})
      expect(found.last).to eq({3, 1})
    end

    # A character who cannot see infers nothing, so what they remember is all
    # they have. One square is nowhere to walk.
    it "answers nothing when there is nowhere at all to go" do
      floor, knowledge = partial SPLIT, [{1, 1}]
      found = Route.chosen knowledge, Vision.blind(1, 1), {7, 1}
      _ = floor

      expect(found).to be_empty
    end

    # The hall between is unlit and has never been walked. The light from the
    # far end reaches the character across it, which is what says those
    # squares are open.
    it "reaches the far end by the light coming from it" do
      _floor, knowledge, seen = lamplit
      found = Route.chosen knowledge, seen, {9, 1}

      expect(found.last).to eq({9, 1})
    end
  end

  describe ".nearest" do
    it "answers the square of the flood nearest the goal" do
      _floor, knowledge = known
      found = Route.nearest Descent.toward(knowledge, {1, 1}), {7, 1}

      expect(found).to eq({7, 1})
    end

    it "answers the square the flood started on when it reached no other" do
      floor, knowledge = partial SPLIT, [{1, 1}]
      _ = floor
      found = Route.nearest Descent.toward(knowledge, {1, 1}), {7, 1}

      expect(found).to eq({1, 1})
    end
  end

  describe ".apart" do
    it "counts a diagonal as one" do
      expect(Route.apart({0, 0}, {3, 3})).to eq 3
    end

    it "counts the longer axis" do
      expect(Route.apart({0, 0}, {5, 2})).to eq 5
    end
  end
end
