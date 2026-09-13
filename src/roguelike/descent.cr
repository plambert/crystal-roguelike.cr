require "./direction"
require "./knowledge"

module Roguelike
  # A number on every square saying how many steps it is from a goal.
  #
  # The goal holds zero, every square beside it holds one, and so on outward.
  # A creature walks a shortest path by stepping to whichever neighbour holds
  # a smaller number than the square it is standing on. The search runs once
  # for a whole band rather than once for each of its members, and the
  # creatures themselves search for nothing.
  #
  # It is built over what somebody believes rather than over the floor. A
  # square nobody has looked at is not in it, so a band does not walk a
  # shortcut it has never found, and one that remembers a door as shut does
  # not path through it.
  #
  # This is derived rather than stored. It is built again whenever the goal
  # moves or the band learns something, and it is not in a save file.
  class Descent
    # Where the goal is.
    getter goal : {Int32, Int32}

    # How many steps each square is from the goal.
    getter steps : Hash({Int32, Int32}, Int32)

    # How far a descent is built before it stops.
    #
    # A band chasing something across a floor it knows well would otherwise
    # flood every square it has ever seen. Nothing pursues from further off
    # than this, so nothing past it is worth the work.
    LIMIT = 40

    def initialize(@goal : {Int32, Int32},
                   @steps : Hash({Int32, Int32}, Int32) = {} of {Int32, Int32} => Int32)
    end

    # The descent over *knowledge* toward *goal*, no further than *limit*.
    #
    # The goal square goes in whatever is remembered of it, so a creature
    # walks to where it believes the character is standing.
    def self.toward(knowledge : Knowledge, goal : {Int32, Int32},
                    limit : Int32 = LIMIT) : Descent
      steps = {goal => 0}
      edge = [goal]
      away = 0

      while !edge.empty? && away < limit
        away += 1
        wave = [] of {Int32, Int32}

        edge.each do |spot|
          Direction.values.each do |direction|
            wanted = direction.from spot[0], spot[1]
            next if steps.has_key? wanted
            next unless knowledge.walkable? wanted[0], wanted[1]

            steps[wanted] = away
            wave << wanted
          end
        end

        edge = wave
      end

      new goal, steps
    end

    # How many steps *x*, *y* is from the goal. `nil` for a square the
    # descent never reached.
    def [](x : Int32, y : Int32) : Int32?
      @steps[{x, y}]?
    end

    # :ditto:
    def [](spot : {Int32, Int32}) : Int32?
      @steps[spot]?
    end

    # How many squares the descent reached.
    def size : Int32
      @steps.size
    end

    # Whether the descent reached *x*, *y*.
    def includes?(x : Int32, y : Int32) : Bool
      @steps.has_key?({x, y})
    end

    # Which way to step from *x*, *y* to get one square nearer the goal.
    #
    # `nil` when nothing beside it is nearer: the goal itself, a square the
    # descent never reached, and a dead end all answer that. A creature that
    # is given `nil` stays where it is.
    #
    # *blocked* names the squares something else is standing on. A creature
    # waits rather than walking into its neighbour.
    #
    # Only a square strictly nearer the goal counts, never one the same
    # distance off. A creature whose way down is taken waits for it to clear
    # rather than stepping sideways and coming back the turn after.
    #
    # Ties go to whichever direction `Direction` names first, so a band walks
    # the same way twice from the same seed.
    def toward(x : Int32, y : Int32,
               blocked : Set({Int32, Int32}) = EMPTY) : Direction?
      here = @steps[{x, y}]?
      return unless here
      return if here.zero?

      best = here
      found = nil.as(Direction?)

      Direction.values.each do |direction|
        wanted = direction.from x, y
        next if blocked.includes? wanted

        away = @steps[wanted]?
        next unless away && away < best

        best = away
        found = direction
      end

      found
    end

    # Nothing standing anywhere. What `#toward` reads when a caller names no
    # squares.
    EMPTY = Set({Int32, Int32}).new

    # The descent drawn over *knowledge*, one character a square.
    #
    # A square the descent reached holds its own distance in base
    # thirty-six, so every square is one character wide however far off it
    # is. A square it did not reach holds *unreached*.
    #
    # For a spec and for reading a failure, the same way `Knowledge#to_map`
    # is.
    def to_map(columns : Int32, rows : Int32, unreached : Char = '.') : Array(String)
      Array.new(rows) do |row|
        String.build(columns) do |line|
          columns.times do |column|
            away = self[column, row]
            line << (away ? Descent.mark(away) : unreached)
          end
        end
      end
    end

    # One character for a distance of *away*.
    def self.mark(away : Int32) : Char
      return '#' if away < 0 || away > 35

      "0123456789abcdefghijklmnopqrstuvwxyz"[away]
    end

    def to_s(io : IO) : Nil
      io << "Descent(" << @goal[0] << ',' << @goal[1]
      io << ' ' << @steps.size << " squares)"
    end
  end
end
