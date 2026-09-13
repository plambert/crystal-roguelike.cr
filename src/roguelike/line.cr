module Roguelike
  # The squares a straight line passes through.
  #
  # Bresenham. Every step moves one square, and the squares come out in order
  # from the near end. Sight, light and a missile all walk this module, so
  # they cross the same squares.
  module Line
    # Yields every square from *from* to *to*, both ends included.
    def self.walk(from : {Int32, Int32}, to : {Int32, Int32},
                  & : {Int32, Int32} ->) : Nil
      x, y = from
      across = (to[0] - x).abs
      down = -(to[1] - y).abs
      step_x = to[0] > x ? 1 : -1
      step_y = to[1] > y ? 1 : -1
      error = across + down

      loop do
        yield({x, y})
        break if x == to[0] && y == to[1]

        twice = 2 * error

        if twice >= down
          error += down
          x += step_x
        end

        if twice <= across
          error += across
          y += step_y
        end
      end
    end

    # :ditto:, as an array.
    def self.between(from : {Int32, Int32}, to : {Int32, Int32}) : Array({Int32, Int32})
      found = [] of {Int32, Int32}
      walk(from, to) { |spot| found << spot }
      found
    end

    # Yields every square along the line from *from* through *through* and on
    # past it, *reach* squares beyond.
    #
    # The squares up to and including *through* are not yielded. What is
    # behind a creature is what this is for.
    def self.beyond(from : {Int32, Int32}, through : {Int32, Int32},
                    reach : Int32, & : {Int32, Int32} ->) : Nil
      across = through[0] - from[0]
      down = through[1] - from[1]
      return if across.zero? && down.zero?

      # Far enough out that the walk covers *reach* squares past *through*,
      # whatever the slope. One step of the line moves at most one on each
      # axis, so a multiple of the reach is always enough.
      far = {through[0] + across * (reach + 1), through[1] + down * (reach + 1)}

      past = false
      taken = 0

      walk(from, far) do |spot|
        if past
          yield spot
          taken += 1
          return if taken >= reach
        end

        past = true if spot == through
      end
    end
  end
end
