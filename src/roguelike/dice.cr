require "json"

module Roguelike
  # A number of dice, their sides, and a flat bonus.
  #
  # `1d6`, `2d4+1`, `1d8-2`. A weapon carries one. A spell will carry one.
  # Rolling takes an `Rng`, so a run reproduces from its seed.
  struct Dice
    include JSON::Serializable

    # How many dice are thrown.
    getter count : Int32

    # How many sides each one has.
    getter sides : Int32

    # What is added to the total after they are thrown.
    getter bonus : Int32

    def initialize(@count : Int32, @sides : Int32, @bonus : Int32 = 0)
      raise ArgumentError.new "#{self} throws no dice" if @count < 0
      raise ArgumentError.new "#{self} has a die with no sides" if @sides < 1
    end

    # No dice and no bonus. A creature with no weapon does this much.
    NONE = Dice.new 0, 1, 0

    # Reads `2d6+1`, `1d8`, `1d8-2` and `3` into dice.
    def self.parse(text : String) : Dice
      match = /\A(?:(\d+)d(\d+))?([+-]\d+)?\z/.match text.strip
      raise ArgumentError.new "#{text.inspect} is not dice" unless match

      count = match[1]?.try &.to_i
      sides = match[2]?.try &.to_i
      bonus = match[3]?.try &.to_i || 0
      raise ArgumentError.new "#{text.inspect} is not dice" if count.nil? && bonus.zero?

      new count || 0, sides || 1, bonus
    end

    # Throws the dice on *rng*.
    def roll(rng : Rng) : Int32
      total = @bonus
      @count.times { total += rng.rand(1..@sides) }
      total
    end

    # The lowest total a throw gives.
    def minimum : Int32
      @count + @bonus
    end

    # The highest.
    def maximum : Int32
      @count * @sides + @bonus
    end

    # The mean of every throw.
    def average : Float64
      @count * (@sides + 1) / 2.0 + @bonus
    end

    # A copy with *amount* added to the bonus.
    def with_bonus(amount : Int32) : Dice
      Dice.new @count, @sides, @bonus + amount
    end

    # Whether a throw can only give nothing.
    def none? : Bool
      @count.zero? && @bonus.zero?
    end

    def to_s(io : IO) : Nil
      io << @count << 'd' << @sides if @count > 0
      io << '+' if @bonus > 0
      io << @bonus if @bonus != 0
      io << '0' if @count.zero? && @bonus.zero?
    end
  end
end
