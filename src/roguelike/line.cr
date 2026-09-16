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

    # The second square of the line from *from* to *to*, which is one step
    # along it. `nil` when the two are the same square.
    #
    # This is what makes a creature look as though it is coming at you. A
    # step chosen from the sign of the difference goes diagonally until one
    # axis lines up and straight after that, which is the same number of
    # turns and reads as a creature walking at forty-five degrees to wherever
    # it is going. A step along the line spreads the diagonals out, so the
    # creature crosses the ground the way a thrown dagger does.
    def self.step(from : {Int32, Int32}, to : {Int32, Int32}) : {Int32, Int32}?
      return if from == to

      found = nil.as({Int32, Int32}?)
      walk(from, to) do |spot|
        next if spot == from

        found = spot
        break
      end

      found
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
