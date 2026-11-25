require "json"
require "../roguelike"

module Roguelike
  # Integer arithmetic for the fixed-point types.
  #
  # Every product is taken in `Int64` and every division goes through
  # `.divide`, so a result is the same on every platform. Crystal raises on
  # overflow, so a value too large for its type fails loudly.
  module FixedPoint
    # *numerator* over *denominator*, rounded half up.
    #
    # Both must be non-negative and the denominator above zero. Callers clamp
    # first.
    def self.divide(numerator : Int64, denominator : Int64) : Int64
      if numerator < 0 || denominator <= 0
        raise ArgumentError.new "cannot divide #{numerator} by #{denominator}"
      end

      (numerator * 2 + denominator) // (denominator * 2)
    end

    # :ditto:
    #
    # A negative numerator rounds its magnitude, so `-x` gives the negative
    # of what `x` gives.
    def self.divide_signed(numerator : Int64, denominator : Int64) : Int64
      return divide(numerator, denominator) if numerator >= 0

      -divide(-numerator, denominator)
    end

    # *value* in tenths, as text with one decimal place.
    #
    # *scale* is how many stored units make one tenth. Zero is written `0`.
    def self.tenths(io : IO, value : Int32, scale : Int64) : Nil
      tenths = divide_signed value.to_i64, scale
      if tenths.zero?
        io << '0'
        return
      end

      io << '-' if tenths < 0
      io << tenths.abs // 10 << '.' << tenths.abs % 10
    end
  end

  # A quantity in hundredths.
  #
  # Accuracy, to-hit, AC, DR, damage and hit points. It holds one more digit
  # than the screen shows, so a sum of several rolled stats rounds once.
  struct Fixed
    include Comparable(Fixed)

    # Stored units in one whole.
    SCALE = 100

    # Raw hundredths.
    getter value : Int32

    def initialize(@value : Int32)
    end

    ZERO = new 0

    # *whole* units.
    def self.whole(whole : Int) : Fixed
      new (whole.to_i64 * SCALE).to_i32
    end

    def self.new(pull : JSON::PullParser) : Fixed
      new pull.read_int.to_i32
    end

    def to_json(json : JSON::Builder) : Nil
      json.number @value
    end

    def <=>(other : Fixed) : Int32
      @value <=> other.value
    end

    def +(other : Fixed) : Fixed
      Fixed.new @value + other.value
    end

    def -(other : Fixed) : Fixed
      Fixed.new @value - other.value
    end

    # This quantity scaled by *other*, rounded half away from zero.
    def *(other : Ratio) : Fixed
      Fixed.new FixedPoint.divide_signed(@value.to_i64 * other.value, Ratio::SCALE).to_i32
    end

    # This quantity *other* times over.
    def *(other : Int32) : Fixed
      Fixed.new (@value.to_i64 * other).to_i32
    end

    def zero? : Bool
      @value.zero?
    end

    # The least whole number at or above this quantity.
    #
    # Hit points are shown this way, so a creature at 0.01 shows 1.
    def ceil : Int32
      ((@value.to_i64 + SCALE - 1) // SCALE).to_i32
    end

    # This quantity, or zero when it is below zero.
    def clamp_positive : Fixed
      @value < 0 ? ZERO : self
    end

    # One decimal place, rounded half up. `12.1`.
    def to_s(io : IO) : Nil
      FixedPoint.tenths io, @value, SCALE // 10
    end

    def inspect(io : IO) : Nil
      io << "Fixed(" << @value << ')'
    end
  end

  # A probability in basis points, from 0 to 10,000.
  #
  # Hit, dodge, parry, deflect, crit, lucky and penetration. A chance is rolled
  # as `rng.below(SCALE) < value`.
  struct Chance
    include Comparable(Chance)

    # Basis points in a certainty.
    SCALE = 10_000

    # The scale a stacked product is folded at.
    STACK = 1_000_000_000_i64

    # Basis points.
    getter value : Int32

    def initialize(@value : Int32)
      unless 0 <= @value <= SCALE
        raise ArgumentError.new "#{@value} is not a chance in basis points"
      end
    end

    NEVER  = new 0
    ALWAYS = new SCALE

    # *value* basis points, held to the range of a chance.
    def self.clamped(value : Int) : Chance
      new value.clamp(0, SCALE).to_i32
    end

    # *chances* added together, never above *cap*.
    def self.sum(chances : Enumerable(Chance), cap : Chance = ALWAYS) : Chance
      total = chances.sum(0_i64, &.value.to_i64)
      new Math.min(total, cap.value.to_i64).to_i32
    end

    # The chance that at least one of *chances* comes up, `1 - Π(1 - p)`.
    #
    # The product is folded at `STACK` from the smallest chance up, rounding
    # once per source. Rounding does not commute, so the order is fixed.
    def self.stack(chances : Enumerable(Chance)) : Chance
      kept = STACK
      chances.map(&.value).sort!.each do |value|
        kept = FixedPoint.divide kept * (SCALE - value), SCALE
      end

      new SCALE - FixedPoint.divide(kept, STACK // SCALE).to_i32
    end

    def self.new(pull : JSON::PullParser) : Chance
      new pull.read_int.to_i32
    end

    def to_json(json : JSON::Builder) : Nil
      json.number @value
    end

    def <=>(other : Chance) : Int32
      @value <=> other.value
    end

    # The chance that this one does not come up.
    def complement : Chance
      Chance.new SCALE - @value
    end

    def zero? : Bool
      @value.zero?
    end

    # A percentage with one decimal place, rounded half up. `51.8%`.
    def to_s(io : IO) : Nil
      FixedPoint.tenths io, @value, SCALE // 1000
      io << '%'
    end

    def inspect(io : IO) : Nil
      io << "Chance(" << @value << ')'
    end
  end

  # A multiplier or a percentage change, in basis points.
  #
  # A crit multiplier of `15_000` is ×1.5. An increase of `600` is +6%.
  struct Ratio
    include Comparable(Ratio)

    # Basis points in one.
    SCALE = 10_000

    # Basis points.
    getter value : Int32

    def initialize(@value : Int32)
    end

    ZERO = new 0
    ONE  = new SCALE

    def self.new(pull : JSON::PullParser) : Ratio
      new pull.read_int.to_i32
    end

    def to_json(json : JSON::Builder) : Nil
      json.number @value
    end

    def <=>(other : Ratio) : Int32
      @value <=> other.value
    end

    def +(other : Ratio) : Ratio
      Ratio.new @value + other.value
    end

    def -(other : Ratio) : Ratio
      Ratio.new @value - other.value
    end

    # As a multiplier with one decimal place. `×1.5`.
    def to_s(io : IO) : Nil
      io << '×'
      FixedPoint.tenths io, @value, SCALE // 10
    end

    # As a signed percentage. `+6%`, or `+6.5%` when it is not whole.
    def percent : String
      String.build do |io|
        tenths = FixedPoint.divide_signed @value.to_i64, SCALE // 1000
        io << (tenths < 0 ? '-' : '+')
        io << tenths.abs // 10
        io << '.' << tenths.abs % 10 unless (tenths % 10).zero?
        io << '%'
      end
    end

    def inspect(io : IO) : Nil
      io << "Ratio(" << @value << ')'
    end
  end
end
