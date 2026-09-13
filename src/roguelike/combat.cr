require "json"
require "./dice"
require "./rng"

module Roguelike
  # What one swing did.
  #
  # A blow is the record of a roll. It changes nobody. `Game` reads one and
  # takes the hit points off. A spec reads one and asserts the maths.
  struct Blow
    include JSON::Serializable

    # The face the die came up.
    getter roll : Int32

    # What the attacker added to the face.
    getter bonus : Int32

    # The armour class the swing was against.
    getter against : Int32

    # Whether it landed.
    getter? hit : Bool

    # Hit points taken off. Zero on a miss.
    getter damage : Int32

    def initialize(@roll : Int32, @bonus : Int32, @against : Int32,
                   @hit : Bool, @damage : Int32)
    end

    # The face and the bonus together.
    def total : Int32
      @roll + @bonus
    end

    # Whether the die came up on the face that always lands.
    def critical? : Bool
      @roll >= Combat::CRITICAL
    end

    # Whether it came up on the face that never lands.
    def fumble? : Bool
      @roll <= Combat::FUMBLE
    end

    def to_s(io : IO) : Nil
      io << "Blow(d" << Combat::SIDES << ' ' << @roll
      io << '+' << @bonus if @bonus > 0
      io << @bonus if @bonus < 0
      io << " vs " << @against << ' '
      io << (@hit ? "hit #{@damage}" : "miss")
      io << ')'
    end
  end

  # How a swing is decided.
  #
  # One twenty sided die, plus what the attacker adds, against the defender's
  # armour class. `TARGET` is the number a swing at an unarmoured defender has
  # to reach. Armour class is added to it, so a better defended creature needs
  # a higher face.
  #
  # Two faces decide on their own. `CRITICAL` always lands and `FUMBLE` never
  # does. Without them a well armoured creature is unhittable by a weak
  # attacker, and an unarmoured one is unmissable by a strong one.
  #
  # Nothing here holds state. Every value the maths needs is an argument, so a
  # spec asserts a swing without building a game around it.
  module Combat
    # How many sides the die has.
    SIDES = 20

    # The number a swing at an unarmoured defender has to reach.
    TARGET = 10

    # The face that always lands.
    CRITICAL = 20

    # The face that never lands.
    FUMBLE = 1

    # The least damage a landed swing does.
    LEAST = 1

    # Whether a face of *roll* plus *bonus* lands on armour class *against*.
    def self.lands?(roll : Int32, bonus : Int32, against : Int32) : Bool
      return true if roll >= CRITICAL
      return false if roll <= FUMBLE

      roll + bonus >= TARGET + against
    end

    # One swing, rolled on *rng*.
    #
    # The face is rolled first and the damage second. A miss rolls no damage,
    # so a miss and a hit draw a different count of values. Each swing is
    # given a generator of its own, so that difference shifts nothing after
    # it.
    def self.swing(rng : Rng, bonus : Int32, against : Int32,
                   damage : Dice) : Blow
      roll = rng.rand 1..SIDES
      return Blow.new roll, bonus, against, false, 0 unless lands? roll, bonus, against

      Blow.new roll, bonus, against, true, Math.max(damage.roll(rng), LEAST)
    end
  end
end
