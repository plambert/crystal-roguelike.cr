require "../roguelike"

module Roguelike
  # What each action costs, in energy.
  #
  # `Pace::TICK` is one tick. An action that costs two ticks leaves the actor
  # a tick in debt, which is paid off before it acts again.
  #
  # Everything costs one tick but getting a suit of armor on or off and
  # hitting something. A blow costs what the weapon says, and the table is
  # here so that changing a number is a change to one place rather than to
  # `Game`.
  module Costs
    # One turn of the world. Walking, reading, drinking, zapping, opening a
    # door, picking something up, waiting.
    TURN = Pace::TICK

    # A blow with nothing in the hand.
    BARE = 80

    # Getting a suit of armor on or off.
    #
    # Three turns. A cap goes on in one and chain mail does not, and the
    # difference is what makes changing armor with something in the room a
    # decision rather than a keystroke.
    BODY = 3 * Pace::TICK

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
