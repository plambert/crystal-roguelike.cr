require "./pace"

module Roguelike
  # What each action costs, in energy.
  #
  # `Pace::TICK` is one tick. An action that costs two ticks leaves the actor
  # a tick in debt, which is paid off before it acts again.
  #
  # Every action costs one tick today. The table is here so that changing one
  # of them is a change to one number rather than a change to `Game`.
  module Costs
    # One turn of the world. Walking, swinging, reading, drinking, zapping,
    # opening a door, picking something up, waiting.
    TURN = Pace::TICK
  end
end
