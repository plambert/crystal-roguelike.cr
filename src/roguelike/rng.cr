module Roguelike
  # A generator for one part of one run.
  #
  # A run has one seed. `--seed N` reproduces the run exactly. That is what
  # makes every later phase testable.
  #
  # A run does not have one sequence. One shared sequence makes a run
  # deterministic. It does not make a run stable. Adding one `rand` call to
  # level generation shifts every roll after it. The same seed then gives a
  # different game in the next build. A bug report with a seed in it stops
  # reproducing.
  #
  # One shared sequence also cannot survive two things this game is built for.
  # The player visits levels in whatever order they choose. Monster planning
  # runs in a parallel execution context. Threads interleave differently on
  # every run.
  #
  # So the seed names the run. A stream names the part of the run. PCG32
  # carries a stream selector beside the seed. Sequences from different
  # streams are independent. `#derive` picks a stream from a name:
  #
  #     master = Rng.for options.seed
  #     level  = master.derive "worldgen", level_id
  #     band   = master.derive "ai", band_id
  #
  # `#derive` reads nothing from the generator it is called on. It is a
  # function of the seed, the parent stream and the name. Level 7 generates
  # identically whether or not level 3 generated first. It generates
  # identically whether or not level 3 generated at all. It generates
  # identically after any number of rolls elsewhere.
  #
  # One derived generator belongs to one fiber. Derive one per band. Derive
  # one per level. Derive one per anything that might plan in parallel. Never
  # share a leaf generator between fibers.
  #
  # NOTE: a domain name is part of the seed contract. Renaming one changes
  # every seed that reaches it. That is the same effect as changing the seed.
  class Rng
    include Random

    # The stream a generator draws from when nobody derived it.
    ROOT_STREAM = 0_u64

    # What this run started from. `--seed` reproduces the run from it.
    #
    # Every generator derived from this one carries the same value. They are
    # all the same run. `#stream` separates them.
    getter seed : UInt64

    # Which of the seed's independent sequences this generator draws from.
    getter stream : UInt64

    def initialize(@seed : UInt64, @stream : UInt64 = ROOT_STREAM)
      @source = ::Random::PCG32.new @seed, @stream
    end

    # A generator on *seed*. A fresh seed from the system when *seed* is
    # `nil`. The command line passes that shape.
    def self.for(seed : UInt64?) : Rng
      seed ? new(seed) : random
    end

    # A generator seeded from the system. For a run nobody asked to reproduce.
    def self.random : Rng
      new ::Random::Secure.rand(UInt64::MAX)
    end

    # The generator for *domain*, derived from this one.
    #
    # Deriving the same name twice answers two generators. Both draw the same
    # sequence. So a caller holds the generator it derived. It does not derive
    # again for each draw.
    def derive(domain : String) : Rng
      Rng.new @seed, Rng.stream_for(@stream, domain)
    end

    # :ditto:
    #
    # *id* names which one. Which level. Which band. Which room. It has to be
    # the thing's own stable identity. A count of how many exist would bring
    # back the order dependency this design removes.
    def derive(domain : String, id : Int) : Rng
      derive "#{domain}:#{id}"
    end

    # The one method `Random` needs. Every other method builds on it.
    def next_u : UInt32
      @source.next_u
    end

    def to_s(io : IO) : Nil
      io << "Rng(seed=" << @seed << ", stream=" << @stream << ')'
    end

    # The stream *domain* names under *parent*.
    #
    # FNV-1a hashes the name. splitmix64 mixes the hash into the parent
    # stream.
    #
    # This code does not call `String#hash`. Crystal seeds its hasher randomly
    # in each process. `"level:3".hash` is a different number in every run. A
    # seed derivation must give the same number in every run.
    #
    # Mixing the parent stream in makes derivation path dependent.
    # `a.derive("x").derive("y")` differs from `a.derive("y").derive("x")`.
    protected def self.stream_for(parent : UInt64, domain : String) : UInt64
      hash = 0xcbf29ce484222325_u64

      domain.each_byte do |byte|
        hash ^= byte
        hash &*= 0x100000001b3_u64
      end

      mix parent ^ hash
    end

    # splitmix64's finalizer. It spreads the bits of a counter into a usable
    # seed.
    protected def self.mix(value : UInt64) : UInt64
      value &+= 0x9e3779b97f4a7c15_u64
      value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9_u64
      value = (value ^ (value >> 27)) &* 0x94d049bb133111eb_u64
      value ^ (value >> 31)
    end
  end
end
