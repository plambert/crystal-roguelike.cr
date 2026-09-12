module Roguelike
  # The one source of randomness in a run.
  #
  # Everything that needs a random number is handed one of these rather than
  # reaching for the global `Random`, because a run has to be reproducible
  # from its seed: `--seed N` twice gives the same dungeon, the same loot and
  # the same dice. A spec that cannot say what the dice did cannot assert
  # anything about combat, so this is load-bearing from the first phase rather
  # than a convenience.
  #
  # Including `Random` rather than delegating to the source means the whole
  # `Random` surface comes from one method: `#rand`, `#next_bool`, and
  # everything that takes a generator — `Array#shuffle(rng)`,
  # `Enumerable#sample(rng)` — works against one of these.
  class Rng
    include Random

    # What this generator was started from, and what reproduces it.
    #
    # Worth printing at startup and worth storing in a save file: the seed is
    # the whole of a run's randomness.
    getter seed : UInt64

    def initialize(@seed : UInt64)
      @source = ::Random::PCG32.new @seed
    end

    # A generator on *seed*, or on a fresh one from the system when *seed* is
    # `nil`, which is the shape the command line hands over.
    def self.for(seed : UInt64?) : Rng
      seed ? new(seed) : random
    end

    # A generator seeded from the system, for a run nobody asked to reproduce.
    def self.random : Rng
      new ::Random::Secure.rand(UInt64::MAX)
    end

    # The one method `Random` needs; everything else is built on it.
    def next_u : UInt32
      @source.next_u
    end

    def to_s(io : IO) : Nil
      io << "Rng(seed=" << @seed << ')'
    end
  end
end
