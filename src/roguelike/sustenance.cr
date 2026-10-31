require "json"
require "../roguelike"

module Roguelike
  # Hunger, thirst and the waterskin, kept on the character.
  #
  # Two counters climb with the turns. `#hunger` climbs every turn and food
  # brings it down. `#thirst` climbs once the character is no longer
  # quenched, and drinking puts it back to zero.
  #
  # While the character is quenched they sip from the skin as they go, one
  # unit every `SIP` turns. When the skin runs dry, thirst starts to climb.
  # Water put back in the skin does not quench them. They have to drink it.
  #
  # One satiety point is one turn of hunger. `#eat` with 1500 points takes
  # the counter down by 1500 turns.
  #
  # Nothing here draws from a generator, so no replay stream depends on it.
  class Sustenance
    include JSON::Serializable

    # How hungry the character is, from best to worst.
    enum HungerStage
      Satiated
      Fed
      Hungry
      Famished
      Starving
    end

    # How thirsty the character is, from best to worst.
    enum ThirstStage
      Quenched
      Fine
      Thirsty
      Parched
      Dehydrated
      Dying
    end

    # What a character who wasted away died of.
    enum Death
      Hunger
      Thirst

      # What the end screen says.
      def ending : String
        case self
        in .hunger? then "You starved to death."
        in .thirst? then "You died of thirst."
        end
      end

      # What a trial report counts the death under.
      def label : String
        case self
        in .hunger? then "starvation"
        in .thirst? then "thirst"
        end
      end
    end

    # Units the skin holds.
    WATER_MAX = 10

    # Turns one unit of water lasts a quenched character.
    SIP = 300

    # Turns of hunger at which each stage starts, and at which the character
    # dies.
    FED      =  500
    HUNGRY   = 1500
    FAMISHED = 3000
    STARVING = 5000
    STARVED  = 9000

    # Turns of thirst at which each stage starts, and at which the character
    # dies.
    THIRSTY    =  500
    PARCHED    = 2000
    DEHYDRATED = 3500
    DYING      = 5000
    DRIED      = 6000

    # Turns between two hit points lost while starving.
    STARVING_EVERY = 100

    # Turns between two hit points lost while dying of thirst.
    DYING_EVERY = 50

    # Pace a character loses while dehydrated, and while starving.
    SLOWING = 10

    # Turns since the character last ate their fill.
    getter hunger : Int32 = 0

    # Turns since the character was last quenched.
    getter thirst : Int32 = 0

    # Units in the skin, from zero to `WATER_MAX`.
    getter water : Int32 = WATER_MAX

    # Turns since the last unit was sipped from the skin.
    getter sipped : Int32 = 0

    def initialize(@hunger : Int32 = 0, @thirst : Int32 = 0,
                   @water : Int32 = WATER_MAX, @sipped : Int32 = 0)
    end

    # Eats up to *points* of satiety. Answers how many were taken. Stops at
    # full.
    def eat(points : Int32) : Int32
      taken = points.clamp(0, @hunger)
      @hunger -= taken
      taken
    end

    # Drinks up to *units* from the skin. Answers how many were drunk. Stops
    # when not thirsty.
    #
    # One unit quenches the character, so no more than one is ever drunk.
    def drink(units : Int32 = 1) : Int32
      return 0 if units <= 0 || quenched? || @water.zero?

      @water -= 1
      slake
      1
    end

    # Water taken from a fountain or a potion, not from the skin. Answers
    # units used.
    def quench(units : Int32) : Int32
      return 0 if units <= 0 || quenched?

      slake
      1
    end

    # Puts *units* into the skin. Answers how many fit.
    def refill(units : Int32) : Int32
      fitted = units.clamp(0, WATER_MAX - @water)
      @water += fitted
      fitted
    end

    # Called once per turn by `Game`. Advances the counters and uses skin
    # water.
    #
    # *thirst* false holds thirst and the skin where they are for this turn,
    # for a food that makes thirst build at half rate.
    def tick(thirst : Bool = true) : Nil
      @hunger += 1
      return unless thirst

      if quenched? && @water > 0
        @sipped += 1
        return if @sipped < SIP

        @sipped = 0
        @water -= 1
        return
      end

      @thirst += 1
    end

    # How hungry the character is now.
    def hunger_stage : HungerStage
      case @hunger
      when ...FED      then HungerStage::Satiated
      when ...HUNGRY   then HungerStage::Fed
      when ...FAMISHED then HungerStage::Hungry
      when ...STARVING then HungerStage::Famished
      else                  HungerStage::Starving
      end
    end

    # How thirsty the character is now.
    def thirst_stage : ThirstStage
      case @thirst
      when 0             then ThirstStage::Quenched
      when ...THIRSTY    then ThirstStage::Fine
      when ...PARCHED    then ThirstStage::Thirsty
      when ...DEHYDRATED then ThirstStage::Parched
      when ...DYING      then ThirstStage::Dehydrated
      else                    ThirstStage::Dying
      end
    end

    # Whether the character can eat no more.
    def full? : Bool
      @hunger.zero?
    end

    # Whether the character needs no water.
    def quenched? : Bool
      @thirst.zero?
    end

    # What the character has died of, or `nil` while neither counter has
    # reached its end.
    def death : Death?
      return Death::Thirst if @thirst >= DRIED
      return Death::Hunger if @hunger >= STARVED

      nil
    end

    # Puts thirst back to nothing. The next sip from the skin is a full
    # `SIP` away.
    private def slake : Nil
      @thirst = 0
      @sipped = 0
    end
  end

  # :ditto:
  alias HungerStage = Sustenance::HungerStage

  # :ditto:
  alias ThirstStage = Sustenance::ThirstStage
end
