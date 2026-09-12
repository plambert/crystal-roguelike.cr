require "json"
require "./level"

module Roguelike
  # Every level of one run, and the seed that made them.
  #
  # The world keeps levels. It does not regenerate them. A player who leaves a
  # level and comes back must find what they left there.
  #
  # A save file holds a world. The seed is here for that reason. The seed is
  # the run's identity. Every random value in the run derives from it.
  class World
    include JSON::Serializable

    # What this run started from.
    getter seed : UInt64

    # Every level there is, by the id it keeps.
    getter levels : Hash(String, Level)

    def initialize(@seed : UInt64, @levels : Hash(String, Level) = {} of String => Level)
    end

    # A world on *rng*'s seed.
    def self.on(rng : Rng) : World
      new rng.seed
    end

    # The level called *id*. The level has to be there.
    def [](id : String) : Level
      @levels[id]
    end

    # :ditto: Answers `nil` when the level is not there.
    def []?(id : String) : Level?
      @levels[id]?
    end

    # Whether there is a level called *id*.
    def has?(id : String) : Bool
      @levels.has_key? id
    end

    # Puts *level* in the world under its own id. Answers *level*.
    def add(level : Level) : Level
      @levels[level.id] = level
    end

    # How many levels there are.
    def size : Int32
      @levels.size
    end

    def to_s(io : IO) : Nil
      io << "World(seed=" << @seed << ", " << @levels.size << " levels)"
    end
  end
end
