require "../roguelike"

module Roguelike
  # One room as somebody knows it, or the part of one that lies in one cell of
  # the coarse grid.
  #
  # Its id is its anchor, the first of its open squares in reading order.
  # The anchor depends on this chamber's own squares and on nothing else, so
  # learning another part of the floor leaves the id where it was.
  class Chamber
    # What an item known to lie in a chamber is, and where.
    record Lying, at : {Int32, Int32}, item : Item

    # The first open square in reading order. This is the chamber's id.
    getter anchor : {Int32, Int32}

    # Every square of it, in reading order. The open squares and the ring of
    # walkable ground between them and the walls.
    getter squares : Array({Int32, Int32})

    # The squares outside it that lead out of it. A door, the mouth of a
    # corridor, or a gap in a wall.
    getter exits : Array({Int32, Int32})

    # The anchors of chambers that touch this one with no passage between.
    # A room larger than a cell of the grid is several chambers that do this.
    getter neighbors : Array({Int32, Int32})

    # The items remembered on its squares, the top one of each pile.
    getter items : Array(Lying)

    # Whether any of its squares borders a square not yet seen.
    getter? frontier : Bool

    def initialize(@anchor : {Int32, Int32}, @squares : Array({Int32, Int32}),
                   @exits : Array({Int32, Int32}),
                   @neighbors : Array({Int32, Int32}),
                   @items : Array(Lying), @frontier : Bool)
    end

    # Whether every square of it and every square beside it has been seen.
    def seen? : Bool
      !@frontier
    end

    def to_s(io : IO) : Nil
      io << "Chamber(" << @anchor[0] << ',' << @anchor[1] << ' '
      io << @squares.size << " squares"
      io << " frontier" if @frontier
      io << ')'
    end
  end

  # A run of corridor squares between chambers.
  #
  # Every walkable square that belongs to no chamber is in one of these:
  # corridors, doors, and ground too narrow to hold an open square.
  class Passage
    # Every square of it, in reading order.
    getter squares : Array({Int32, Int32})

    # The anchors of the chambers it touches, in reading order.
    getter chambers : Array({Int32, Int32})

    # Its squares with three or more ways off them across the four sides.
    getter junctions : Array({Int32, Int32})

    # Its squares with exactly one walkable square beside them.
    getter dead_ends : Array({Int32, Int32})

    def initialize(@squares : Array({Int32, Int32}),
                   @chambers : Array({Int32, Int32}),
                   @junctions : Array({Int32, Int32}),
                   @dead_ends : Array({Int32, Int32}))
    end
  end

  # What somebody knows of a floor, cut into chambers and the passages
  # between them.
  #
  # A square is open when it and the eight squares around it are all known
  # ground that is not a door. Open squares that touch flood together into a
  # chamber. A door and a corridor one or two squares wide hold no open
  # square, so they cut chambers apart. The walkable squares beside a
  # chamber's open squares join it, which takes in the ring of floor along a
  # room's walls.
  #
  # The flood stops at the lines of a grid of `CELL` squares laid from the
  # floor's corner. A large cave is then several chambers rather than one
  # that grows across the floor, and the anchor of each stays inside its own
  # cell however much more of the cave is found.
  #
  # Nothing here reads a `Floor`. It is built from `Knowledge` alone, and
  # `Knowledge#chambers` keeps it until the knowledge changes.
  class Chambers
    # How wide and tall a cell of the grid is.
    CELL = 24

    # What the squares were cut from.
    getter columns : Int32
    getter rows : Int32

    # The `Knowledge#revision` this was built at.
    getter revision : Int32

    # Every chamber, by anchor in reading order.
    getter chambers : Array(Chamber)

    # Every passage, by first square in reading order.
    getter passages : Array(Passage)

    # Which chamber each square belongs to, as an index into `#chambers`, or
    # -1 for none.
    @owner : Array(Int32)

    # Whether each square is walkable and borders a square not yet seen.
    @edge : Array(Bool)

    def initialize(@columns : Int32, @rows : Int32, @revision : Int32,
                   @chambers : Array(Chamber), @passages : Array(Passage),
                   @owner : Array(Int32), @edge : Array(Bool))
    end

    # The chamber *x*, *y* belongs to. `nil` for a corridor, a door, a wall
    # and a square not yet seen.
    def at(x : Int32, y : Int32) : Chamber?
      return unless inside? x, y

      index = @owner[y * @columns + x]
      index < 0 ? nil : @chambers[index]
    end

    # :ditto:
    def at(spot : {Int32, Int32}) : Chamber?
      at spot[0], spot[1]
    end

    # The chamber whose anchor is *anchor*.
    def [](anchor : {Int32, Int32}) : Chamber?
      found = at anchor
      found if found && found.anchor == anchor
    end

    # Whether *x*, *y* is walkable and borders a square not yet seen.
    #
    # Standing on one shows what is beside it. These are where explore goes.
    def frontier?(x : Int32, y : Int32) : Bool
      inside?(x, y) && @edge[y * @columns + x]
    end

    # Whether `#frontier?` holds for any square.
    def frontier? : Bool
      @edge.includes? true
    end

    # Every square `#frontier?` holds for, in reading order.
    def frontier : Array({Int32, Int32})
      found = [] of {Int32, Int32}
      @edge.each_with_index do |edge, index|
        found << {index % @columns, index // @columns} if edge
      end
      found
    end

    private def inside?(x : Int32, y : Int32) : Bool
      x >= 0 && y >= 0 && x < @columns && y < @rows
    end

    # The eight ways off a square, as offsets. The order is fixed, so what
    # a tie picks is the same every time.
    AROUND = [{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}]

    # The four sides of a square, as offsets.
    SIDES = [{0, -1}, {-1, 0}, {1, 0}, {0, 1}]

    # Cuts what *knowledge* holds of a floor of *columns* by *rows*.
    def self.of(knowledge : Knowledge, columns : Int32, rows : Int32) : Chambers
      Cutting.new(knowledge, columns, rows).cut
    end

    # The work of one cut. Every grid is one flat array over the floor.
    private class Cutting
      @size : Int32

      # Whether the square has been seen.
      @known : Array(Bool)

      # Whether the square is known ground a chamber can hold. Such a square
      # is walkable and is not a door.
      @ground : Array(Bool)

      # Whether the square can be crossed, doors and openings counted.
      @cross : Array(Bool)

      # Whether the square is open.
      @open : Array(Bool)

      @owner : Array(Int32)

      # Each chamber's anchor, by its number.
      @anchors = [] of {Int32, Int32}

      def initialize(@knowledge : Knowledge, @columns : Int32, @rows : Int32)
        @size = @columns * @rows
        @known = Array(Bool).new @size, false
        @ground = Array(Bool).new @size, false
        @cross = Array(Bool).new @size, false
        @open = Array(Bool).new @size, false
        @owner = Array(Int32).new @size, -1
      end

      def cut : Chambers
        read
        mark_open
        flood
        skirt
        edge = edges

        members = Array.new(@anchors.size) { [] of Int32 }
        @size.times { |square| members[@owner[square]] << square unless @owner[square] < 0 }

        chambers = @anchors.map_with_index { |anchor, number| chamber anchor, number, members[number], edge }
        Chambers.new @columns, @rows, @knowledge.revision, chambers, passages,
          @owner, edge
      end

      private def index(x : Int32, y : Int32) : Int32?
        return if x < 0 || y < 0 || x >= @columns || y >= @rows

        y * @columns + x
      end

      private def spot(index : Int32) : {Int32, Int32}
        {index % @columns, index // @columns}
      end

      private def cell(index : Int32) : {Int32, Int32}
        {(index % @columns) // CELL, (index // @columns) // CELL}
      end

      # Each index beside *index* that is on the floor, in `AROUND` order.
      private def around(index : Int32, & : Int32 ->) : Nil
        x, y = spot index
        AROUND.each do |offset|
          found = index(x + offset[0], y + offset[1])
          yield found if found
        end
      end

      # Fills the three grids the cut reads from what is remembered.
      private def read : Nil
        @knowledge.each do |column, row, memory|
          at = index column, row
          next unless at

          terrain = memory.terrain
          @known[at] = true
          @ground[at] = terrain.passable? && !terrain.door?
          @cross[at] = @knowledge.crossable? column, row
        end

        @knowledge.openings.each do |key|
          parts = key.split ','
          at = index parts[0].to_i, parts[1].to_i
          @cross[at] = true if at && !@known[at]
        end
      end

      # Marks every square whose block of nine is all ground.
      private def mark_open : Nil
        @size.times do |square|
          next unless @ground[square]

          x, y = spot square
          @open[square] = AROUND.all? do |offset|
            found = index(x + offset[0], y + offset[1])
            !found.nil? && @ground[found]
          end
        end
      end

      # Floods the open squares into chambers, cell by cell, and records each
      # chamber's anchor.
      #
      # The scan runs in reading order, so the square that starts a flood is
      # the first open square of its chamber in that order.
      private def flood : Nil
        @size.times do |start|
          next unless @open[start] && @owner[start] < 0

          number = @anchors.size
          @anchors << spot(start)
          home = cell start
          @owner[start] = number
          queue = Deque{start}

          while at = queue.shift?
            around at do |next_to|
              next unless @open[next_to] && @owner[next_to] < 0
              next unless cell(next_to) == home

              @owner[next_to] = number
              queue << next_to
            end
          end
        end
      end

      # Gives each ground square beside an open square to that square's
      # chamber. The first open square in `AROUND` order wins a tie.
      private def skirt : Nil
        taken = @owner.dup

        @size.times do |square|
          next if !@ground[square] || @open[square]

          around square do |next_to|
            next unless @open[next_to]

            taken[square] = @owner[next_to]
            break
          end
        end

        @owner = taken
      end

      # Whether each square can be crossed and borders one not yet seen.
      #
      # A square crossed only by inference is unseen itself, so it counts.
      private def edges : Array(Bool)
        Array.new(@size) do |square|
          next false unless @cross[square]
          next true unless @known[square]

          bordering = false
          around(square) { |next_to| bordering = true unless @known[next_to] }
          bordering
        end
      end

      private def chamber(anchor : {Int32, Int32}, number : Int32,
                          members : Array(Int32), edge : Array(Bool)) : Chamber
        squares = [] of {Int32, Int32}
        exits = Set({Int32, Int32}).new
        neighbors = Set({Int32, Int32}).new
        items = [] of Chamber::Lying
        frontier = false

        members.each do |square|
          here = spot square
          squares << here
          frontier ||= edge[square]
          lying = @knowledge[here].try &.item
          items << Chamber::Lying.new(here, lying) if lying

          around square do |next_to|
            next unless @cross[next_to]

            other = @owner[next_to]
            if other < 0
              exits << spot(next_to)
            elsif other != number
              neighbors << @anchors[other]
            end
          end
        end

        Chamber.new anchor, squares, Chambers.ordered(exits),
          Chambers.ordered(neighbors), items, frontier
      end

      # Every passage: the crossable squares no chamber holds, flooded
      # together across the eight ways off a square.
      private def passages : Array(Passage)
        found = [] of Passage
        seen = Array(Bool).new @size, false

        @size.times do |start|
          next if !@cross[start] || @owner[start] >= 0 || seen[start]

          seen[start] = true
          queue = Deque{start}
          squares = [] of Int32

          while at = queue.shift?
            squares << at
            around at do |next_to|
              next if !@cross[next_to] || @owner[next_to] >= 0 || seen[next_to]

              seen[next_to] = true
              queue << next_to
            end
          end

          found << passage(squares.sort!)
        end

        found
      end

      private def passage(squares : Array(Int32)) : Passage
        chambers = Set({Int32, Int32}).new
        junctions = [] of {Int32, Int32}
        dead_ends = [] of {Int32, Int32}

        squares.each do |square|
          ways = 0
          around square do |next_to|
            next unless @cross[next_to]

            ways += 1
            other = @owner[next_to]
            chambers << @anchors[other] unless other < 0
          end

          x, y = spot square
          sides = SIDES.count do |offset|
            found = index(x + offset[0], y + offset[1])
            !found.nil? && @cross[found]
          end

          junctions << {x, y} if sides >= 3
          dead_ends << {x, y} if ways == 1
        end

        Passage.new squares.map { |square| spot square }, Chambers.ordered(chambers),
          junctions, dead_ends
      end
    end

    # *spots* in reading order.
    def self.ordered(spots : Enumerable({Int32, Int32})) : Array({Int32, Int32})
      spots.to_a.sort_by! { |spot| {spot[1], spot[0]} }
    end

    # The chambers drawn over a floor of the size this was cut from.
    #
    # Each chamber's squares hold a letter, `a` for the first anchor in
    # reading order and on through the alphabet, then `A` to `Z`, then `*`.
    # A passage square holds `+`, anything else *other*. For a spec and for
    # reading a failure, the way `Knowledge#to_map` is.
    def to_map(other : Char = ' ') : Array(String)
      letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
      corridor = Set({Int32, Int32}).new
      @passages.each { |found| found.squares.each { |spot| corridor << spot } }

      Array.new(@rows) do |row|
        String.build(@columns) do |line|
          @columns.times do |column|
            owner = @owner[row * @columns + column]
            line << if owner >= 0
              letters[owner]? || '*'
            elsif corridor.includes?({column, row})
              '+'
            else
              other
            end
          end
        end
      end
    end
  end
end
