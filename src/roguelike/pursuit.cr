require "../roguelike"

module Roguelike
  # How a creature decides where to go.
  #
  # Nothing here holds state, opens a floor or writes anything. It reads a
  # `Snapshot` and answers an `Action`. An AI proposes, and the one owner of
  # the game state applies.
  module Pursuit
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
    # applies it, checking it against the floor. A creature that decides to
    # walk into a wall walks nowhere.
    #
    # `hemmed` says every square nearer the quarry was taken by another
    # creature. `Game` counts how many turns in a row that has held.
    record Action, intent : Intent, direction : Direction? = nil,
      hemmed : Bool = false do
      # Stay put. *hemmed* says why.
      def self.wait(hemmed : Bool = false) : Action
        new Intent::Wait, hemmed: hemmed
      end

      # Walk one square *direction*.
      def self.step(direction : Direction, hemmed : Bool = false) : Action
        new Intent::Step, direction, hemmed
      end

      # Swing at the square one step *direction*.
      def self.strike(direction : Direction) : Action
        new Intent::Strike, direction
      end

      # Whether every nearer square was taken.
      def hemmed? : Bool
        @hemmed
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

    # Everything an AI reads to decide one creature's action.
    #
    # There is no `Floor` here and no `Player`. What an AI knows about the
    # shape of the floor is `knowledge`, which is its band's belief, and what
    # it is after is `quarry`, which is where the band last saw it. Neither
    # is necessarily what is on the floor now.
    #
    # `blocked` is the only field here that is not belief.
    #
    # `stumble` says this creature is about to put a foot wrong. `Game` rolls
    # it, because nothing here rolls anything.
    #
    # `foes` is where the band saw every other hostile within the last
    # `FRESH` turns, the character first.
    record Snapshot,
      at : {Int32, Int32},
      knowledge : Knowledge,
      quarry : {Int32, Int32}? = nil,
      stale : Int32 = 0,
      descent : Descent? = nil,
      blocked : Set({Int32, Int32}) = Descent::EMPTY,
      stumble : Bool = false,
      foes : Array({Int32, Int32}) = [] of {Int32, Int32}

    # How many turns old a sighting may be and still be worth swinging at.
    #
    # A creature that was looking at the character last turn swings at the
    # square it believes they are on. So does one that was hit by them, which
    # is how a creature fights back in a dark corridor it can see nothing in:
    # being stabbed says which side the blow came from. Older than this and
    # the creature walks to the square instead, and finds nothing there.
    FRESH = 1

    # What the creature *snapshot* describes does this turn.
    #
    # It swings when its quarry is one square away and it knew where the
    # quarry was within the last `FRESH` turns. It swings at another foe one
    # square away when the quarry is not. It walks toward where it last saw
    # the quarry otherwise. It waits when it has never seen one, when it is
    # standing on the square it last saw it, and when there is nowhere to go.
    def self.decide(snapshot : Snapshot) : Action
      quarry = snapshot.quarry
      return Action.wait unless quarry

      beside = beside snapshot.at, quarry
      return Action.strike(beside) if beside && snapshot.stale <= FRESH

      snapshot.foes.each do |foe|
        near = beside snapshot.at, foe
        return Action.strike(near) if near
      end
      return Action.wait if snapshot.at == quarry

      hemmed = hemmed? snapshot
      direction = walk snapshot, hemmed
      direction ? Action.step(direction, hemmed) : Action.wait(hemmed)
    end

    # Whether every square nearer the quarry holds another creature.
    #
    # A creature beside the quarry is not hemmed. The character is what
    # holds that square, and it swings or waits for a fresh sighting.
    private def self.hemmed?(snapshot : Snapshot) : Bool
      descent = snapshot.descent
      return false unless descent

      x, y = snapshot.at
      return false unless descent.downhill(x, y, snapshot.blocked).empty?

      nearer = descent.downhill x, y
      return false if nearer.empty?

      nearer.none? { |direction| direction.from(x, y) == descent.goal }
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
    #
    # A creature whose every nearer square is taken steps to a square as far
    # from the quarry as it is now, which takes it toward another side of
    # what it is chasing. It waits when there is none.
    #
    # A creature that paths but is not on its own map walks straight at the
    # quarry as well. A creature that can see the character is on its map,
    # because seeing them writes down the ground between. One that has not
    # seen them itself and was told where they are may not be, and heading
    # that way beats standing still.
    #
    # A creature that is putting a foot wrong steps sideways rather than
    # nearer, so what it is chasing gains a square. That is what being shaken
    # off looks like from the other side. There is nowhere sideways to go in a
    # corridor, and a creature there walks on properly: nothing is shaken off
    # in a corridor.
    private def self.walk(snapshot : Snapshot, hemmed : Bool) : Direction?
      descent = snapshot.descent
      if descent
        astray = wrong_foot descent, snapshot
        return astray if astray

        downhill = Descent.nearest(
          descent.downhill(snapshot.at[0], snapshot.at[1], snapshot.blocked),
          snapshot.at, descent.goal)
        return downhill if downhill
        return around descent, snapshot if hemmed
      end

      return if snapshot.stumble

      blunder snapshot
    end

    # The step to a square as far from the goal as the creature is, or `nil`
    # when every one is taken.
    private def self.around(descent : Descent, snapshot : Snapshot) : Direction?
      Descent.nearest descent.sideways(
        snapshot.at[0], snapshot.at[1], snapshot.blocked),
        snapshot.at, descent.goal
    end

    # The sideways step a creature that is putting a foot wrong takes, or
    # `nil` when it is not or when there is nowhere sideways to go.
    private def self.wrong_foot(descent : Descent,
                                snapshot : Snapshot) : Direction?
      return unless snapshot.stumble

      around descent, snapshot
    end

    # The step a creature that does not path takes.
    #
    # Along the line to the quarry, and nothing at all when what is that way
    # cannot be walked on. A slime does this. It comes up against a wall and
    # stays against it, because it has no idea the corridor round the corner
    # is there.
    #
    # The line rather than the sign of the difference. A step chosen from the
    # sign goes diagonally until one axis lines up and straight after that,
    # which is the same number of turns and reads as a creature walking at
    # forty-five degrees to wherever it is going.
    private def self.blunder(snapshot : Snapshot) : Direction?
      quarry = snapshot.quarry
      return unless quarry

      direction = straight snapshot.at, quarry
      return unless direction

      wanted = direction.from snapshot.at[0], snapshot.at[1]
      return if snapshot.blocked.includes? wanted
      return unless snapshot.knowledge.walkable? wanted[0], wanted[1]

      direction
    end

    # Which way one step along the line from *at* to *quarry* goes.
    def self.straight(at : {Int32, Int32}, quarry : {Int32, Int32}) : Direction?
      step = Line.step at, quarry
      return unless step

      across = step[0] - at[0]
      down = step[1] - at[1]

      Direction.values.find { |found| found.dx == across && found.dy == down }
    end
  end
end
