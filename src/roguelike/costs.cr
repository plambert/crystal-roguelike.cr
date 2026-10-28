require "../roguelike"

module Roguelike
  # What each action costs, in energy.
  #
  # `Pace::TICK` is one tick. An action that costs two ticks leaves the actor
  # a tick in debt, which is paid off before it acts again.
  #
  # Everything costs one tick but getting a suit of armor on or off,
  # driving a spike, hitting something, and walking in anything but leather
  # armor. A blow costs what the weapon says and what the armor adds. The
  # tables are here so that changing a number is a change to one place
  # rather than to `Game`.
  module Costs
    # One turn of the world. Walking, reading, drinking, zapping, opening a
    # door, picking something up, waiting.
    TURN = Pace::TICK

    # A blow with nothing in the hand.
    BARE = 80

    # Driving an iron spike into a door.
    #
    # Half a turn. A person shuts a door on something chasing them and
    # spikes it before the chaser reaches it.
    SPIKE = TURN // 2

    # Getting a suit of armor on or off.
    #
    # Three turns. A cap goes on in one and chain mail does not, and the
    # difference is what makes changing armor with something in the room a
    # decision rather than a keystroke.
    BODY = 3 * Pace::TICK

    # What a step costs and what a melee blow gains, by the class of the
    # body armor worn.
    #
    # Leather armor is medium and walks at a normal pace. Less is quicker
    # and more is slower. The blow cost goes on top of the weapon's swing.
    # A creature's hide counts for the step and adds nothing to a blow.
    PACES = {
      Bulk::None      => {90, 0},
      Bulk::Light     => {95, 5},
      Bulk::Medium    => {100, 10},
      Bulk::Heavy     => {105, 20},
      Bulk::VeryHeavy => {110, 30},
    }

    # What a shield adds to a melee blow. It does not slow a step.
    SHIELD_BLOW = 10

    # What wearing *worn* adds to one melee blow: the body armor's class and
    # a shield.
    def self.blow_drag(worn : Enumerable(Item)) : Int32
      worn.sum do |item|
        kind = item.kind
        next SHIELD_BLOW if kind.slot.try &.shield?

        kind.slot.try(&.body?) ? kind.bulk.blow : 0
      end
    end

    # The class of the body armor in *worn*. `None` when there is none.
    def self.body(worn : Enumerable(Item)) : Bulk
      worn.find(&.kind.slot.try &.body?).try(&.kind.bulk) || Bulk::None
    end

    # A part of a turn, in words, such as "a quarter" for 25.
    def self.share(cost : Int32) : String
      case cost
      when TURN // 20 then "a twentieth"
      when TURN // 10 then "a tenth"
      when TURN // 5  then "a fifth"
      when TURN // 4  then "a quarter"
      when TURN // 2  then "a half"
      else                 "#{cost * 100 // TURN}%"
      end
    end

    # What one melee blow with *item* costs.
    #
    # `nil` is bare hands. A thing with no dice of its own, a cursed wand
    # for one, is swung like a fist.
    def self.swing(item : Item?) : Int32
      return BARE unless item && Player.swung?(item)

      item.kind.swing
    end

    # What shooting with the ranged weapon *item*, or throwing *item*, costs.
    def self.loose(item : Item) : Int32
      item.kind.swing
    end

    # What a cost reads as to a player.
    def self.pace_word(cost : Int32) : String
      if cost < TURN
        "quick"
      elsif cost > TURN
        "slow"
      else
        "normal"
      end
    end

    # What filling *slot* costs, or emptying it again.
    #
    # Body armor is the slow one. Everything else a character holds or wears
    # takes a turn.
    def self.donning(slot : Slot?) : Int32
      slot.try(&.body?) ? BODY : TURN
    end
  end
end
