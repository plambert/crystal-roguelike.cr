module Roguelike
  # A generator for one part of one run.
  #
  # A run has one seed, and every generator in it comes from that seed — but
  # not from one sequence. Drawing everything from a single stream makes a run
  # *deterministic* without making it *stable*: adding one `rand` to level
  # generation shifts every roll after it, so the same seed gives a different
  # game in the next build and a bug report with a seed in it stops
  # reproducing. Worse, it cannot survive the two things this game is being
  # built for — levels visited in whatever order the player chooses, and
  # monster planning in a parallel execution context, where the interleaving
  # between threads is not the same twice.
  #
  # So the seed names the run and a *stream* names the part of it. PCG32
  # carries a stream selector beside the seed and guarantees the sequences are
  # independent, and `#derive` picks one from a name:
  #
  #     master = Rng.for options.seed
  #     level  = master.derive "worldgen", level_id
  #     band   = master.derive "ai", band_id
  #
  # `#derive` reads nothing from the generator it is called on — it is a
  # function of the seed, the parent's stream and the name. Level 7 is
  # generated identically whether or not level 3 was generated first, whether
  # or not it was generated at all, and however many rolls anything else has
  # made. That is the property worth having.
  #
  # A derived generator belongs to one fiber. Derive one per band, per level,
  # per anything that might plan in parallel, and never share a leaf.
  #
  # NOTE: a domain name is part of the seed contract. Renaming one changes
  # every seed that reaches it, the same as changing the seed.
  class Rng
    include Random

    # The stream a generator nobody derived draws from.
    ROOT_STREAM = 0_u64

    # What this run was started from, and what reproduces it.
    #
    # Every generator derived from this one carries the same value, because
    # they are all the same run. `#stream` is what separates them.
    getter seed : UInt64

    # Which of the seed's independent sequences this generator draws from.
    getter stream : UInt64

    def initialize(@seed : UInt64, @stream : UInt64 = ROOT_STREAM)
      @source = ::Random::PCG32.new @seed, @stream
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

    # The generator for *domain*, derived from this one.
    #
    # Deriving the same name twice answers two generators drawing the same
    # sequence, so a caller holds the one it derived rather than deriving
    # again per draw.
    def derive(domain : String) : Rng
      Rng.new @seed, Rng.stream_for(@stream, domain)
    end

    # :ditto:
    #
    # *id* names which one — which level, which band, which room — and has to
    # be the thing's own stable identity rather than a count of how many have
    # been made, or the order they are made in comes back as a dependency.
    def derive(domain : String, id : Int) : Rng
      derive "#{domain}:#{id}"
    end

    # The one method `Random` needs; everything else is built on it.
    def next_u : UInt32
      @source.next_u
    end

    def to_s(io : IO) : Nil
      io << "Rng(seed=" << @seed << ", stream=" << @stream << ')'
    end

    # The stream *domain* names under *parent*.
    #
    # FNV-1a over the name, mixed into the parent's stream with splitmix64.
    # It is written out here rather than reaching for `String#hash` because
    # Crystal seeds its hasher randomly per process, so `"level:3".hash` is a
    # different number in every run — which is the one thing a seed derivation
    # must not be. Mixing the parent in makes the derivation path-dependent,
    # so `a.derive("x").derive("y")` is not `a.derive("y").derive("x")`.
    protected def self.stream_for(parent : UInt64, domain : String) : UInt64
      hash = 0xcbf29ce484222325_u64

      domain.each_byte do |byte|
        hash ^= byte
        hash &*= 0x100000001b3_u64
      end

      mix parent ^ hash
    end

    # splitmix64's finalizer, which avalanches a counter into a usable seed.
    protected def self.mix(value : UInt64) : UInt64
      value &+= 0x9e3779b97f4a7c15_u64
      value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9_u64
      value = (value ^ (value >> 27)) &* 0x94d049bb133111eb_u64
      value ^ (value >> 31)
    end
  end
end
