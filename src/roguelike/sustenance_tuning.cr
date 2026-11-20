require "../roguelike"

module Roguelike
  class Sustenance
    # Every number hunger, thirst, water, fountains and the pantry are tuned
    # by. Each has one definition here, and the code reads it from here.
    #
    # Debts and times are in turns. One turn is ten seconds, so 360 turns is
    # an hour.
    module Tuning
      # ------------------------------------------------------------ hunger

      HUNGER_FIRST   =   2_160 # 6h. The first effect, as the fed stage.
      HUNGER_HUNGRY  =   4_320 # 12h. The hungry stage.
      HUNGER_SERIOUS =   8_640 # 24h. The famished stage.
      HUNGER_SEVERE  =  21_600 # 60h. The starving stage. A corpse can be eaten where it lies.
      HUNGER_DEATH   = 362_880 # 6 weeks. Death by starvation.

      # ------------------------------------------------------------ thirst

      THIRST_FIRST   =  2_520 # 7h. The first effect, as the thirsty stage.
      THIRST_SERIOUS =  8_640 # 24h. The parched stage.
      THIRST_SEVERE  = 17_280 # 48h. The dehydrated stage.
      THIRST_DEATH   = 25_920 # 72h. Death by thirst.

      # ---------------------------------------------------------- severity

      # Hunger severity at each debt. Zero below the first point, a straight
      # line between points, then the climb to 1.0 at `HUNGER_DEATH`.
      HUNGER_SEVERITY = [
        {HUNGER_FIRST, 0.0},
        {HUNGER_HUNGRY, 0.15},
        {HUNGER_SERIOUS, 0.35},
        {HUNGER_SEVERE, 0.6},
      ]

      # Thirst severity at each debt. Zero below the first point, then as
      # for hunger, to 1.0 at `THIRST_DEATH`.
      THIRST_SEVERITY = [
        {THIRST_FIRST, 0.1},
        {THIRST_SERIOUS, 0.35},
        {THIRST_SEVERE, 0.65},
      ]

      CLIMB = 2 # Power of the share of the way from the last point to death.

      # ----------------------------------------------------------- effects

      PACE_LOSS     =  60 # Pace lost at severity 1, out of a normal 100.
      TO_HIT_LOSS   =   4 # To-hit lost at severity 1, on top of what dexterity loses.
      DAMAGE_LOSS   =   3 # Melee and thrown damage lost at severity 1, on top of strength.
      REGEN_SLOWING =   4 # Regeneration takes 1 + this times severity as long.
      WASTING       = 0.9 # Severity at which regeneration stops and hit points waste away.
      WASTE_FIRST   = 100 # Turns between two hit points lost at `WASTING`.
      WASTE_LAST    =  10 # Turns between two hit points lost at severity 1.

      # Every attribute falls toward `Attributes::MINIMUM` in step with
      # severity, and reaches it at severity 1.

      # ------------------------------------------------------------- water

      SKIN_UNITS        =   20 # Units the waterskin holds.
      UNIT_TURNS        =  450 # Turns of thirst debt one unit pays.
      POTION_QUENCH     =  100 # Turns of thirst debt any potion pays.
      MEAT_FRESH_WATER  =   90 # Turns of thirst debt a piece of fresh meat pays.
      MEAT_STALE_WATER  =    0 # Turns of thirst debt a piece of stale meat pays.
      MEAT_ROTTEN_WATER = -180 # Turns of thirst debt a piece of rotten meat adds.

      # ---------------------------------------------------------- fountains

      # By depth: the chance of a fountain out of a hundred, and the dry
      # floors in a row directly above after which one is certain. `nil`
      # is no certainty. Floor 1 always has one.
      FOUNTAINS = {
        2..4  => {75, 3},
        5..7  => {25, nil},
        8..10 => {45, 4},
      } of Range(Int32, Int32) => {Int32, Int32?}

      # ------------------------------------------------------------ pantry

      # By depth: food items per 100,000 squares of open floor. Every floor
      # holds one at least.
      PANTRY = {
        1..3  => 105,
        4..7  => 10,
        8..10 => 40,
      } of Range(Int32, Int32) => Int32
    end
  end
end
