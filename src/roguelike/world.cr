require "json"
require "./level"

module Roguelike
  # Every level of one run, and the seed that made it.
  #
  # Levels are kept rather than regenerated, because leaving one and coming
  # back to it has to find what was left there. The world is what a save file
  # holds, which is why the seed is here: it is the run's identity, and
  # everything random in the run is derived from it.
  class World
    include JSON::Serializable

    # What this run was started from.
    getter seed : UInt64

    # Every level there is, by the name it keeps.
    getter levels : Hash(String, Level)

    def initialize(@seed : UInt64, @levels : Hash(String, Level) = {} of String => Level)
    end

    # A world on *rng*'s seed.
    def self.on(rng : Rng) : World
      new rng.seed
    end

    # The level called *id*, which has to be there.
    def [](id : String) : Level
      @levels[id]
    end

    # :ditto:, answering `nil` when it is not.
    def []?(id : String) : Level?
      @levels[id]?
    end

    # Whether there is a level called *id*.
    def has?(id : String) : Bool
      @levels.has_key? id
    end

    # Puts *level* in the world under its own id, answering it.
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
