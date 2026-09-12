require "json"

module Roguelike
  # The character the person plays.
  #
  # A player holds a position and nothing else so far. Later phases add
  # attributes, hit points, experience and carried items. Those fields go
  # here.
  #
  # The player holds a level id. It does not hold a `Level`. Levels persist
  # and a save file stores them. A save file that stored the level twice would
  # hold one copy in the world and one under the player. The two copies would
  # then need to stay in step.
  class Player
    include JSON::Serializable

    # Which level the character is on.
    property level : String

    # The column the character stands in.
    getter x : Int32

    # The row the character stands in.
    getter y : Int32

    def initialize(@level : String, @x : Int32, @y : Int32)
    end

    # Where the character stands.
    def at : {Int32, Int32}
      {@x, @y}
    end

    # Puts the character at *x*, *y*. This method does not check the square.
    # `Game#step` checks the square.
    def move_to(x : Int32, y : Int32) : Nil
      @x = x
      @y = y
    end

    # :ditto:
    def move_to(spot : {Int32, Int32}) : Nil
      move_to spot[0], spot[1]
    end

    # Whether the character stands on *x*, *y*.
    def at?(x : Int32, y : Int32) : Bool
      @x == x && @y == y
    end

    def to_s(io : IO) : Nil
      io << "Player(" << @level << ' ' << @x << ',' << @y << ')'
    end
  end
end
