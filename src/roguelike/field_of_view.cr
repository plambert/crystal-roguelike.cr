require "./floor"

module Roguelike
  # Which squares a creature can see from where it stands.
  #
  # The algorithm is Albert Ford's symmetric shadowcasting. It scans four
  # quadrants out from the origin, one row of each at a time, narrowing the
  # wedge of slopes it is still looking through whenever a wall cuts into it.
  #
  # Symmetric means what it says: if A can see B then B can see A. A floor
  # square is seen when its centre is inside the wedge. A wall square is seen
  # whenever the scan reaches it at all, because a wall a creature cannot see
  # the centre of is still a wall they can see the face of.
  #
  # Every comparison is on whole numbers. A slope is a `Fraction` of two
  # integers rather than a float, so a square on the edge of a wedge falls the
  # same side of it every time. Floating point would make which side it falls
  # depend on rounding.
  #
  # A field of view is derived rather than stored. It is recomputed from the
  # floor and a position, and it is not in a save file. `Knowledge` is what
  # remembers a floor between one look and the next.
  class FieldOfView
    # Where the creature stands.
    getter origin : {Int32, Int32}

    # Every square that can be seen, the origin included.
    getter visible : Set({Int32, Int32})

    # How far sight reaches. `nil` reaches as far as the floor does.
    #
    # A light source has one. A creature looking about a lit floor does not.
    # The limit is a circle rather than a square: a square is inside it when
    # it is within *radius* of the origin by straight-line distance.
    getter radius : Int32?

    def initialize(@origin : {Int32, Int32},
                   @visible : Set({Int32, Int32}) = Set({Int32, Int32}).new,
                   @radius : Int32? = nil)
      @visible << @origin
    end

    # What can be seen from *x*, *y* of *floor*, no further than *radius*.
    def self.from(floor : Floor, x : Int32, y : Int32,
                  radius : Int32? = nil) : FieldOfView
      sight = new({x, y}, radius: radius)
      sight.cast floor
      sight
    end

    # :ditto:
    def self.from(floor : Floor, spot : {Int32, Int32},
                  radius : Int32? = nil) : FieldOfView
      from floor, spot[0], spot[1], radius
    end

    # Whether *x*, *y* is within `#radius` of the origin.
    private def in_range?(x : Int32, y : Int32) : Bool
      reach = @radius
      return true unless reach

      across = x - @origin[0]
      down = y - @origin[1]

      across * across + down * down <= reach * reach
    end

    # Whether *x*, *y* can be seen.
    def includes?(x : Int32, y : Int32) : Bool
      @visible.includes?({x, y})
    end

    # :ditto:
    def includes?(spot : {Int32, Int32}) : Bool
      @visible.includes? spot
    end

    # How many squares can be seen.
    def size : Int32
      @visible.size
    end

    # Yields every square that can be seen. In no order.
    def each(& : {Int32, Int32} ->) : Nil
      @visible.each { |spot| yield spot }
    end

    # *floor* drawn with *unseen* wherever this field of view does not reach.
    #
    # For a spec and for reading a failure. A fixture holds one of these, so a
    # change to the algorithm shows as a diff of two maps.
    def to_map(floor : Floor, unseen : Char = '?') : Array(String)
      Array.new(floor.rows) do |row|
        String.build(floor.columns) do |line|
          floor.columns.times do |column|
            line << (includes?(column, row) ? floor.terrain(column, row).mark : unseen)
          end
        end
      end
    end

    def to_s(io : IO) : Nil
      io << "FieldOfView(" << @origin[0] << ',' << @origin[1]
      io << ' ' << @visible.size << " seen)"
    end

    # ------------------------------------------------------------ the scan

    # A slope, as an exact fraction. The denominator is never zero and never
    # negative, so a comparison can cross-multiply without flipping.
    struct Fraction
      getter numerator : Int32
      getter denominator : Int32

      def initialize(@numerator : Int32, @denominator : Int32)
        raise ArgumentError.new "a slope needs a denominator" if @denominator.zero?

        if @denominator < 0
          @numerator = -@numerator
          @denominator = -@denominator
        end
      end

      # The whole number nearest this slope at *depth*, ties going up.
      #
      # That is `floor(depth * self + 1/2)`, worked out without dividing.
      def up_at(depth : Int32) : Int32
        top = 2_i64 * depth * @numerator + @denominator
        (top // (2_i64 * @denominator)).to_i32
      end

      # The whole number nearest this slope at *depth*, ties going down.
      #
      # That is `ceil(depth * self - 1/2)`.
      def down_at(depth : Int32) : Int32
        top = 2_i64 * depth * @numerator - @denominator
        bottom = 2_i64 * @denominator

        (-((-top) // bottom)).to_i32
      end

      # Whether *column* at *depth* is at or past this slope.
      def below?(depth : Int32, column : Int32) : Bool
        column.to_i64 * @denominator >= depth.to_i64 * @numerator
      end

      # Whether *column* at *depth* is at or short of this slope.
      def above?(depth : Int32, column : Int32) : Bool
        column.to_i64 * @denominator <= depth.to_i64 * @numerator
      end

      def to_s(io : IO) : Nil
        io << @numerator << '/' << @denominator
      end
    end

    # One row of a quadrant: how far out from the origin it is, and the wedge
    # of slopes still being looked through at that distance.
    struct Row
      # How many squares out from the origin.
      getter depth : Int32

      # The near edge of the wedge.
      property start_slope : Fraction

      # The far edge.
      property end_slope : Fraction

      def initialize(@depth : Int32, @start_slope : Fraction, @end_slope : Fraction)
      end

      # The first row of a quadrant. The wedge is the whole 90 degrees.
      def self.first : Row
        new 1, Fraction.new(-1, 1), Fraction.new(1, 1)
      end

      # Which columns of this row the wedge covers.
      def columns : Range(Int32, Int32)
        @start_slope.up_at(@depth)..@end_slope.down_at(@depth)
      end

      # The row behind this one, through the same wedge.
      def behind : Row
        Row.new @depth + 1, @start_slope, @end_slope
      end

      # The row behind this one, through a wedge ending at *slope*.
      def behind(slope : Fraction) : Row
        Row.new @depth + 1, @start_slope, slope
      end

      # Whether the centre of *column* is inside the wedge.
      def holds?(column : Int32) : Bool
        @start_slope.below?(@depth, column) && @end_slope.above?(@depth, column)
      end
    end

    # The slope of the near edge of the square at *depth*, *column*.
    private def edge(depth : Int32, column : Int32) : Fraction
      Fraction.new 2 * column - 1, 2 * depth
    end

    # Whether *spot* stops the scan.
    #
    # Past the edge of the floor stops it, because there is nothing beyond
    # the floor to see.
    private def solid?(floor : Floor, spot : {Int32, Int32}) : Bool
      !floor.contains?(spot[0], spot[1]) || floor.blocks_sight?(spot[0], spot[1])
    end

    # Whether *spot* is seen from the origin.
    #
    # A wall is seen whenever the scan reaches it, because a wall a creature
    # cannot see the centre of is still a wall they can see the face of. A
    # floor square is seen when its centre is inside the wedge.
    #
    # Neither is seen past the edge of the floor or past `#radius`.
    private def seen?(floor : Floor, spot : {Int32, Int32}, wall : Bool,
                      row : Row, column : Int32) : Bool
      return false unless floor.contains? spot[0], spot[1]
      return false unless in_range? spot[0], spot[1]

      wall || row.holds?(column)
    end

    # The four quadrants, as the direction each scans away from the origin.
    #
    # Every quadrant is scanned with the same code. `#place` is what turns a
    # depth and a column of one quadrant into a square of the floor.
    enum Quadrant
      North
      South
      East
      West
    end

    # Fills `#visible` from the origin over *floor*.
    protected def cast(floor : Floor) : Nil
      Quadrant.each { |quadrant| scan floor, quadrant, Row.first }
    end

    # Which square of the floor *depth* and *column* of *quadrant* name.
    private def place(quadrant : Quadrant, depth : Int32, column : Int32) : {Int32, Int32}
      x, y = @origin

      case quadrant
      in .north? then {x + column, y - depth}
      in .south? then {x + column, y + depth}
      in .east?  then {x + depth, y + column}
      in .west?  then {x - depth, y + column}
      end
    end

    # Scans one row of one quadrant, and whatever rows follow from it.
    #
    # A wall inside the row narrows the wedge for the rows behind it. The
    # scan recurses into the rows behind with the tighter far edge, and
    # carries on along this row with the tighter near edge.
    private def scan(floor : Floor, quadrant : Quadrant, row : Row) : Nil
      reach = @radius
      return if reach && row.depth > reach

      seen_any = false
      was_wall = false

      row.columns.each do |column|
        spot = place quadrant, row.depth, column
        wall = solid? floor, spot

        @visible << spot if seen? floor, spot, wall, row, column

        if seen_any && was_wall != wall
          if wall
            scan floor, quadrant, row.behind(edge row.depth, column)
          else
            row.start_slope = edge row.depth, column
          end
        end

        seen_any = true
        was_wall = wall
      end

      # The row ended on open ground, so the wedge carries on unchanged.
      scan floor, quadrant, row.behind if seen_any && !was_wall
    end
  end
end
