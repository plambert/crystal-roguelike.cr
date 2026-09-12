require "./terrain"

module Roguelike
  # One square of a level.
  #
  # Only the terrain so far. What else a square holds — whether it is lit,
  # what is lying on it, whether a trap was set there — arrives with the phase
  # that needs it, and arrives here rather than in a parallel array, so that
  # everything about a square is in one place.
  #
  # A struct, because a level holds tens of thousands of these and they are
  # read far more often than they are changed. Changing one is
  # `Level#set`, which puts a new tile in the array.
  struct Tile
    # What the square is made of.
    getter terrain : Terrain

    def initialize(@terrain : Terrain)
    end

    # Whether something can walk onto this square.
    def passable? : Bool
      @terrain.passable?
    end

    # Whether something can see through it.
    def blocks_sight? : Bool
      @terrain.blocks_sight?
    end

    # A copy of this square made of *terrain* instead, which is what opening a
    # door is.
    def with_terrain(terrain : Terrain) : Tile
      Tile.new terrain
    end
  end
end
