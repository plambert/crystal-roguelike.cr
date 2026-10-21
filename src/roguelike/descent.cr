require "../roguelike"

module Roguelike
  # A number on every square saying how many steps it is from a goal.
  #
  # The goal holds zero, every square beside it holds one, and so on outward.
  # A creature walks a shortest path by stepping to whichever neighbor holds
  # a smaller number than the square it is standing on. The search runs once
  # for a whole band rather than once for each of its members, and the
  # creatures themselves search for nothing.
  #
  # It is built over what somebody believes rather than over the floor. A
  # square nobody has looked at is not in it, so a band does not walk a
  # shortcut it has never found. One that remembers a door as shut paths
  # through it only when its members open doors.
  #
  # This is derived rather than stored. It is built again whenever the goal
  # moves or the band learns something, and it is not in a save file.
  class Descent
    # Where the goal is.
    getter goal : {Int32, Int32}

    # The first column and row the distances cover, and how many of each.
    @left : Int32
    @top : Int32
    @columns : Int32
    @rows : Int32

    # How many steps each square of the box is from the goal, or -1 for a
    # square the descent never reached.
    @away : Slice(Int32)

    # Every square reached, in the order the flood reached it.
    @order : Array({Int32, Int32})

    # `#steps`, once something has asked for it.
    @steps : Hash({Int32, Int32}, Int32)? = nil

    # How far a descent is built before it stops.
    #
    # A band chasing something across a floor it knows well would otherwise
    # flood every square it has ever seen. Nothing pursues from further off
    # than this, so nothing past it is worth the work.
    LIMIT = 40

    def initialize(@goal : {Int32, Int32},
                   steps : Hash({Int32, Int32}, Int32) = {} of {Int32, Int32} => Int32)
      left = right = @goal[0]
      top = bottom = @goal[1]
      steps.each_key do |spot|
        left = Math.min left, spot[0]
        right = Math.max right, spot[0]
        top = Math.min top, spot[1]
        bottom = Math.max bottom, spot[1]
      end

      @left = left
      @top = top
      @columns = right - left + 1
      @rows = bottom - top + 1
      @away = Slice(Int32).new @columns * @rows, -1
      @order = [] of {Int32, Int32}
      steps.each do |spot, away|
        @away[index(spot[0], spot[1])] = away
        @order << spot
      end
    end

    private def initialize(@goal : {Int32, Int32}, @left : Int32, @top : Int32,
                           @columns : Int32, @rows : Int32, @away : Slice(Int32),
                           @order : Array({Int32, Int32}))
    end

    # How many steps each square is from the goal, in the order the flood
    # reached them.
    def steps : Hash({Int32, Int32}, Int32)
      @steps ||= begin
        found = {} of {Int32, Int32} => Int32
        @order.each { |spot| found[spot] = @away[index(spot[0], spot[1])] }
        found
      end
    end

    # Yields every square reached and its distance, in the order the flood
    # reached them.
    def each(& : {Int32, Int32}, Int32 ->) : Nil
      @order.each { |spot| yield spot, @away[index(spot[0], spot[1])] }
    end

    private def index(x : Int32, y : Int32) : Int32
      (y - @top) * @columns + x - @left
    end

    private def covers?(x : Int32, y : Int32) : Bool
      x >= @left && y >= @top && x < @left + @columns && y < @top + @rows
    end

    # The descent over *knowledge* toward *goal*, no further than *limit*.
    #
    # The goal square goes in whatever is remembered of it, so a creature
    # walks to where it believes the character is standing.
    #
    # *doors* crosses a door remembered as shut, unless it is known to be
    # spiked against whoever holds *knowledge*. A route the person picked
    # does that, and so does a band whose members open doors. The default
    # leaves a shut door in the way.
    #
    # *avoid* names squares the flood treats as solid. A creature whose way is
    # held by another creature floods with that square in it, and so finds the
    # way round.
    #
    # *keep*, when given, names the only squares the flood may enter besides
    # the goal. A walk that must stay in one room floods with that room's
    # squares.
    def self.toward(knowledge : Knowledge, goal : {Int32, Int32},
                    limit : Int32 = LIMIT, doors : Bool = false,
                    avoid : Set({Int32, Int32}) = EMPTY,
                    keep : Set({Int32, Int32})? = nil) : Descent
      grid = knowledge.grid
      wanted_flag = doors ? Knowledge::Grid::CROSS : Knowledge::Grid::WALK
      left, top, right, bottom = box grid, goal, limit
      columns = right - left
      rows = bottom - top

      reached = Slice(Int32).new columns * rows, -1
      order = [goal]
      reached[(goal[1] - top) * columns + goal[0] - left] = 0
      edge = [goal]
      away = 0

      while !edge.empty? && away < limit
        away += 1
        wave = [] of {Int32, Int32}

        edge.each do |spot|
          DIRECTIONS.each do |direction|
            wanted = direction.from spot[0], spot[1]
            x, y = wanted
            next unless x >= left && y >= top && x < right && y < bottom

            at = (y - top) * columns + x - left
            next if reached[at] >= 0
            next unless admits? wanted, avoid, keep
            next if grid[x, y] & wanted_flag == 0

            reached[at] = away
            order << wanted
            wave << wanted
          end
        end

        edge = wave
      end

      new goal, left, top, columns, rows, reached, order
    end

    # Whether *avoid* and *keep* let a flood onto *spot*.
    private def self.admits?(spot : {Int32, Int32}, avoid : Set({Int32, Int32}),
                             keep : Set({Int32, Int32})?) : Bool
      return false if avoid.includes? spot

      keep.nil? || keep.includes?(spot)
    end

    # The box a flood toward *goal* over *grid* can reach in *limit* steps,
    # as its left, top, right and bottom edges, the last two exclusive.
    #
    # Every square reached is within *limit* steps of the goal and is one the
    # grid holds, so the box is where those two overlap. It always holds the
    # goal.
    private def self.box(grid : Knowledge::Grid, goal : {Int32, Int32},
                         limit : Int32) : {Int32, Int32, Int32, Int32}
      reach = Math.min limit, 1 << 24
      left = Math.max grid.left, goal[0] - reach
      top = Math.max grid.top, goal[1] - reach
      right = Math.min grid.left + grid.columns, goal[0] + reach + 1
      bottom = Math.min grid.top + grid.rows, goal[1] + reach + 1
      {Math.min(left, goal[0]), Math.min(top, goal[1]),
       Math.max(right, goal[0] + 1), Math.max(bottom, goal[1] + 1)}
    end

    # Every direction, in the order `Direction` names them.
    DIRECTIONS = Direction.values

    # How many steps *x*, *y* is from the goal. `nil` for a square the
    # descent never reached.
    def [](x : Int32, y : Int32) : Int32?
      return unless covers? x, y

      away = @away[index(x, y)]
      away < 0 ? nil : away
    end

    # :ditto:
    def [](spot : {Int32, Int32}) : Int32?
      self[spot[0], spot[1]]
    end

    # How many squares the descent reached.
    def size : Int32
      @order.size
    end

    # Whether the descent reached *x*, *y*.
    def includes?(x : Int32, y : Int32) : Bool
      !self[x, y].nil?
    end

    # Which way to step from *x*, *y* to get one square nearer the goal.
    #
    # `nil` when nothing beside it is nearer: the goal itself, a square the
    # descent never reached, and a dead end all answer that. A creature that
    # is given `nil` stays where it is.
    #
    # *blocked* names the squares something else is standing on. A creature
    # waits rather than walking into its neighbor.
    #
    # Only a square strictly nearer the goal counts, never one the same
    # distance off. `Pursuit` decides what a creature does when every square
    # nearer is taken.
    #
    # Several neighbors are usually the same distance nearer, because a
    # diagonal step costs what a straight one does. `.nearest` picks between
    # them, and ties there go to whichever direction `Direction` names first,
    # so a band walks the same way twice from the same seed.
    def toward(x : Int32, y : Int32,
               blocked : Set({Int32, Int32}) = EMPTY) : Direction?
      Descent.nearest downhill(x, y, blocked), {x, y}, @goal
    end

    # Every direction from *x*, *y* that is as near the goal as any is.
    #
    # Empty when nothing beside the square is nearer than the square itself.
    def downhill(x : Int32, y : Int32,
                 blocked : Set({Int32, Int32}) = EMPTY) : Array(Direction)
      here = self[x, y]
      return NOWHERE if here.nil? || here.zero?

      best = here
      found = [] of Direction

      DIRECTIONS.each do |direction|
        wanted = direction.from x, y
        next if blocked.includes? wanted

        away = self[wanted]
        next unless away && away < here

        if away < best
          best = away
          found.clear
        end

        found << direction if away == best
      end

      found
    end

    # Every direction from *x*, *y* that leaves the square as far from the
    # goal as the one it is standing on.
    #
    # A creature that puts a foot wrong takes one of these. It has not gone
    # the wrong way, it has gone sideways, and whatever it is chasing has
    # gained a square. There are none of these in a corridor, which is why
    # nothing can be shaken off in one.
    def sideways(x : Int32, y : Int32,
                 blocked : Set({Int32, Int32}) = EMPTY) : Array(Direction)
      here = self[x, y]
      return NOWHERE if here.nil? || here.zero?

      found = [] of Direction

      DIRECTIONS.each do |direction|
        wanted = direction.from x, y
        next if blocked.includes? wanted
        next unless self[wanted] == here

        found << direction
      end

      found
    end

    # Every direction from *x*, *y* onto a square further from the goal than
    # the one the creature is standing on.
    #
    # A neighbor is never more than one step further than the square, so each
    # of these is exactly one step further. A creature running from the goal
    # takes one of them. Empty for a square the descent never reached and for
    # one with nothing further off beside it.
    def uphill(x : Int32, y : Int32,
               blocked : Set({Int32, Int32}) = EMPTY) : Array(Direction)
      here = self[x, y]
      return NOWHERE unless here

      DIRECTIONS.select do |direction|
        wanted = direction.from x, y
        next false if blocked.includes? wanted

        away = self[wanted]
        !away.nil? && away > here
      end
    end

    # No way down at all. What `#downhill` answers for a dead end.
    NOWHERE = [] of Direction

    # Which of *found* heads most nearly along the line from *at* to *goal*.
    #
    # Every one of them is the same number of steps from the goal, so the map
    # has nothing left to say. What decides it is which of them looks like
    # walking at the goal: a creature that picks by the order the directions
    # happen to be declared walks diagonally until one axis lines up and
    # straight after that, which is the same number of turns and reads as a
    # creature heading somewhere else.
    def self.nearest(found : Array(Direction), at : {Int32, Int32},
                     goal : {Int32, Int32}) : Direction?
      return if found.empty?
      return found.first if found.size == 1

      step = Line.step at, goal
      return found.first unless step

      wanted = {step[0] - at[0], step[1] - at[1]}
      found.min_by do |direction|
        (direction.dx - wanted[0]).abs + (direction.dy - wanted[1]).abs
      end
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
      io << ' ' << size << " squares)"
    end
  end
end
