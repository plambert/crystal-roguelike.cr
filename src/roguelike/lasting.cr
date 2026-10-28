require "../roguelike"

module Roguelike
  # One temporary effect on the character, and the turns it has left.
  #
  # Each effect keeps its own timer where the game counts it down. This is a
  # reading of those timers, so a pane can list them without knowing where
  # each one lives.
  record Lasting, status : Event::Status, left : Int32 do
    # Every status a reading can name, in the order a pane lists them.
    ORDER = [Event::Status::Hurried, Event::Status::Dragging, Event::Status::Blind]

    # What runs on *player* now, in `ORDER`.
    #
    # A haste and a slow count ticks, and a blindness counts turns. One turn
    # is one tick, so all three read in turns.
    def self.on(player : Player) : Array(Lasting)
      found = [] of Lasting
      found << new(:hurried, player.pace.hasted) if player.pace.hurried?
      found << new(:dragging, player.pace.slowed) if player.pace.dragging?
      found << new(:blind, player.blinded) if player.blind?
      found
    end
  end
end
