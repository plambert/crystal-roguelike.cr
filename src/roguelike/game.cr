require "json"
require "./levels"
require "./player"
require "./world"

module Roguelike
  # Everything a run is. The only class that changes a run.
  #
  # A game holds the world, the character and the turn count. It opens no
  # device. It draws nothing. A spec plays a hundred turns with no widget
  # tree. A save file is one game written out.
  #
  # Every game rule lives here. `Session` reads the answer and draws it.
  # `Session` decides nothing.
  class Game
    include JSON::Serializable

    # Every level of the run, and the seed that made them.
    getter world : World

    # The character the person plays.
    getter player : Player

    # How many turns have been taken.
    #
    # A blocked step does not count. A turn gives every other creature on the
    # level one action. A blocked step gives them none.
    getter turn : Int32

    def initialize(@world : World, @player : Player, @turn : Int32 = 0)
    end

    # A new run on *rng*.
    def self.start(rng : Rng) : Game
      world = World.on rng
      level = world.add Levels.proving_ground

      new world, Player.new(level.id, *entrance(level))
    end

    # Where a character arriving on *level* stands.
    #
    # The up staircase, when the level has one. A player enters a level by a
    # staircase. Any passable square otherwise.
    def self.entrance(level : Level) : {Int32, Int32}
      found = level.find Terrain::StairsUp
      return found if found

      level.each do |column, row, tile|
        return {column, row} if tile.passable?
      end

      raise ArgumentError.new "level #{level.id} has nowhere to stand"
    end

    # The level the character is on.
    def level : Level
      @world[@player.level]
    end

    # Takes one step *direction*. Answers whether a turn happened.
    #
    # A step into an impassable square moves nothing. It counts no turn.
    def step(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return false unless level.passable? wanted[0], wanted[1]

      @player.move_to wanted
      @turn += 1
      true
    end

    # What stops a step *direction*. Answers `nil` when nothing stops it.
    def blocking(direction : Direction) : Terrain?
      wanted = direction.from @player.x, @player.y
      found = level.tile? wanted[0], wanted[1]
      return unless found
      return if found.passable?

      found.terrain
    end

    def to_s(io : IO) : Nil
      io << "Game(turn=" << @turn << ", " << @player << ')'
    end
  end
end
