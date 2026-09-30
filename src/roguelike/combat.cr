require "json"
require "../roguelike"

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

    # The armor class the swing was against.
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
  # armor class. `TARGET` is the number a swing at an unarmored defender has
  # to reach. Armor class is added to it, so a better defended creature needs
  # a higher face.
  #
  # Two faces decide on their own. `CRITICAL` always lands and `FUMBLE` never
  # does. Without them a well armored creature is unhittable by a weak
  # attacker, and an unarmored one is unmissable by a strong one.
  #
  # Nothing here holds state. Every value the maths needs is an argument, so a
  # spec asserts a swing without building a game around it.
  module Combat
    # How many sides the die has.
    SIDES = 20

    # The number a swing at an unarmored defender has to reach.
    TARGET = 10

    # The face that always lands.
    CRITICAL = 20

    # The face that never lands.
    FUMBLE = 1

    # The least damage a landed swing does.
    LEAST = 1

    # What an attacker adds to its swing when the target is flanked.
    FLANKING = 2

    # The square across *target* from *attacker*.
    #
    # It is *attacker*'s square reflected through *target*'s, so a diagonal
    # neighbour's opposite is the other end of that diagonal.
    def self.opposite(attacker : {Int32, Int32},
                      target : {Int32, Int32}) : {Int32, Int32}
      {2 * target[0] - attacker[0], 2 * target[1] - attacker[1]}
    end

    # Whether an attacker at *attacker* flanks the target at *target*.
    #
    # It does when the square across the target holds another creature that
    # is fighting the same target. The block answers that for a square. The
    # rule is the same whoever the target is, so the character and a
    # monster are flanked alike.
    def self.flanks?(attacker : {Int32, Int32}, target : {Int32, Int32},
                     & : {Int32, Int32} -> Bool) : Bool
      yield opposite(attacker, target)
    end

    # What *attacker* adds to a swing at *target* for flanking it.
    def self.flanking(attacker : {Int32, Int32}, target : {Int32, Int32},
                      & : {Int32, Int32} -> Bool) : Int32
      flanks?(attacker, target) { |spot| yield spot } ? FLANKING : 0
    end

    # Whether a face of *roll* plus *bonus* lands on armor class *against*.
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
