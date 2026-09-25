require "./pace"
require "./slot"

module Roguelike
  # What each action costs, in energy.
  #
  # `Pace::TICK` is one tick. An action that costs two ticks leaves the actor
  # a tick in debt, which is paid off before it acts again.
  #
  # Everything costs one tick but getting a suit of armor on or off. The
  # table is here so that changing one of those is a change to one number
  # rather than a change to `Game`.
  module Costs
    # One turn of the world. Walking, swinging, reading, drinking, zapping,
    # opening a door, picking something up, waiting.
    TURN = Pace::TICK

    # Getting a suit of armor on or off.
    #
    # Three turns. A cap goes on in one and chain mail does not, and the
    # difference is what makes changing armor with something in the room a
    # decision rather than a keystroke.
    BODY = 3 * Pace::TICK

    # What filling *slot* costs, or emptying it again.
    #
    # Body armor is the slow one. Everything else a character holds or wears
    # takes a turn.
    def self.donning(slot : Slot?) : Int32
      slot.try(&.body?) ? BODY : TURN
    end
  end
end
