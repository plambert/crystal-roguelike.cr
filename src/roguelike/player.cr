require "json"
require "./advancement"
require "./attributes"
require "./inventory"

module Roguelike
  # The character the person plays.
  #
  # The word "level" means two things in a roguelike. `#floor` is which level
  # of the world the character stands on. `#level` is how far the character
  # has advanced. They are named apart here so that neither reading has to be
  # guessed.
  #
  # The floor is held by its id rather than by a reference to the `Level`.
  # Levels persist and a save file stores them. A save file that stored the
  # floor twice would hold one copy in the world and one under the player. The
  # two copies would then need to stay in step.
  class Player
    include JSON::Serializable

    # Which level of the world the character stands on.
    property floor : String

    # The column the character stands in.
    getter x : Int32

    # The row the character stands in.
    getter y : Int32

    # What the character is made of.
    property attributes : Attributes

    # How far the character has advanced. It starts at one.
    getter level : Int32

    # Experience points. `Advancement` turns them into a level.
    getter experience : Int32

    # Hit points left. The character dies at zero.
    getter hit_points : Int32

    # What the character carries.
    getter inventory : Inventory

    # Gold pieces. Counted rather than carried, so they take no letter.
    getter gold : Int32

    def initialize(@floor : String, @x : Int32, @y : Int32,
                   @attributes : Attributes = Attributes.new,
                   @level : Int32 = 1,
                   @experience : Int32 = 0,
                   hit_points : Int32? = nil,
                   @inventory : Inventory = Inventory.new,
                   @gold : Int32 = 0)
      @hit_points = hit_points || Advancement.max_hit_points(@level, @attributes.constitution)
    end

    # Adds *amount* gold pieces. Answers the new total.
    def take_gold(amount : Int32) : Int32
      @gold += Math.max amount, 0
    end

    # Takes *amount* gold pieces away, no further than nothing. Answers how
    # many were taken.
    def spend_gold(amount : Int32) : Int32
      spent = Math.min Math.max(amount, 0), @gold
      @gold -= spent
      spent
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

    # Hit points at full health.
    def max_hit_points : Int32
      Advancement.max_hit_points @level, @attributes.constitution
    end

    # Whether the character is still alive.
    def alive? : Bool
      @hit_points > 0
    end

    # Experience still needed to reach the next level. `nil` at the last one.
    def to_next_level : Int32?
      Advancement.to_next @experience
    end

    # Takes *amount* off the hit points. Answers how many are left.
    def hurt(amount : Int32) : Int32
      @hit_points = Math.max @hit_points - amount, 0
    end

    # Puts *amount* back, up to full health. Answers how many were restored.
    def heal(amount : Int32) : Int32
      before = @hit_points
      @hit_points = Math.min @hit_points + amount, max_hit_points
      @hit_points - before
    end

    # Adds *amount* experience. Answers how many levels that gained.
    #
    # A level gained raises the maximum hit points. The current hit points go
    # up by the same number. A character who levels up mid fight is better off
    # than before, and is not suddenly at full health either.
    def gain(amount : Int32) : Int32
      return 0 if amount <= 0

      @experience += amount
      wanted = Advancement.level_for @experience
      return 0 if wanted <= @level

      before = max_hit_points
      gained = wanted - @level
      @level = wanted
      @hit_points += max_hit_points - before

      gained
    end

    def to_s(io : IO) : Nil
      io << "Player(" << @floor << ' ' << @x << ',' << @y
      io << " L" << @level << ' ' << @hit_points << '/' << max_hit_points << ')'
    end
  end
end
