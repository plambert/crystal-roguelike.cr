require "../roguelike"

module Roguelike
  # What each action costs, in energy.
  #
  # `Pace::TICK` is one tick. An action that costs two ticks leaves the actor
  # a tick in debt, which is paid off before it acts again.
  #
  # Everything costs one tick but getting a suit of armor on or off,
  # driving a spike, hitting something, and walking in heavy armor. A blow
  # costs what the weapon says. The table is here so that changing a number
  # is a change to one place rather than to `Game`.
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

    # What medium armor adds to a step. Walking takes a tenth longer.
    MEDIUM_STEP = 10

    # What heavy armor adds to a step. Walking takes a quarter longer.
    HEAVY_STEP = 25

    # What heavy armor adds to a melee blow.
    HEAVY_BLOW = 20

    # What a shield adds to a melee blow.
    SHIELD_BLOW = 10

    # What one step costs in *worn*.
    #
    # Each piece adds what its `Bulk` says, so leather armor and chain mail
    # are a choice between pace and armor. The same rule holds for the
    # character and for a creature.
    def self.step(worn : Enumerable(Item)) : Int32
      TURN + worn.sum(&.kind.step_drag)
    end

    # What *worn* adds to one melee blow.
    def self.blow_drag(worn : Enumerable(Item)) : Int32
      worn.sum &.kind.blow_drag
    end

    # A part of a turn, in words, such as "a quarter" for 25.
    def self.share(cost : Int32) : String
      case cost
      when TURN // 10 then "a tenth"
      when TURN // 5  then "a fifth"
      when TURN // 4  then "a quarter"
      when TURN // 2  then "a half"
      else                 "#{cost * 100 // TURN} in a hundred"
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
