require "./terrain"

module Roguelike
  # One square of a level.
  #
  # A tile holds terrain and nothing else so far. Later phases add fields for
  # light, for items and for traps. Those fields go here. They do not go in a
  # second array beside this one.
  #
  # `Tile` is a struct. A level holds tens of thousands of them. A program
  # reads a tile far more often than it changes one. `Level#set` is how a
  # program changes one. It puts a new tile in the array.
  struct Tile
    # What the square is made of.
    getter terrain : Terrain

    def initialize(@terrain : Terrain)
    end

    # Whether a creature can walk onto this square.
    def passable? : Bool
      @terrain.passable?
    end

    # Whether a creature can see through this square.
    def blocks_sight? : Bool
      @terrain.blocks_sight?
    end

    # A copy of this square made of *terrain*. Opening a door uses this.
    def with_terrain(terrain : Terrain) : Tile
      Tile.new terrain
    end
  end
end
