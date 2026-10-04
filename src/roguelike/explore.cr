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
  # Like `Route`, nothing here reads a `Floor`. A route that ends on the
  # character's own square is never answered. The ground under them is known
  # already, and a walk that stood still to look at it would never end.
  module Explore
    # The route to the square explore heads for, the character's own square
    # first. Empty when no square left to see can be reached.
    #
    # *columns* and *rows* are the floor's size. The size of a floor is not a
    # secret, and the edge of it is not a square to go and look at.
    def self.route(knowledge : Knowledge, from : {Int32, Int32},
                   columns : Int32, rows : Int32) : Array({Int32, Int32})
      found = knowledge.chambers columns, rows
      descent = Descent.toward knowledge, from,
        Math.max(columns * rows, Route::LIMIT), doors: true

      goal = nil
      here = Explore.within found, from
      if here
        room = Explore.room found, here
        if room.any? &.frontier?
          edge = room.flat_map &.squares.select { |spot| found.frontier? spot[0], spot[1] }
          goal = nearest descent, edge
        end
      end
      goal ||= nearest descent, found.frontier
      return Route::NOWHERE unless goal

      Route.over descent, goal
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
