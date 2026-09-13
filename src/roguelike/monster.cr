require "json"
require "./species"

module Roguelike
  # One creature on a floor.
  #
  # A monster knows what it is, where it stands, how hurt it is and which band
  # it belongs to. It decides nothing. Phase 19 gives a band a plan and this
  # class still decides nothing: an AI reads a snapshot and answers an action,
  # and the one owner of the game state applies it.
  class Monster
    include JSON::Serializable

    # What sort of creature it is.
    getter species : Species

    # The column it stands in.
    getter x : Int32

    # The row it stands in.
    getter y : Int32

    # Hit points left. It dies at zero.
    getter hit_points : Int32

    # What it is made of.
    getter attributes : Attributes

    # Which band it belongs to, by `Band#id`.
    #
    # Nothing reads this yet. Every monster is in a band of one until a band
    # has something to share.
    getter band : String

    def initialize(@species : Species, @x : Int32, @y : Int32,
                   @band : String,
                   hit_points : Int32? = nil,
                   attributes : Attributes? = nil)
      @hit_points = hit_points || @species.hit_points
      @attributes = attributes || @species.attributes
    end

    # Where it stands.
    def at : {Int32, Int32}
      {@x, @y}
    end

    # Puts it at *x*, *y*. This method does not check the square. `Floor#walk`
    # checks the square and keeps the floor's own table in step.
    def move_to(x : Int32, y : Int32) : Nil
      @x = x
      @y = y
    end

    # :ditto:
    def move_to(spot : {Int32, Int32}) : Nil
      move_to spot[0], spot[1]
    end

    # Whether it stands on *x*, *y*.
    def at?(x : Int32, y : Int32) : Bool
      @x == x && @y == y
    end

    # Hit points at full health.
    def max_hit_points : Int32
      @species.hit_points
    end

    # Whether it is still alive.
    def alive? : Bool
      @hit_points > 0
    end

    # Takes *amount* off its hit points. Answers how many are left.
    def hurt(amount : Int32) : Int32
      @hit_points = Math.max @hit_points - amount, 0
    end

    # What it is called.
    def label : String
      @species.label
    end

    # A sentence about it, for the examine pane.
    def description : String
      @species.description
    end

    def ==(other : Monster) : Bool
      @species == other.species && @x == other.x && @y == other.y &&
        @hit_points == other.hit_points && @band == other.band &&
        @attributes.to_a == other.attributes.to_a
    end

    def to_s(io : IO) : Nil
      io << "Monster(" << @species << ' ' << @x << ',' << @y
      io << ' ' << @hit_points << '/' << max_hit_points << ')'
    end
  end
end
