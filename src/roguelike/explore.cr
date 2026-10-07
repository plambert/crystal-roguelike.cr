require "../roguelike"

module Roguelike
  # Where the character walks to see what they have not seen.
  #
  # The goal is the nearest square of `Chambers#frontier`, which is walkable
  # ground beside a square not yet seen. Standing on one shows what is
  # beside it. Nearest means fewest steps over what the character knows, shut
  # doors counted as crossable because a walk opens them.
  #
  # A room that is only partly seen keeps the character in it. While the
  # room they stand in has a frontier they can reach, the goal is the nearest
  # square of that frontier, so a room is swept before it is left. `.within`
  # says which chamber they stand in, and `.room` takes in the chambers the
  # grid cut the same room into.
  #
  # Gold comes first, and so does ammunition the quiver takes. While the
  # character remembers either lying somewhere they can reach, the goal is
  # the nearest pile of the two, and the step onto it picks it up. A pile
  # remembered where it no longer lies is forgotten when the square is seen
  # again, and the walk goes on to the next goal.
  #
  # Like `Route`, nothing here reads a `Floor`. A route that ends on the
  # character's own square is never answered. The ground under them is known
  # already, and a walk that stood still to look at it would never end.
  module Explore
    # The route to the square explore heads for, the character's own square
    # first. Empty when no pile worth taking and no square left to see can be
    # reached.
    #
    # *columns* and *rows* are the floor's size. The size of a floor is not a
    # secret, and the edge of it is not a square to go and look at. *takes*
    # says which items the quiver picks up, and is `nil` when it picks up
    # none.
    def self.route(knowledge : Knowledge, from : {Int32, Int32},
                   columns : Int32, rows : Int32,
                   takes : Proc(Item, Bool)? = nil) : Array({Int32, Int32})
      found = knowledge.chambers columns, rows
      descent = flood knowledge, from, columns, rows

      goal = nearest descent, Explore.wanted(knowledge, takes)
      goal ||= sweeping found, descent, from
      goal ||= nearest descent, found.frontier
      return Route::NOWHERE unless goal

      Route.over descent, goal
    end

    # The nearest square left to see in the room the character at *from*
    # stands in. `nil` when that room has none they can reach.
    private def self.sweeping(chambers : Chambers, descent : Descent,
                              from : {Int32, Int32}) : {Int32, Int32}?
      here = Explore.within chambers, from
      return unless here

      room = Explore.room chambers, here
      return unless room.any? &.frontier?

      edge = room.flat_map &.squares.select { |spot| chambers.frontier? spot[0], spot[1] }
      nearest descent, edge
    end

    # Whether a pile worth taking that *knowledge* remembers lies anywhere
    # the character at *from* can reach, other than under them.
    def self.wanted?(knowledge : Knowledge, from : {Int32, Int32},
                     columns : Int32, rows : Int32,
                     takes : Proc(Item, Bool)? = nil) : Bool
      piles = Explore.wanted knowledge, takes
      return false if piles.empty?

      !nearest(flood(knowledge, from, columns, rows), piles).nil?
    end

    # How many steps every square the character knows is from *from*.
    private def self.flood(knowledge : Knowledge, from : {Int32, Int32},
                           columns : Int32, rows : Int32) : Descent
      Descent.toward knowledge, from, Math.max(columns * rows, Route::LIMIT), doors: true
    end

    # Every square *knowledge* remembers gold or an item *takes* accepts
    # lying on, in reading order.
    def self.wanted(knowledge : Knowledge,
                    takes : Proc(Item, Bool)? = nil) : Array({Int32, Int32})
      found = [] of {Int32, Int32}
      knowledge.each do |column, row, memory|
        item = memory.item
        next unless item

        found << {column, row} if item.kind.gold? || takes.try &.call(item)
      end

      found.sort_by! { |spot| {spot[1], spot[0]} }
    end

    # The chamber the character at *at* is sweeping.
    #
    # The one they stand in, or else the first one beside them. A doorway
    # and the neck of a cave hold no chamber. Taking the chamber beside one
    # keeps a sweep going through it. Without that, a step into the neck
    # would pick the nearest square left to see anywhere, and the next step
    # back into the chamber would pick the chamber's own again.
    def self.within(chambers : Chambers, at : {Int32, Int32}) : Chamber?
      found = chambers.at at
      return found if found

      Chambers::AROUND.each do |offset|
        found = chambers.at at[0] + offset[0], at[1] + offset[1]
        return found if found
      end

      nil
    end

    # *chamber* and every chamber joined to it with no passage between.
    #
    # The grid cuts a large room into several chambers. They are still one
    # room to sweep, or the character would turn back each time they crossed
    # a line of the grid.
    def self.room(chambers : Chambers, chamber : Chamber) : Array(Chamber)
      found = [chamber]
      seen = Set{chamber.anchor}
      index = 0

      while index < found.size
        found[index].neighbors.each do |anchor|
          next unless seen.add? anchor

          joined = chambers[anchor]
          found << joined if joined
        end
        index += 1
      end

      found
    end

    # Which of *spots* is fewest steps away on *descent*. Ties go to the
    # first in reading order. `nil` when *descent* reaches none of them past
    # its own goal.
    def self.nearest(descent : Descent,
                     spots : Array({Int32, Int32})) : {Int32, Int32}?
      best = nil.as({Int32, Int32}?)
      least = 0

      spots.each do |spot|
        away = descent[spot]
        next if away.nil? || away.zero?
        next if best && away >= least

        best = spot
        least = away
      end

      best
    end
  end
end
