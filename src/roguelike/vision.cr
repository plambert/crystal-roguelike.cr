require "./field_of_view"
require "./lighting"

module Roguelike
  # What a creature can actually see.
  #
  # Two things decide that. The field of view says what a creature has a line
  # to. The lighting says what has light on it. A square is seen when it is
  # both.
  #
  # That is what makes a distant lit room visible across a dark one: the line
  # runs the whole way, and the far room is the part with light on it. It is
  # also what makes an unlit corridor invisible from one step away.
  #
  # The square a creature stands on is always seen. A person in the dark
  # knows where their own feet are.
  #
  # A `nil` lighting lights everything. A spec that is not about light then
  # needs to say nothing about light.
  class Vision
    # What the creature has a line to.
    getter field : FieldOfView

    # What has light on it. `nil` lights everything.
    getter lighting : Lighting?

    def initialize(@field : FieldOfView, @lighting : Lighting? = nil)
    end

    # Where the creature stands.
    def origin : {Int32, Int32}
      @field.origin
    end

    # What can be seen from *x*, *y* of *floor* by the light of *sources*.
    def self.from(floor : Floor, x : Int32, y : Int32,
                  sources : Enumerable(LightSource)) : Vision
      new FieldOfView.from(floor, x, y), Lighting.over(floor, sources)
    end

    # :ditto:
    def self.from(floor : Floor, spot : {Int32, Int32},
                  sources : Enumerable(LightSource)) : Vision
      from floor, spot[0], spot[1], sources
    end

    # A vision with a line to everything it can reach and light everywhere.
    def self.lit(floor : Floor, x : Int32, y : Int32) : Vision
      new FieldOfView.from(floor, x, y)
    end

    # Whether *x*, *y* can be seen.
    def includes?(x : Int32, y : Int32) : Bool
      return true if {x, y} == origin
      return false unless @field.includes? x, y

      found = @lighting
      found ? found.lit?(x, y) : true
    end

    # :ditto:
    def includes?(spot : {Int32, Int32}) : Bool
      includes? spot[0], spot[1]
    end

    # How many squares can be seen.
    def size : Int32
      count = 0
      @field.each { |spot| count += 1 if includes? spot }
      count += 1 unless @field.includes? origin
      count
    end

    # Yields every square that can be seen. In no order.
    def each(& : {Int32, Int32} ->) : Nil
      yield origin
      @field.each do |spot|
        next if spot == origin

        yield spot if includes? spot
      end
    end

    # How much light *x*, *y* has. Zero when nothing lights it.
    def light(x : Int32, y : Int32) : Int32
      found = @lighting
      found ? found.level(x, y) : 0
    end

    # *floor* drawn with *unseen* wherever this vision does not reach.
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
      io << "Vision(" << origin[0] << ',' << origin[1] << ' ' << size << " seen)"
    end
  end
end
