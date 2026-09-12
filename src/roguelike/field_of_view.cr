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
  # same side of it every time. Floating point would make the answer depend on
  # rounding.
  #
  # A field of view is derived rather than stored. It is recomputed from the
  # floor and a position, and it is not in a save file. `Knowledge` is what
  # remembers a floor between one look and the next.
  class FieldOfView
    # Where the creature stands.
    getter origin : {Int32, Int32}

    # Every square that can be seen, the origin included.
    getter visible : Set({Int32, Int32})

    def initialize(@origin : {Int32, Int32},
                   @visible : Set({Int32, Int32}) = Set({Int32, Int32}).new)
      @visible << @origin
    end

    # What can be seen from *x*, *y* of *floor*.
    def self.from(floor : Floor, x : Int32, y : Int32) : FieldOfView
      sight = new({x, y})
      sight.cast floor
      sight
    end

    # :ditto:
    def self.from(floor : Floor, spot : {Int32, Int32}) : FieldOfView
      from floor, spot[0], spot[1]
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

    # The slope of the near edge of the square at *depth*, *column*.
    private def edge(depth : Int32, column : Int32) : Fraction
      Fraction.new 2 * column - 1, 2 * depth
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
      Quadrant.each do |quadrant|
        scan floor, quadrant, 1, Fraction.new(-1, 1), Fraction.new(1, 1)
      end
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
    # *start_slope* and *end_slope* are the wedge still being looked through.
    # A wall inside the row narrows the wedge for the rows behind it: the
    # scan recurses with the tighter end, and carries on with the tighter
    # start.
    private def scan(floor : Floor, quadrant : Quadrant, depth : Int32,
                     start_slope : Fraction, end_slope : Fraction) : Nil
      seen_any = false
      was_wall = false

      (start_slope.up_at(depth)..end_slope.down_at(depth)).each do |column|
        spot = place quadrant, depth, column

        # Past the edge of the floor is treated as solid, so the scan stops
        # there. It is not recorded as seen, because there is nothing there
        # to see.
        on_floor = floor.contains? spot[0], spot[1]
        wall = !on_floor || floor.blocks_sight?(spot[0], spot[1])

        # A wall is seen whenever the scan reaches it. A floor square is seen
        # when its centre is inside the wedge.
        if on_floor &&
           (wall || (start_slope.below?(depth, column) && end_slope.above?(depth, column)))
          @visible << spot
        end

        if seen_any && was_wall != wall
          if wall
            scan floor, quadrant, depth + 1, start_slope, edge(depth, column)
          else
            start_slope = edge depth, column
          end
        end

        seen_any = true
        was_wall = wall
      end

      # The row ended on open ground, so the wedge carries on unchanged.
      scan floor, quadrant, depth + 1, start_slope, end_slope if seen_any && !was_wall
    end
  end
end
