require "./descent"
require "./knowledge"
require "./line"
require "./vision"

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
    # How far a route is searched.
    #
    # The dug floor is 216 by 84, so this reaches any square of it from any
    # other.
    LIMIT = 320

    # No way at all.
    NOWHERE = [] of {Int32, Int32}

    # The route the character walks when they pick *goal*.
    #
    # Three tries, in this order:
    #
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

    # The squares from where *descent* was flooded from to *goal*.
    #
    # The flood counts steps out from the character, so walking downhill from
    # the goal arrives at the character. The list is turned round before it is
    # answered, because a route is walked from this end.
    def self.over(descent : Descent,
                  goal : {Int32, Int32}) : Array({Int32, Int32})
      return NOWHERE unless descent.includes? goal[0], goal[1]

      found = [goal]
      at = goal

      until at == descent.goal
        direction = descent.toward at[0], at[1]
        return NOWHERE unless direction

        at = direction.from at[0], at[1]
        found << at
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
