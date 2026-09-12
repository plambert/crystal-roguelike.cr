require "json"
require "./floor"

module Roguelike
  # Every floor of one run, and the seed that made them.
  #
  # The world keeps floors. It does not regenerate them. A player who leaves a
  # floor and comes back must find what they left there.
  #
  # A save file holds a world. The seed is here for that reason. The seed is
  # the run's identity. Every random value in the run derives from it.
  class World
    include JSON::Serializable

    # What this run started from.
    getter seed : UInt64

    # Every floor there is, by the id it keeps.
    getter floors : Hash(String, Floor)

    def initialize(@seed : UInt64, @floors : Hash(String, Floor) = {} of String => Floor)
    end

    # A world on *rng*'s seed.
    def self.on(rng : Rng) : World
      new rng.seed
    end

    # The floor called *id*. The floor has to be there.
    def [](id : String) : Floor
      @floors[id]
    end

    # :ditto: Answers `nil` when the floor is not there.
    def []?(id : String) : Floor?
      @floors[id]?
    end

    # Whether there is a floor called *id*.
    def has?(id : String) : Bool
      @floors.has_key? id
    end

    # Puts *floor* in the world under its own id. Answers *floor*.
    def add(floor : Floor) : Floor
      @floors[floor.id] = floor
    end

    # How many floors there are.
    def size : Int32
      @floors.size
    end

    def to_s(io : IO) : Nil
      io << "World(seed=" << @seed << ", " << @floors.size << " floors)"
    end
  end
end
