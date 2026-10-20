require "../roguelike"

module Roguelike
  # Where the character walks to see what they have not seen.
  #
  # The goal is a square of `Chambers#frontier`, which is walkable ground
  # beside a square not yet seen. Standing on one shows what is beside it.
  #
  # The small side comes first. The goal is the frontier square with the
  # least unseen space behind it, by `Chambers#behind`. Only a square within
  # `REACH` steps is ranked that way, and every other square counts as
  # large. A pocket beside the character is seen while they stand by it, and
  # is not left to walk back to at the end. Between equal estimates the goal
  # is the nearest. Nearest means fewest steps over what the character knows, shut
  # doors counted as crossable because a walk opens them.
  #
  # A room that is only partly seen keeps the character in it. While the
  # room they stand in has a frontier they can reach, the goal is chosen from
  # that frontier alone, so a room is swept before it is left. `.within`
  # says which chamber they stand in, and `.room` takes in the chambers the
  # grid cut the same room into.
  #
  # A passage holds the character once they are in it. While they stand on
  # a square no chamber holds, such as a door or a corridor, and that
  # passage has a square left to see, the goal is chosen from those squares.
  # The way there keeps to the passage. A passage with nothing left to see
  # lets them go, and so does reaching a room.
  #
  # Gold comes first, and so does whatever automatic pickup takes. While
  # the character remembers either lying somewhere they can reach, the goal
  # is the nearest pile of the two, and the step onto it picks it up. A pile
  # remembered where it no longer lies is forgotten when the square is seen
  # again, and the walk goes on to the next goal.
  #
  # An item seen from too far off to read comes last. Once nothing is left
  # to see, the goal is the nearest of those, and the walk stops when the
  # character comes near enough to read it.
  #
  # Like `Route`, nothing here reads a `Floor`. A route that ends on the
  # character's own square is never answered. The ground under them is known
  # already, and a walk that stood still to look at it would never end.
  module Explore
    # The route to the square explore heads for, the character's own square
    # first. Empty when no pile worth taking, no square left to see and no
    # item left to read can be reached.
    #
    # *columns* and *rows* are the floor's size. The size of a floor is not a
    # secret, and the edge of it is not a square to go and look at. *takes*
    # says which items automatic pickup takes, and is `nil` when it takes
    # none.
    def self.route(knowledge : Knowledge, from : {Int32, Int32},
                   columns : Int32, rows : Int32,
                   takes : Proc(Item, Bool)? = nil) : Array({Int32, Int32})
      found = knowledge.chambers columns, rows
      descent = flood knowledge, from, columns, rows

      goal = nearest descent, Explore.wanted(knowledge, takes)
      unless goal
        room = sweeping knowledge, found, from, columns, rows
        return room if room
        along = passage knowledge, found, from, columns, rows
        ahead = along.try { |inside| smallest found, inside, found.frontier }
        return Route.over(along, ahead) if along && ahead
      end
      goal ||= smallest found, descent, found.frontier
      goal ||= nearest descent, Explore.unread(knowledge)
      return Route::NOWHERE unless goal

      Route.over descent, goal
    end

    # How many steps every square of the passage the character at *from*
    # stands in is from *from*, counted without entering a chamber. `nil`
    # when a chamber holds *from*.
    private def self.passage(knowledge : Knowledge, chambers : Chambers,
                             from : {Int32, Int32}, columns : Int32,
                             rows : Int32) : Descent?
      return if chambers.at from

      rooms = Set({Int32, Int32}).new
      chambers.chambers.each { |chamber| rooms.concat chamber.squares }
      Descent.toward knowledge, from, Math.max(columns * rows, Route::LIMIT),
        doors: true, avoid: rooms
    end

    # The route to the square left to see that explore picks in the room the
    # character at *from* is sweeping. `nil` when that room has none they can reach.
    #
    # The route keeps to the room. A route that left it through a doorway
    # would put the character in a passage, where the passage rule could
    # turn them back toward the room, and the walk would go round.
    private def self.sweeping(knowledge : Knowledge, chambers : Chambers,
                              from : {Int32, Int32}, columns : Int32,
                              rows : Int32) : Array({Int32, Int32})?
      here = Explore.within chambers, from
      return unless here

      room = Explore.room chambers, here
      return unless room.any? &.frontier?

      squares = Set({Int32, Int32}).new
      room.each { |chamber| squares.concat chamber.squares }
      inside = Descent.toward knowledge, from, Math.max(columns * rows, Route::LIMIT),
        doors: true, keep: squares
      edge = room.flat_map &.squares.select { |spot| chambers.frontier? spot[0], spot[1] }
      goal = smallest chambers, inside, edge
      Route.over inside, goal if goal
    end

    # Whether a pile worth taking or an item left to read that *knowledge*
    # remembers lies anywhere the character at *from* can reach, other than
    # under them.
    def self.wanted?(knowledge : Knowledge, from : {Int32, Int32},
                     columns : Int32, rows : Int32,
                     takes : Proc(Item, Bool)? = nil) : Bool
      piles = Explore.wanted(knowledge, takes) + Explore.unread(knowledge)
      return false if piles.empty?

      !nearest(flood(knowledge, from, columns, rows), piles).nil?
    end

    # How many steps every square the character knows is from *from*.
    private def self.flood(knowledge : Knowledge, from : {Int32, Int32},
                           columns : Int32, rows : Int32) : Descent
      Descent.toward knowledge, from, Math.max(columns * rows, Route::LIMIT), doors: true
    end

    # Every square *knowledge* remembers gold or an item *takes* accepts
    # lying on, in reading order. The whole remembered pile counts, so
    # arrows under a dagger are found. Gold the character put down does not
    # count.
    def self.wanted(knowledge : Knowledge,
                    takes : Proc(Item, Bool)? = nil) : Array({Int32, Int32})
      found = [] of {Int32, Int32}
      knowledge.each do |column, row, memory|
        next unless memory.item

        wanted = memory.holds? do |item|
          (item.kind.gold? && !item.dropped?) || takes.try(&.call(item)) || false
        end
        found << {column, row} if wanted
      end

      found.sort_by! { |spot| {spot[1], spot[0]} }
    end

    # Every square *knowledge* remembers an item on that was seen from too
    # far off to read, in reading order. Gold and torches are left out,
    # because neither stops a walk.
    def self.unread(knowledge : Knowledge) : Array({Int32, Int32})
      found = [] of {Int32, Int32}
      knowledge.each do |column, row, memory|
        item = memory.item
        next unless item && memory.regard < Regard::Everything
        next if item.kind.gold? || item.kind.torch?

        found << {column, row}
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

    # How many steps off a pocket can be and still come before a nearer
    # square. A pocket farther off counts as large, so explore does not
    # walk across a room for one square while open ground lies beside it.
    REACH = 4

    # Which of *spots* has the least unseen space behind it, by
    # `Chambers#behind`. Only a square within `REACH` steps on *descent* is
    # told apart this way, and every other square counts as large. The
    # fewest steps breaks a tie, and reading order breaks a tie of both.
    # `nil` when *descent* reaches none of them past its own goal.
    def self.smallest(chambers : Chambers, descent : Descent,
                      spots : Array({Int32, Int32})) : {Int32, Int32}?
      best = nil.as({Int32, Int32}?)
      least = {0, 0}

      spots.each do |spot|
        away = descent[spot]
        next if away.nil? || away.zero?

        behind = away <= REACH ? chambers.behind(spot) : Chambers::BEHIND
        score = {behind, away}
        next if best && (score <=> least) >= 0

        best = spot
        least = score
      end

      best
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
