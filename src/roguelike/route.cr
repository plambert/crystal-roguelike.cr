require "../roguelike"

module Roguelike
  # A way from where the character stands to a square they picked.
  #
  # A band of monsters walks a `Descent` built toward what it is chasing. The
  # character walks the other way round: they pick a square and want the
  # squares between. So the flood here starts at the character, runs once, and
  # every question is answered off it.
  #
  # Nothing here reads a `Floor`. A route crosses what somebody believes is
  # there. A shortcut nobody has found is not offered.
  #
  # A door is crossed whether it is remembered open or shut. The character
  # opens any door they can reach, and a walk along a route opens a shut one
  # and carries on. A band is the other case, and `Descent.toward` leaves a
  # shut door in its way by default.
  module Route
    # How far a route is searched when nobody names a floor.
    LIMIT = 320

    # How far a route over *floor* is searched.
    #
    # A route never crosses a square twice, so one as long as the floor has
    # squares reaches any square from any other, however the floor winds.
    # The flood runs over what the character remembers, which is what bounds
    # the work.
    def self.limit(floor : Floor) : Int32
      Math.max floor.columns * floor.rows, LIMIT
    end

    # No way at all.
    NOWHERE = [] of {Int32, Int32}

    # The route the character walks when they pick *goal*.
    #
    # Four tries, in this order:
    #
    # * the straight line to it, when they can see it and walk it;
    # * over what they remember;
    # * over what they remember plus the squares a line of sight crossed,
    #   which is how a lit room on the far side of a dark one is reached;
    # * to whichever square of that second try is nearest the goal.
    #
    # Empty when they can reach nothing at all.
    def self.chosen(knowledge : Knowledge, vision : Vision,
                    goal : {Int32, Int32},
                    limit : Int32 = LIMIT) : Array({Int32, Int32})
      found, guess = reaching knowledge, vision, goal, limit
      return found unless found.empty?
      return NOWHERE unless guess

      near = nearest guess, goal
      return NOWHERE if near.nil? || near == vision.origin

      over guess, near
    end

    # The route to *goal*, over what the character remembers and then over
    # what they can infer. Empty when neither reaches it.
    #
    # This is what points at a staircase. A staircase that cannot be walked
    # to is still worth marking where it is, and a route to somewhere else
    # entirely would not be.
    def self.known(knowledge : Knowledge, vision : Vision,
                   goal : {Int32, Int32},
                   limit : Int32 = LIMIT) : Array({Int32, Int32})
      reaching(knowledge, vision, goal, limit)[0]
    end

    # The route to *goal*, and the flood the second try ran over.
    #
    # The second flood is built only when the first try fails, because the
    # first try is what a click on a square already walked takes.
    private def self.reaching(knowledge : Knowledge, vision : Vision,
                              goal : {Int32, Int32},
                              limit : Int32) : {Array({Int32, Int32}), Descent?}
      from = vision.origin

      sighted = sighted knowledge, vision, goal
      return {sighted, nil} if sighted

      found = over Descent.toward(knowledge, from, limit, doors: true), goal
      return {found, nil} unless found.empty?

      guess = Descent.toward guessed(knowledge, vision), from, limit, doors: true
      {over(guess, goal), guess}
    end

    # The squares from *from* to *goal*, *from* first and *goal* last. Empty
    # when no way is known.
    def self.between(knowledge : Knowledge, from : {Int32, Int32},
                     goal : {Int32, Int32},
                     limit : Int32 = LIMIT) : Array({Int32, Int32})
      over Descent.toward(knowledge, from, limit, doors: true), goal
    end

    # The straight line to *goal*, when the character can see it and walk it.
    # `nil` otherwise.
    #
    # A line steps once a square and never moves away from the goal on
    # either axis, so it is as short as any route. Somebody walking at what
    # they can see walks at it.
    #
    # A square along the line that is not remembered was crossed by the line
    # of sight to the goal, so nothing solid stands in it. `.guessed` reads it
    # the same way.
    def self.sighted(knowledge : Knowledge, vision : Vision,
                     goal : {Int32, Int32}) : Array({Int32, Int32})?
      return unless vision.includes? goal
      return unless knowledge.crossable? goal

      line = Line.between vision.origin, goal
      clear = line[1..-2].all? do |spot|
        knowledge.crossable?(spot) || knowledge[spot].nil?
      end

      line if clear
    end

    # The squares from where *descent* was flooded from to *goal*.
    #
    # A diagonal step costs what a straight one does, so many routes are
    # usually the shortest. This one changes direction the fewest times, and
    # a route round a wall bends once at the wall and runs straight after.
    # Among routes that bend as often, it keeps nearest the straight line
    # between the two ends. Any tie left goes to the direction `Direction`
    # names first, so one click picks one route every time.
    #
    # The flood counts steps out from the character. Every square on a
    # shortest route is one step further out than the square before it, so
    # the search runs outward a step at a time over those squares alone.
    def self.over(descent : Descent,
                  goal : {Int32, Int32}) : Array({Int32, Int32})
      return NOWHERE unless descent.includes? goal[0], goal[1]

      start = descent.goal
      return [goal] if goal == start

      layers = funnel descent, goal
      legs = {} of {Int32, Int32} => Hash(Direction, Leg)

      layers.each_with_index do |layer, away|
        next if away.zero?

        layer.each do |spot|
          found = {} of Direction => Leg
          off = drift start, goal, spot

          descent.downhill(spot[0], spot[1]).each do |back|
            before = back.from spot[0], spot[1]
            heading = back.opposite

            if before == start
              keep found, heading, Leg.new(0, off, nil)
              next
            end

            legs[before]?.try &.each do |came, leg|
              turns = leg.turns + (came == heading ? 0 : 1)
              keep found, heading, Leg.new(turns, leg.drift + off, came)
            end
          end

          legs[spot] = found unless found.empty?
        end
      end

      walk_back legs, start, goal
    end

    # How a route arrives on a square: how often it has changed direction,
    # how far it has strayed from the straight line, and which way it was
    # heading on the square before. *came* is `nil` on the first step.
    private record Leg, turns : Int32, drift : Int32, came : Direction?

    # Keeps *leg* as the way to arrive heading *heading*, unless an earlier
    # one bends less or strays less.
    private def self.keep(found : Hash(Direction, Leg), heading : Direction,
                          leg : Leg) : Nil
      held = found[heading]?
      return if held && {held.turns, held.drift} <= {leg.turns, leg.drift}

      found[heading] = leg
    end

    # How far *spot* lies from the line through *start* and *goal*, scaled by
    # the length of that line. Only comparisons read it, so the scale does
    # not matter.
    private def self.drift(start : {Int32, Int32}, goal : {Int32, Int32},
                           spot : {Int32, Int32}) : Int32
      across = goal[0] - start[0]
      down = goal[1] - start[1]
      (across * (spot[1] - start[1]) - down * (spot[0] - start[0])).abs
    end

    # Every square on a shortest route from where *descent* was flooded from
    # to *goal*, grouped by how many steps out each one is.
    #
    # It walks down from the goal along every way the flood goes down, so a
    # square off to the side of every shortest route is left out.
    private def self.funnel(descent : Descent,
                            goal : {Int32, Int32}) : Array(Array({Int32, Int32}))
      far = descent[goal] || 0
      layers = Array.new(far + 1) { [] of {Int32, Int32} }
      layers[far] << goal
      held = Set{goal}

      far.downto(1) do |away|
        layers[away].each do |spot|
          descent.downhill(spot[0], spot[1]).each do |back|
            before = back.from spot[0], spot[1]
            next unless held.add? before

            layers[away - 1] << before
          end
        end
      end

      layers
    end

    # The route that *legs* hold from *start* to *goal*, *start* first.
    private def self.walk_back(legs : Hash({Int32, Int32}, Hash(Direction, Leg)),
                               start : {Int32, Int32},
                               goal : {Int32, Int32}) : Array({Int32, Int32})
      arrivals = legs[goal]?
      return NOWHERE unless arrivals

      heading, leg = arrivals.min_by { |_, found| {found.turns, found.drift} }
      found = [goal]
      at = goal

      loop do
        at = heading.opposite.from at[0], at[1]
        found << at
        break if at == start

        came = leg.came
        return NOWHERE unless came

        leg = legs[at][came]
        heading = came
      end

      found.reverse!
    end

    # The square *descent* reached that is nearest *goal*. `nil` when it
    # reached nothing.
    #
    # Ties go to the square fewest steps out, so a route to somewhere
    # unreachable stops on the near side of whatever is in the way rather
    # than at the far end of a detour that ends the same distance off.
    def self.nearest(descent : Descent,
                     goal : {Int32, Int32}) : {Int32, Int32}?
      found = nil.as({Int32, Int32}?)
      best = {0, 0}

      descent.steps.each do |spot, away|
        gap = {Route.apart(spot, goal), away}
        next if found && gap >= best

        found = spot
        best = gap
      end

      found
    end

    # How many steps apart *from* and *to* are, counting a diagonal as one.
    def self.apart(from : {Int32, Int32}, to : {Int32, Int32}) : Int32
      Math.max (from[0] - to[0]).abs, (from[1] - to[1]).abs
    end

    # *knowledge* with every square a line of sight crossed marked open.
    #
    # Light that reached the eye ran through those squares, so nothing solid
    # stands in them. It says no more than that: an unlit corridor crossed by
    # the line to a lit room is still unlit and still unseen. What it gives is
    # enough to walk it.
    #
    # The square at each end of a line is left out. The far end is what was
    # seen, and a wall is seen as readily as a floor: a field of view holds
    # every wall the scan reached. What the line says is that nothing solid
    # stands between the two, which is the squares in between and no more.
    # The far end needs nothing from this anyway, because looking at a square
    # is what puts it in `Knowledge`.
    #
    # A square remembered as a wall stays a wall. `Knowledge#crossable?` reads
    # a memory before it reads an opening.
    #
    # The field of view is symmetric shadowcasting and the line here is
    # Bresenham's, so the two disagree about a square that clips the corner of
    # a wall. A route through one of those stops against the wall on the step
    # that finds it, the same as a route onto a square something has since
    # walked onto.
    def self.guessed(knowledge : Knowledge, vision : Vision) : Knowledge
      found = knowledge.copy
      origin = vision.origin

      vision.each do |spot|
        crossing = Line.between origin, spot
        next if crossing.size < 3

        crossing[1..-2].each { |crossed| found.opening crossed[0], crossed[1] }
      end

      found
    end
  end
end
