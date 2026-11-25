require "../roguelike"

module Roguelike
  # How a roll falls inside a `Span`.
  #
  # Every spread is symmetric, so the mean of a span is its midpoint whatever
  # the spread.
  enum Spread
    # One draw, flat across the span.
    Even

    # `(3a + b) / 4` over two draws. Flat across the middle half, tapering at
    # both ends.
    Steady

    # `(a + b) / 2` over two draws. A triangle peaked at the midpoint.
    Centered

    # A draw in `0..Span::STEPS`, shaped by this spread.
    def draw(rng : Rng) : Int64
      case self
      in .even?
        rng.below(Span::STEPS + 1).to_i64
      in .steady?
        first = rng.below(Span::STEPS + 1).to_i64
        second = rng.below(Span::STEPS + 1).to_i64
        FixedPoint.divide first * 3 + second, 4_i64
      in .centered?
        first = rng.below(Span::STEPS + 1).to_i64
        second = rng.below(Span::STEPS + 1).to_i64
        FixedPoint.divide first + second, 2_i64
      end
    end
  end

  # A range of damage or hit points, with a spread. The interface shows
  # `3.0–7.0`.
  struct Span
    # The largest spread draw.
    STEPS = 65_535

    getter low : Fixed
    getter high : Fixed
    getter spread : Spread

    def initialize(@low : Fixed, @high : Fixed, @spread : Spread = Spread::Steady)
      if @low.value < 0 || @high < @low
        raise ArgumentError.new "#{@low.value}..#{@high.value} is not a span"
      end
    end

    # A span from *low* to *high* whole units.
    def self.whole(low : Int, high : Int, spread : Spread = Spread::Steady) : Span
      new Fixed.whole(low), Fixed.whole(high), spread
    end

    # A roll inside the span, `low + (high - low) × u / STEPS`.
    def roll(rng : Rng) : Fixed
      width = (@high - @low).value.to_i64
      Fixed.new (@low.value + FixedPoint.divide(width * @spread.draw(rng), STEPS.to_i64)).to_i32
    end

    # The midpoint, which is the mean of every spread.
    def mean : Fixed
      Fixed.new FixedPoint.divide(@low.value.to_i64 + @high.value, 2_i64).to_i32
    end

    def to_s(io : IO) : Nil
      io << @low << '–' << @high
    end
  end
end
