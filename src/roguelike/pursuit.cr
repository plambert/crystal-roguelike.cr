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

      # Shut the open door one square away.
      Shut

      # Shoot at a square along a clear line.
      Shoot
    end

    # One creature's decision.
    #
    # An `Action` changes nothing. `Pursuit.decide` answers one and `Game`
    # applies it, checking it against the floor. A creature that decides to
    # walk into a wall walks nowhere.
    #
    # `hemmed` says every square nearer the quarry was taken by another
    # creature. `Game` counts how many turns in a row that has held.
    #
    # `target` is the square a shot is aimed at. Nothing else has one.
    record Action, intent : Intent, direction : Direction? = nil,
      hemmed : Bool = false, target : {Int32, Int32}? = nil do
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

      # Shut the open door one step *direction*.
      def self.shut(direction : Direction) : Action
        new Intent::Shut, direction
      end

      # Shoot at *target*.
      def self.shoot(target : {Int32, Int32}) : Action
        new Intent::Shoot, target: target
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
        @target.try { |spot| io << ' ' << spot[0] << ',' << spot[1] }
      end
    end

    # Everything an AI reads to decide one creature's action.
    #
    # There is no `Floor` here and no `Player`. What an AI knows about the
    # shape of the floor is `knowledge`, which is its band's belief, and what
    # it is after is `quarry`, which is where the band last saw it. Neither
    # is necessarily what is on the floor now.
    #
    # `blocked` and `closable` are the only fields here that are not belief.
    # `closable` names the squares beside the creature holding an open door
    # that nothing stands in, and is empty for a creature that cannot shut one.
    #
    # `fleeing` says the creature is running. `shade` is the light on the
    # floor, and `company` is where the rest of its band stands. A running
    # creature reads both.
    #
    # `stumble` says this creature is about to put a foot wrong. `Game` rolls
    # it, because nothing here rolls anything.
    #
    # `reach` is how far the creature can shoot, and zero when it has nothing
    # to shoot or nothing to shoot with. `clear` says a shot at the quarry
    # would get there. `Game` works it out on the floor, as it does
    # `blocked`, because a creature sees who is standing in the way.
    #
    # `surrounds` says this creature moves round its quarry to face a
    # bandmate across it. `bandmates` is where the other members of its band
    # stand beside the quarry.
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
      fleeing : Bool = false,
      shade : Lighting? = nil,
      company : Array({Int32, Int32}) = [] of {Int32, Int32},
      closable : Set({Int32, Int32}) = Descent::EMPTY,
      reach : Int32 = 0,
      clear : Bool = false,
      surrounds : Bool = false,
      bandmates : Array({Int32, Int32}) = [] of {Int32, Int32},
      foes : Array({Int32, Int32}) = [] of {Int32, Int32}

    # How many turns old a sighting may be and still be worth swinging at.
    #
    # A creature that was looking at the character last turn swings at the
    # square it believes they are on. So does one that was hit by them, which
    # is how a creature fights back in a dark corridor it can see nothing in:
    # being stabbed says which side the blow came from. Older than this and
    # the creature walks to the square instead, and finds nothing there.
    FRESH = 1

    # The nearest a creature that shoots lets the character come before it
    # backs away.
    NEAREST = 3

    # The farthest a creature that shoots lets fly from. Farther than this it
    # walks nearer first.
    FARTHEST = 6

    # What the creature *snapshot* describes does this turn.
    #
    # It swings when its quarry is one square away and it knew where the
    # quarry was within the last `FRESH` turns. It swings at another foe one
    # square away when the quarry is not. It walks toward where it last saw
    # the quarry otherwise. It waits when it has never seen one, when it is
    # standing on the square it last saw it, and when there is nowhere to go.
    #
    # A creature that is running runs first. See `#flee`. A creature that can
    # shoot and saw its quarry within `FRESH` turns keeps its distance next.
    # See `#stand_off`.
    def self.decide(snapshot : Snapshot) : Action
      quarry = snapshot.quarry
      return Action.wait unless quarry
      return flee snapshot, quarry if snapshot.fleeing

      if snapshot.stale <= FRESH
        engaged = engage snapshot, quarry
        return engaged if engaged
      end

      snapshot.foes.each do |foe|
        near = beside snapshot.at, foe
        return Action.strike(near) if near
      end
      return Action.wait if snapshot.at == quarry

      hemmed = hemmed? snapshot
      direction = walk snapshot, hemmed
      direction ? Action.step(direction, hemmed) : Action.wait(hemmed)
    end

    # What a creature that saw its quarry within `FRESH` turns does about
    # it, or `nil` to go on as any other.
    #
    # One that can shoot keeps its distance or shoots. One that surrounds
    # moves round to face a bandmate across the quarry. Any other swings
    # when the quarry is beside it.
    private def self.engage(snapshot : Snapshot, quarry : {Int32, Int32}) : Action?
      beside = beside snapshot.at, quarry
      if snapshot.reach > 0
        ranged = stand_off snapshot, quarry, beside
        return ranged if ranged
      end

      round = encircle snapshot, quarry
      return Action.step(round) if round

      Action.strike(beside) if beside
    end

    # What a running creature does.
    #
    # It shuts an open door it has just come through, unless the character is
    # beside it. Otherwise it steps to a square further from the quarry, one
    # step further than its own on the band's map. Of those it takes the one
    # with the least light on it, then the one nearest the rest of its band,
    # then the first in `Direction` order.
    #
    # A creature with no square further off swings when the character is
    # beside it, because it is cornered. It waits otherwise, which is what a
    # creature at the edge of its map has done when it has got away.
    private def self.flee(snapshot : Snapshot, quarry : {Int32, Int32}) : Action
      at = snapshot.at
      near = beside at, quarry
      descent = snapshot.descent
      here = descent.try &.[at]
      away = descent && here ? descent.uphill(at[0], at[1], snapshot.blocked) : Descent::NOWHERE

      if away.empty?
        return Action.strike(near) if near && snapshot.stale <= FRESH
        return Action.wait
      end

      if descent && here && !near
        door = Direction.values.find do |direction|
          spot = direction.from at[0], at[1]
          next false unless snapshot.closable.includes? spot

          stepped = descent[spot]
          !stepped.nil? && stepped < here
        end
        return Action.shut(door) if door
      end

      Action.step away.min_by { |direction| shelter snapshot, direction.from(at[0], at[1]) }
    end

    # How good a square to run to *spot* is. Lower is better.
    #
    # The light on it, then the squared distance to the nearest other member
    # of the band.
    private def self.shelter(snapshot : Snapshot,
                             spot : {Int32, Int32}) : {Int32, Int32}
      light = snapshot.shade.try(&.level(spot[0], spot[1])) || 0
      gap = snapshot.company.min_of? do |other|
        (other[0] - spot[0]) ** 2 + (other[1] - spot[1]) ** 2
      end

      {light, gap || 0}
    end

    # What a creature that can shoot does, or `nil` to fight as any other.
    #
    # Closer than `NEAREST` it steps back when there is a square farther from
    # the quarry to step to. It shoots along a clear line from `FARTHEST` or
    # nearer. It shoots from two squares when it cannot back away, and swings
    # when the quarry is beside it and it cannot back away. Otherwise it walks
    # as any other creature does, which brings it into range or round to a
    # clear line.
    private def self.stand_off(snapshot : Snapshot, quarry : {Int32, Int32},
                               beside : Direction?) : Action?
      distance = gap snapshot.at, quarry
      if distance < NEAREST
        away = retreat snapshot, quarry
        return Action.step(away) if away
      end
      return if beside
      return unless snapshot.clear
      return unless distance <= Math.min(FARTHEST, snapshot.reach)

      Action.shoot quarry
    end

    # The step that takes the creature farthest from *quarry*, or `nil` when
    # every step brings it no farther.
    #
    # Farther by the count of steps between first, then by the straight line,
    # so a creature backs straight away rather than along a wall. The first in
    # `Direction` order wins a tie.
    private def self.retreat(snapshot : Snapshot, quarry : {Int32, Int32}) : Direction?
      here = gap snapshot.at, quarry
      best = nil.as(Direction?)
      best_key = {here, 0}

      Direction.values.each do |direction|
        spot = direction.from snapshot.at[0], snapshot.at[1]
        next if snapshot.blocked.includes? spot
        next unless snapshot.knowledge.walkable? spot[0], spot[1]

        across = spot[0] - quarry[0]
        down = spot[1] - quarry[1]
        key = {gap(spot, quarry), across * across + down * down}
        next unless key[0] > here && (best.nil? || key > best_key)

        best = direction
        best_key = key
      end

      best
    end

    # How many steps apart *one* and *other* are. A diagonal step is one step.
    def self.gap(one : {Int32, Int32}, other : {Int32, Int32}) : Int32
      Math.max (one[0] - other[0]).abs, (one[1] - other[1]).abs
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

    # How far from its quarry a creature that surrounds looks for a square
    # to flank from, and walks round to reach one.
    REACH = 2

    # The step a creature near its quarry takes to flank it, or `nil` to go
    # on as it would.
    #
    # Only one that `surrounds` does this. It looks for a free square beside
    # the quarry across from a bandmate that is beside the quarry too. It
    # pairs only with a bandmate whose square sorts before its own, north
    # to south and west to east, so of two unpaired members one stays and
    # swings while the other walks round. One already across from a bandmate
    # stays.
    #
    # The walk keeps within `REACH` squares of the quarry and goes round
    # the quarry and the bandmates beside it. It steps only when the step
    # brings it nearer, so it never circles for nothing.
    private def self.encircle(snapshot : Snapshot, quarry : {Int32, Int32}) : Direction?
      return unless snapshot.surrounds

      at = snapshot.at
      mates = snapshot.bandmates
      return if mates.empty?
      return if apart(at, quarry) > REACH
      return if touches?(at, quarry) && mates.includes?(Combat.opposite(at, quarry))

      targets = mates.select { |mate| {mate[1], mate[0]} < {at[1], at[0]} }
        .map { |mate| Combat.opposite mate, quarry }
        .select { |spot| free? snapshot, quarry, spot }
      return if targets.empty?

      away = distances snapshot, quarry, targets
      here = away[at]?
      return unless here

      best = Direction.values.select { |direction| away.has_key? direction.from(*at) }
        .min_by? { |direction| away[direction.from(*at)] }
      return unless best

      best if away[best.from(*at)] < here
    end

    # How many steps each square within `REACH` of *quarry* is from the
    # nearest of *targets*, walking only on free squares. The creature's own
    # square counts as free.
    private def self.distances(snapshot : Snapshot, quarry : {Int32, Int32},
                               targets : Array({Int32, Int32})) : Hash({Int32, Int32}, Int32)
      away = {} of {Int32, Int32} => Int32
      queue = Deque({Int32, Int32}).new
      targets.each do |spot|
        away[spot] = 0
        queue << spot
      end

      while spot = queue.shift?
        Direction.values.each do |direction|
          next_spot = direction.from(*spot)
          next if away.has_key? next_spot
          next if apart(next_spot, quarry) > REACH
          next unless next_spot == snapshot.at || free?(snapshot, quarry, next_spot)

          away[next_spot] = away[spot] + 1
          queue << next_spot
        end
      end

      away
    end

    # Whether *spot* is free to walk on, as far as the creature knows.
    private def self.free?(snapshot : Snapshot, quarry : {Int32, Int32},
                           spot : {Int32, Int32}) : Bool
      return false if spot == quarry
      return false if snapshot.bandmates.includes? spot
      return false if snapshot.blocked.includes? spot

      snapshot.knowledge.walkable? spot[0], spot[1]
    end

    # Whether *spot* is one of the eight squares around *quarry*.
    private def self.touches?(spot : {Int32, Int32}, quarry : {Int32, Int32}) : Bool
      apart(spot, quarry) == 1
    end

    # How many steps apart two squares are.
    private def self.apart(one : {Int32, Int32}, other : {Int32, Int32}) : Int32
      Math.max (one[0] - other[0]).abs, (one[1] - other[1]).abs
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
