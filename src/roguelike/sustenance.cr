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

      # What the log says as the character dies.
      def line : String
        case self
        in .hunger? then "You starve to death..."
        in .thirst? then "You die of thirst..."
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

    # Hit points the last `#tick` wasted away. The save leaves it out,
    # because `Game` reads it on the turn it was set.
    @[JSON::Field(ignore: true)]
    getter wasted : Int32 = 0

    # What the last `#tick` wasted hit points away for. `nil` when it took
    # none.
    @[JSON::Field(ignore: true)]
    getter wasted_by : Death? = nil

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
      @wasted = 0
      @wasted_by = nil
      parch if thirst

      waste Death::Hunger if hunger_stage.starving? && due?(@hunger, STARVING, STARVING_EVERY)
    end

    # One turn of thirst, or one sip from the skin.
    private def parch : Nil
      if quenched? && @water > 0
        @sipped += 1
        return if @sipped < SIP

        @sipped = 0
        @water -= 1
        return
      end

      @thirst += 1
      waste Death::Thirst if thirst_stage.dying? && due?(@thirst, DYING, DYING_EVERY)
    end

    # Whether *count* has gone a whole number of *every* turns past *start*.
    private def due?(count : Int32, start : Int32, every : Int32) : Bool
      count > start && ((count - start) % every).zero?
    end

    # Wastes one hit point away for *death*. Thirst is named first when both
    # take one on the same turn.
    private def waste(death : Death) : Nil
      @wasted += 1
      @wasted_by ||= death
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

    # The status *stage* shows, or `nil` for none.
    def self.status(stage : HungerStage) : Event::Status?
      case stage
      in .satiated?, .fed? then nil
      in .hungry?          then Event::Status::Hungry
      in .famished?        then Event::Status::Famished
      in .starving?        then Event::Status::Starving
      end
    end

    # :ditto:
    def self.status(stage : ThirstStage) : Event::Status?
      case stage
      in .quenched?, .fine? then nil
      in .thirsty?          then Event::Status::Thirsty
      in .parched?          then Event::Status::Parched
      in .dehydrated?       then Event::Status::Dehydrated
      in .dying?            then Event::Status::DyingOfThirst
      end
    end

    # The status the hunger stage shows, or `nil` for none.
    def hunger_status : Event::Status?
      Sustenance.status hunger_stage
    end

    # The status the thirst stage shows, or `nil` for none.
    def thirst_status : Event::Status?
      Sustenance.status thirst_stage
    end

    # The statuses hunger and thirst show now, hunger first.
    def statuses : Array(Event::Status)
      [hunger_status, thirst_status].compact
    end

    # Whether natural regeneration takes twice as long.
    #
    # Each ladder's later stage takes the place of its earlier one, so only
    # the first stage of each slows it.
    def slow_regeneration? : Bool
      hunger_stage.hungry? || thirst_stage.thirsty?
    end

    # Whether natural regeneration runs at all. It stops while the character
    # wastes away.
    def regenerates? : Bool
      !hunger_stage.starving? && !thirst_stage.dying?
    end

    # What hunger and thirst take off every roll to hit.
    def to_hit_penalty : Int32
      found = 0
      found += 1 if hunger_stage.famished?
      found += 1 if thirst_stage.parched?
      found
    end

    # What hunger takes off melee and thrown damage.
    def damage_penalty : Int32
      hunger_stage.famished? ? 1 : 0
    end

    # What hunger and thirst take off pace.
    def slowing : Int32
      found = 0
      found += SLOWING if hunger_stage.starving?
      found += SLOWING if thirst_stage.dehydrated?
      found
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
