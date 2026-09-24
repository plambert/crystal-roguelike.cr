require "../spec_helper"

Spectator.describe Roguelike::Pursuit do
  alias Action = Roguelike::Pursuit::Action
  alias Descent = Roguelike::Descent
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Intent = Roguelike::Pursuit::Intent
  alias Knowledge = Roguelike::Knowledge
  alias Pursuit = Roguelike::Pursuit

  # A room split by a wall, with the way round it at the bottom.
  SPLIT = [
    "#########",
    "#...#...#",
    "#...#...#",
    "#...#...#",
    "#.......#",
    "#########",
  ]

  # Knowledge of every square of *lines*.
  def known(lines : Array(String) = SPLIT) : Knowledge
    floor = Floor.parse "test", lines
    knowledge = Knowledge.new floor.id
    floor.each { |column, row, _tile| knowledge.see floor, column, row }

    knowledge
  end

  # A snapshot of a creature at *at* after a character at *quarry*.
  #
  # *paths* says whether the creature works out a way round, which is the
  # difference between a goblin and a slime.
  def snapshot(at : {Int32, Int32},
               quarry : {Int32, Int32}? = nil,
               stale : Int32 = 0,
               paths : Bool = true,
               knowledge : Knowledge? = nil,
               blocked : Array({Int32, Int32}) = [] of {Int32, Int32},
               stumble : Bool = false) : Pursuit::Snapshot
    held = knowledge || known
    taken = Set({Int32, Int32}).new
    blocked.each { |spot| taken << spot }

    Pursuit::Snapshot.new(
      at: at,
      knowledge: held,
      quarry: quarry,
      stale: stale,
      descent: quarry && paths ? Descent.toward(held, quarry) : nil,
      blocked: taken,
      stumble: stumble)
  end

  # One open room, for a chase with somewhere to go sideways.
  OPEN = [
    "###########",
    "#.........#",
    "#.........#",
    "#.........#",
    "#.........#",
    "###########",
  ]

  # One corridor, where there is nowhere to go but on or back.
  TUNNEL = [
    "#########",
    "#.......#",
    "#########",
  ]

  describe "a creature that has never seen the character" do
    it "waits" do
      expect(Pursuit.decide snapshot({2, 2})).to eq Action.wait
    end
  end

  describe "a creature standing beside the character" do
    it "swings at them" do
      found = Pursuit.decide snapshot({2, 2}, quarry: {3, 2})

      expect(found.intent).to eq Intent::Strike
      expect(found.direction).to eq Direction::East
    end

    it "swings on the diagonal too" do
      found = Pursuit.decide snapshot({2, 2}, quarry: {3, 3})

      expect(found.intent).to eq Intent::Strike
      expect(found.direction).to eq Direction::SouthEast
    end

    # A creature hit in the dark knows which side the blow came from. It
    # swings back without seeing anything.
    it "swings back at a sighting from last turn" do
      found = Pursuit.decide snapshot({2, 2}, quarry: {3, 2}, stale: Pursuit::FRESH)

      expect(found.intent).to eq Intent::Strike
      expect(found.direction).to eq Direction::East
    end

    # An older sighting is where they were rather than where they are. It
    # walks onto the square and finds nothing.
    it "walks onto the square when the sighting has gone cold" do
      found = Pursuit.decide snapshot({2, 2}, quarry: {3, 2}, stale: Pursuit::FRESH + 1)

      expect(found.intent).to eq Intent::Step
      expect(found.direction).to eq Direction::East
    end
  end

  describe "a creature standing where it last saw them" do
    it "waits" do
      found = Pursuit.decide snapshot({2, 2}, quarry: {2, 2}, stale: 5)

      expect(found).to eq Action.wait
    end
  end

  describe "a creature that paths" do
    it "walks downhill toward the character" do
      found = Pursuit.decide snapshot({3, 3}, quarry: {1, 1})

      expect(found.intent).to eq Intent::Step
      expect(found.direction).to eq Direction::NorthWest
    end

    # Straight at the character is a wall, so a creature that paths goes
    # round it.
    it "walks round a wall rather than into it" do
      found = Pursuit.decide snapshot({5, 1}, quarry: {3, 1})

      expect(found.intent).to eq Intent::Step
      expect(found.direction).not_to eq Direction::West
      expect(found.direction.try &.dy).to eq 1
    end

    # A descent steps to a square strictly nearer the goal, never sideways,
    # so a creature whose way down is taken waits for it rather than
    # shuffling round and coming back next turn.
    it "waits rather than pushing past its neighbour" do
      open = Pursuit.decide snapshot({3, 3}, quarry: {1, 1})
      shut = Pursuit.decide snapshot({3, 3}, quarry: {1, 1}, blocked: [{2, 2}])

      expect(open.direction).to eq Direction::NorthWest
      expect(shut).to eq Action.wait
    end

    it "takes whichever way down is left when one of several is taken" do
      found = Pursuit.decide snapshot({3, 4}, quarry: {1, 1}, blocked: [{2, 3}])

      expect(found.intent).to eq Intent::Step
      expect(found.direction).not_to eq Direction::NorthWest
    end

    it "waits when every way down is taken" do
      found = Pursuit.decide snapshot({2, 2}, quarry: {1, 1},
        stale: 5, blocked: [{1, 1}, {1, 2}, {2, 1}])

      expect(found).to eq Action.wait
    end

    # A band that has never looked down a corridor cannot use it.
    it "does not walk a way it has never seen" do
      floor = Floor.parse "test", SPLIT
      partial = Knowledge.new floor.id
      [{1, 1}, {2, 1}, {3, 1}, {3, 2}, {3, 3}].each do |spot|
        partial.see floor, spot[0], spot[1]
      end

      found = Pursuit.decide snapshot({3, 3}, quarry: {1, 1}, knowledge: partial)

      expect(found.intent).to eq Intent::Step
      expect(found.direction).to eq Direction::North
    end
  end

  describe "a creature that does not path" do
    it "walks straight at the character" do
      found = Pursuit.decide snapshot({3, 3}, quarry: {1, 1}, paths: false)

      expect(found.intent).to eq Intent::Step
      expect(found.direction).to eq Direction::NorthWest
    end

    # It has no idea the way round the end of the wall is there.
    it "stops at a wall rather than going round it" do
      found = Pursuit.decide snapshot({5, 1}, quarry: {3, 1}, paths: false)

      expect(found).to eq Action.wait
    end

    it "waits rather than walking into its neighbour" do
      found = Pursuit.decide snapshot({3, 3}, quarry: {1, 1}, paths: false,
        blocked: [{2, 2}])

      expect(found).to eq Action.wait
    end
  end

  describe "a creature that puts a foot wrong" do
    # It has not gone the wrong way. It has gone sideways, and what it is
    # chasing has gained a square.
    it "steps sideways rather than nearer" do
      held = known OPEN
      steady = Pursuit.decide snapshot({8, 2}, quarry: {2, 2}, knowledge: held)
      astray = Pursuit.decide snapshot({8, 2}, quarry: {2, 2}, knowledge: held,
        stumble: true)

      descent = Descent.toward held, {2, 2}
      expect(steady.intent).to eq Intent::Step
      expect(astray.intent).to eq Intent::Step
      expect(astray.direction).not_to eq steady.direction

      where = astray.direction
      raise "it went nowhere" unless where

      expect(descent[where.from 8, 2]).to eq descent[8, 2]
    end

    # Nothing is shaken off in a corridor. Every square beside a creature in
    # one is nearer the quarry or further from it, and there is no third
    # choice.
    it "walks on properly where there is nowhere sideways to go" do
      held = known TUNNEL
      steady = Pursuit.decide snapshot({6, 1}, quarry: {1, 1}, knowledge: held)
      astray = Pursuit.decide snapshot({6, 1}, quarry: {1, 1}, knowledge: held,
        stumble: true)

      expect(astray).to eq steady
      expect(astray.direction).to eq Direction::West
    end

    # A slime has no map to step sideways on. Losing the turn is what a
    # mistake costs it.
    it "stays where it is when it does not path" do
      found = Pursuit.decide snapshot({3, 3}, quarry: {1, 1}, paths: false,
        stumble: true)

      expect(found).to eq Action.wait
    end

    # A creature with its hand already on you does not fumble the swing. What
    # is being modelled is finding the way, not fighting.
    it "still swings at a character beside it" do
      found = Pursuit.decide snapshot({2, 2}, quarry: {3, 3}, stumble: true)

      expect(found.intent).to eq Intent::Strike
    end
  end

  describe Roguelike::Pursuit::Action do
    it "writes itself out" do
      expect(Action.wait.to_s).to eq "Wait"
      expect(Action.step(Direction::North).to_s).to eq "Step north"
      expect(Action.strike(Direction::SouthWest).to_s).to eq "Strike south-west"
    end

    it "knows when it does nothing" do
      expect(Action.wait.nothing?).to be_true
      expect(Action.step(Direction::North).nothing?).to be_false
    end
  end
end
