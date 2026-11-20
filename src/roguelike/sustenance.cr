require "json"
require "../roguelike"

module Roguelike
  # Hunger, thirst and the waterskin, kept on the character.
  #
  # Hunger and thirst are debts, counted in turns. Each climbs by one every
  # turn. Eating pays hunger debt down, and drinking pays thirst debt down.
  # Neither goes below zero. One satiety point pays one turn of hunger.
  #
  # Each debt has a severity from 0 to 1, read off the points in `Tuning`.
  # The two add, up to 1, and every effect reads the sum.
  #
  # The waterskin holds `Tuning::SKIN_UNITS` units. The character drinks
  # from it only when they choose to.
  #
  # Every number is in `Tuning`. Nothing here draws from a generator, so no
  # replay stream depends on it.
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

    # Seconds of game time in one turn. Every time shown to the player is
    # counted from this.
    SECONDS_PER_TURN = 10

    # The thirst debt at which thirst alone would waste the character away.
    # The dying stage starts here.
    THIRST_DYING = (Tuning::THIRST_SEVERE..Tuning::THIRST_DEATH).bsearch do |debt|
      Sustenance.thirst_severity(debt) >= Tuning::WASTING
    end || Tuning::THIRST_DEATH

    # *turns* as the player sees them. The game time is rounded down to ten
    # minutes and written as "50m", "4h10m" or "1h". Anything under ten
    # minutes is "<10m".
    #
    # The player never learns the exact turn a change comes on.
    def self.approximate(turns : Int32) : String
      minutes = Math.max(turns, 0).to_i64 * SECONDS_PER_TURN // 60
      steps = minutes // 10 * 10
      return "<10m" if steps.zero?

      hours, left = steps.divmod 60
      return "#{left}m" if hours.zero?
      return "#{hours}h" if left.zero?

      "#{hours}h#{left}m"
    end

    # *turns* as `.approximate` writes them, but in whole hours from ten
    # hours up, as "20h". A budget line uses it, so the longest line fits
    # the narrow panel.
    def self.rough(turns : Int32) : String
      hours = Math.max(turns, 0).to_i64 * SECONDS_PER_TURN // 3600
      hours >= 10 ? "#{hours}h" : approximate(turns)
    end

    # The severity of *debt* on a ladder of *points* that ends at *death*.
    #
    # Zero below the first point. A straight line from each point to the
    # next. From the last point it climbs as the `Tuning::CLIMB` power of the
    # share of the way to *death*, and is 1 there and past it.
    def self.severity(debt : Int32, points : Array({Int32, Float64}), death : Int32) : Float64
      return 0.0 if debt < points.first[0]
      return 1.0 if debt >= death

      points.each_cons_pair do |(low, from), (high, to)|
        return from + (to - from) * (debt - low) / (high - low) if debt < high
      end

      last, from = points.last
      share = (debt - last) / (death - last)
      from + (1.0 - from) * share ** Tuning::CLIMB
    end

    # The severity of *debt* turns of hunger.
    def self.hunger_severity(debt : Int32) : Float64
      severity debt, Tuning::HUNGER_SEVERITY, Tuning::HUNGER_DEATH
    end

    # The severity of *debt* turns of thirst.
    def self.thirst_severity(debt : Int32) : Float64
      severity debt, Tuning::THIRST_SEVERITY, Tuning::THIRST_DEATH
    end

    # Turns of hunger debt.
    @[JSON::Field(key: "hunger_debt")]
    getter hunger : Int32 = 0

    # Turns of thirst debt.
    @[JSON::Field(key: "thirst_debt")]
    getter thirst : Int32 = 0

    # Units in the skin, from zero to `Tuning::SKIN_UNITS`.
    @[JSON::Field(key: "skin")]
    getter water : Int32 = Tuning::SKIN_UNITS

    # The counters a save from before the debts holds. `#after_initialize`
    # turns them into debts, and they are never written.
    @[JSON::Field(key: "hunger", ignore_serialize: true)]
    @old_hunger : Int32? = nil
    @[JSON::Field(key: "thirst", ignore_serialize: true)]
    @old_thirst : Int32? = nil
    @[JSON::Field(key: "water", ignore_serialize: true)]
    @old_water : Int32? = nil

    # Thousandths of a hit point worn away toward the next one wasted.
    # `nil` stands for none, so a character who is not wasting away writes
    # no field.
    @wear : Int32? = nil

    # Hit points the last `#tick` wasted away. The save leaves it out,
    # because `Game` reads it on the turn it was set.
    @[JSON::Field(ignore: true)]
    getter wasted : Int32 = 0

    # What the last `#tick` wasted hit points away for. `nil` when it took
    # none.
    @[JSON::Field(ignore: true)]
    getter wasted_by : Death? = nil

    def initialize(@hunger : Int32 = 0, @thirst : Int32 = 0,
                   @water : Int32 = Tuning::SKIN_UNITS)
    end

    # Turns the counters of a save from before the debts into debts.
    #
    # Hunger carries over as it was. A skin that held water becomes a full
    # skin and no thirst debt. A dry skin stays dry, and the thirst count
    # becomes the debt.
    protected def after_initialize : Nil
      return unless @old_hunger || @old_thirst || @old_water

      @hunger = @old_hunger || 0
      if (@old_water || 1) > 0
        @thirst = 0
        @water = Tuning::SKIN_UNITS
      else
        @thirst = @old_thirst || 0
        @water = 0
      end
      @old_hunger = @old_thirst = @old_water = nil
    end

    # Eats up to *points* of satiety. Answers how many were taken. Stops at
    # full.
    def eat(points : Int32) : Int32
      taken = points.clamp(0, @hunger)
      @hunger -= taken
      taken
    end

    # Drinks one unit from the skin, which pays `Tuning::UNIT_TURNS` of
    # thirst debt. Answers the units drunk.
    #
    # Nothing is drunk while there is no thirst debt or the skin is empty.
    def drink : Int32
      return 0 if quenched? || @water.zero?

      @water -= 1
      quench Tuning::UNIT_TURNS
      1
    end

    # Pays up to *turns* of thirst debt. Answers how many were paid.
    def quench(turns : Int32) : Int32
      paid = turns.clamp(0, @thirst)
      @thirst -= paid
      paid
    end

    # Pays all the thirst debt, as a fountain does. Answers how many turns
    # were paid.
    def slake : Int32
      quench @thirst
    end

    # Adds *turns* of thirst debt.
    def parch(turns : Int32) : Nil
      @thirst += Math.max turns, 0
    end

    # Puts *units* into the skin. Answers how many fit.
    def refill(units : Int32) : Int32
      fitted = units.clamp(0, Tuning::SKIN_UNITS - @water)
      @water += fitted
      fitted
    end

    # Called once per turn by `Game`. Climbs both debts and wastes hit
    # points away once severity passes `Tuning::WASTING`.
    #
    # *thirst* false holds thirst where it is for this turn, for a food that
    # makes thirst build at half rate.
    def tick(thirst : Bool = true) : Nil
      @hunger += 1
      @thirst += 1 if thirst
      @wasted = 0
      @wasted_by = nil

      every = waste_every
      unless every
        @wear = nil
        return
      end

      worn = (@wear || 0) + WORN // every
      @wasted, left = worn.divmod WORN
      @wear = left.zero? ? nil : left
      @wasted_by = thirst_severity >= hunger_severity ? Death::Thirst : Death::Hunger if @wasted > 0
    end

    # What `@wear` counts to before a hit point is wasted away.
    WORN = 1000

    # Turns between two hit points wasted away, or `nil` while severity is
    # short of `Tuning::WASTING`. It falls in a straight line from
    # `Tuning::WASTE_FIRST` there to `Tuning::WASTE_LAST` at severity 1.
    def waste_every : Int32?
      found = severity
      return if found < Tuning::WASTING

      share = (found - Tuning::WASTING) / (1.0 - Tuning::WASTING)
      span = Tuning::WASTE_FIRST - Tuning::WASTE_LAST
      Math.max (Tuning::WASTE_FIRST - span * share).round.to_i, 1
    end

    # How severe the hunger debt is, from 0 to 1.
    def hunger_severity : Float64
      Sustenance.hunger_severity @hunger
    end

    # How severe the thirst debt is, from 0 to 1.
    def thirst_severity : Float64
      Sustenance.thirst_severity @thirst
    end

    # Hunger and thirst severity together, no more than 1. Every effect
    # reads this.
    def severity : Float64
      Math.min hunger_severity + thirst_severity, 1.0
    end

    # How hungry the character is now.
    def hunger_stage : HungerStage
      case @hunger
      when ...Tuning::HUNGER_FIRST   then HungerStage::Satiated
      when ...Tuning::HUNGER_HUNGRY  then HungerStage::Fed
      when ...Tuning::HUNGER_SERIOUS then HungerStage::Hungry
      when ...Tuning::HUNGER_SEVERE  then HungerStage::Famished
      else                                HungerStage::Starving
      end
    end

    # How thirsty the character is now. Quenched is less than one unit's
    # worth of debt, and fine is a unit or more short of thirsty.
    def thirst_stage : ThirstStage
      case @thirst
      when ...Tuning::UNIT_TURNS     then ThirstStage::Quenched
      when ...Tuning::THIRST_FIRST   then ThirstStage::Fine
      when ...Tuning::THIRST_SERIOUS then ThirstStage::Thirsty
      when ...Tuning::THIRST_SEVERE  then ThirstStage::Parched
      when ...THIRST_DYING           then ThirstStage::Dehydrated
      else                                ThirstStage::Dying
      end
    end

    # Turns until hunger reaches its next stage. At starving, turns until
    # the character starves to death.
    def food_left : Int32
      ahead = case hunger_stage
              in .satiated? then Tuning::HUNGER_FIRST
              in .fed?      then Tuning::HUNGER_HUNGRY
              in .hungry?   then Tuning::HUNGER_SERIOUS
              in .famished? then Tuning::HUNGER_SEVERE
              in .starving? then Tuning::HUNGER_DEATH
              end
      Math.max ahead - @hunger, 0
    end

    # Turns until thirst reaches its next stage that shows a status. At
    # dying, turns until the character dies of thirst.
    def water_left : Int32
      ahead = case thirst_stage
              in .quenched?, .fine? then Tuning::THIRST_FIRST
              in .thirsty?          then Tuning::THIRST_SERIOUS
              in .parched?          then Tuning::THIRST_SEVERE
              in .dehydrated?       then THIRST_DYING
              in .dying?            then Tuning::THIRST_DEATH
              end
      Math.max ahead - @thirst, 0
    end

    # Whether a drink from the skin now pays a whole unit's worth of debt
    # and keeps the character short of the thirsty stage. An explore drinks
    # when this is true.
    def drink_due? : Bool
      @thirst >= Tuning::UNIT_TURNS &&
        @thirst + Tuning::UNIT_TURNS > Tuning::THIRST_FIRST
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

    # How many times as long natural regeneration takes.
    def regeneration_factor : Float64
      1.0 + Tuning::REGEN_SLOWING * severity
    end

    # Whether natural regeneration runs at all. It stops while the character
    # wastes away.
    def regenerates? : Bool
      severity < Tuning::WASTING
    end

    # What hunger and thirst take off every roll to hit, on top of what
    # they take off dexterity.
    def to_hit_penalty : Int32
      (severity * Tuning::TO_HIT_LOSS).to_i
    end

    # What hunger and thirst take off melee and thrown damage, on top of
    # what they take off strength.
    def damage_penalty : Int32
      (severity * Tuning::DAMAGE_LOSS).to_i
    end

    # What hunger and thirst take off pace.
    def slowing : Int32
      (severity * Tuning::PACE_LOSS).to_i
    end

    # *attributes* as hunger and thirst leave them. Each score falls toward
    # `Attributes::MINIMUM` in step with severity, and is there at
    # severity 1. A score at or below the minimum stays where it is.
    def wear(attributes : Attributes) : Attributes
      found = severity
      return attributes if found <= 0.0

      held = Attributes::Which.values.map do |which|
        score = attributes[which]
        score - (Math.max(score - Attributes::MINIMUM, 0) * found).to_i
      end
      Attributes.new held[0], held[1], held[2], held[3], held[4]
    end

    # Whether the character can eat no more.
    def full? : Bool
      @hunger.zero?
    end

    # Whether the character has no thirst debt.
    def quenched? : Bool
      @thirst.zero?
    end

    # What the character has died of, or `nil` while neither debt has
    # reached its end.
    def death : Death?
      return Death::Thirst if @thirst >= Tuning::THIRST_DEATH
      return Death::Hunger if @hunger >= Tuning::HUNGER_DEATH

      nil
    end
  end

  # :ditto:
  alias HungerStage = Sustenance::HungerStage

  # :ditto:
  alias ThirstStage = Sustenance::ThirstStage
end
