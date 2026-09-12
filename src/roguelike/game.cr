require "json"
require "./levels"
require "./player"
require "./world"

module Roguelike
  # Everything a run is, and the only thing that changes it.
  #
  # The model root: the world, the character, and how many turns have been
  # taken. Nothing here opens a device or draws anything, so a spec plays a
  # hundred turns with no widget tree at all — and a save file is one of these
  # written out.
  #
  # Every rule about what may happen lives on this side. `Session` reads the
  # answer and draws it; it never decides anything.
  class Game
    include JSON::Serializable

    # Every level of the run, and the seed that made them.
    getter world : World

    # The character being played.
    getter player : Player

    # How many turns have been taken. A turn that did not happen — a step into
    # a wall — does not count, because what a turn buys is the chance for
    # everything else on the level to act, and nothing acted.
    getter turn : Int32

    def initialize(@world : World, @player : Player, @turn : Int32 = 0)
    end

    # A new run on *rng*.
    #
    # The character starts on the staircase they came down by, which is where
    # a level is entered from and where a level without one puts them instead.
    def self.start(rng : Rng) : Game
      world = World.on rng
      level = world.add Levels.proving_ground

      new world, Player.new(level.id, *entrance(level))
    end

    # Where a character arriving on *level* stands.
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

    # Takes one step *direction*, answering whether a turn happened.
    #
    # A step into something that will not be walked through costs nothing: no
    # move, and no turn, so nothing else on the level gets to act because the
    # character bumping a wall is not the character doing anything.
    def step(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return false unless level.passable? wanted[0], wanted[1]

      @player.move_to wanted
      @turn += 1
      true
    end

    # What is in the way *direction*, for saying so.
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
