require "json"

module Roguelike
  # The character being played.
  #
  # Where they are, and nothing else yet. Attributes, hit points, experience
  # and what they are carrying arrive with the phases that need them, and
  # arrive here.
  #
  # The level is held by its id rather than by a reference to the `Level`,
  # because levels persist and are saved: a save file that held the level
  # twice, once in the world and once under the player, would have two of them
  # to keep in step.
  class Player
    include JSON::Serializable

    # Which level they are on.
    property level : String

    # Where on it.
    getter x : Int32

    # :ditto:
    getter y : Int32

    def initialize(@level : String, @x : Int32, @y : Int32)
    end

    # Where they are.
    def at : {Int32, Int32}
      {@x, @y}
    end

    # Puts them at *x*, *y*. Whether they could be there is the caller's
    # question, and `Game#step` is where it is asked.
    def move_to(x : Int32, y : Int32) : Nil
      @x = x
      @y = y
    end

    # :ditto:
    def move_to(spot : {Int32, Int32}) : Nil
      move_to spot[0], spot[1]
    end

    # Whether they are standing on *x*, *y*.
    def at?(x : Int32, y : Int32) : Bool
      @x == x && @y == y
    end

    def to_s(io : IO) : Nil
      io << "Player(" << @level << ' ' << @x << ',' << @y << ')'
    end
  end
end
