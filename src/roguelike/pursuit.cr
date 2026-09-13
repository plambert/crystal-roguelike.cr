require "./descent"
require "./direction"
require "./knowledge"

module Roguelike
  # What a creature has decided to do.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Intent
    # Stay where it is.
    Wait

    # Walk one square.
    Step

    # Swing at whatever is one square away.
    Strike
  end

  # One creature's decision.
  #
  # An `Action` changes nothing. `Pursuit.decide` answers one and `Game`
  # applies it, which is where the decision meets the floor and is checked
  # against it. A creature that decides to walk into a wall walks nowhere.
  record Action, intent : Intent, direction : Direction? = nil do
    # Stay put.
    def self.wait : Action
      new Intent::Wait
    end

    # Walk one square *direction*.
    def self.step(direction : Direction) : Action
      new Intent::Step, direction
    end

    # Swing at the square one step *direction*.
    def self.strike(direction : Direction) : Action
      new Intent::Strike, direction
    end

    # Whether this does nothing at all.
    def nothing? : Bool
      @intent.wait?
    end

    def to_s(io : IO) : Nil
      io << @intent
      @direction.try { |where| io << ' ' << where.label }
    end
  end

  # How a creature decides where to go.
  #
  # Nothing here holds state, opens a floor or writes anything. It reads a
  # `Snapshot` and answers an `Action`. That is the rule the whole model is
  # built to keep: an AI proposes, and the one owner of the game state
  # applies.
  module Pursuit
    # Everything an AI reads to decide one creature's action.
    #
    # There is no `Floor` here and no `Player`. What an AI knows about the
    # shape of the floor is `knowledge`, which is its band's belief, and what
    # it knows about where the character is is `quarry`, which is where the
    # band last saw them. Neither of those is the truth, and a creature acts
    # on the difference.
    #
    # `blocked` is the one thing here that is not belief. A creature knows
    # what it is standing against.
    record Snapshot,
      at : {Int32, Int32},
      knowledge : Knowledge,
      quarry : {Int32, Int32}? = nil,
      hunting : Bool = false,
      descent : Descent? = nil,
      blocked : Set({Int32, Int32}) = Descent::EMPTY

    # What the creature *snapshot* describes does this turn.
    #
    # It swings when the character is one square away and it can see them. It
    # walks toward where it last saw them otherwise. It waits when it has
    # never seen them, when it is standing on the square it last saw them,
    # and when there is nowhere to go.
    def self.decide(snapshot : Snapshot) : Action
      quarry = snapshot.quarry
      return Action.wait unless quarry

      beside = beside snapshot.at, quarry
      return Action.strike(beside) if beside && snapshot.hunting
      return Action.wait if snapshot.at == quarry

      direction = walk snapshot
      direction ? Action.step(direction) : Action.wait
    end

    # Which way *quarry* is, when it is one step from *at*. `nil` otherwise.
    private def self.beside(at : {Int32, Int32},
                            quarry : {Int32, Int32}) : Direction?
      Direction.values.find { |direction| direction.from(at[0], at[1]) == quarry }
    end

    # Which way the creature walks, or `nil` for nowhere to go.
    #
    # A species that paths descends the band's map. One that does not walks
    # straight at the quarry.
    private def self.walk(snapshot : Snapshot) : Direction?
      found = snapshot.descent
      return found.toward(snapshot.at[0], snapshot.at[1], snapshot.blocked) if found

      blunder snapshot
    end

    # The step a creature that does not path takes.
    #
    # Straight at the quarry, and nothing at all when what is that way cannot
    # be walked on. A slime does this. It comes up against a wall and stays
    # against it, because it has no idea the corridor round the corner is
    # there.
    private def self.blunder(snapshot : Snapshot) : Direction?
      quarry = snapshot.quarry
      return unless quarry

      across = (quarry[0] - snapshot.at[0]).sign
      down = (quarry[1] - snapshot.at[1]).sign
      direction = Direction.values.find do |found|
        found.dx == across && found.dy == down
      end
      return unless direction

      wanted = direction.from snapshot.at[0], snapshot.at[1]
      return if snapshot.blocked.includes? wanted
      return unless snapshot.knowledge.walkable? wanted[0], wanted[1]

      direction
    end
  end
end
