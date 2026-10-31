require "../roguelike"

module Roguelike
  # One temporary effect on the character, and the turns it has left.
  #
  # Each effect keeps its own timer where the game counts it down. This is a
  # reading of those timers, so a pane can list them without knowing where
  # each one lives.
  #
  # *left* is `nil` for an effect with no timer. A stage of hunger or thirst
  # lasts until the character eats or drinks, and the pane shows no count
  # for it.
  record Lasting, status : Event::Status, left : Int32? = nil do
    # Every status a reading can name, in the order a pane lists them.
    ORDER = [
      Event::Status::Hurried, Event::Status::Dragging, Event::Status::Blind,
      Event::Status::Hungry, Event::Status::Famished, Event::Status::Starving,
      Event::Status::Thirsty, Event::Status::Parched, Event::Status::Dehydrated,
      Event::Status::DyingOfThirst,
      Event::Status::WellFed, Event::Status::Refreshed, Event::Status::SteadyAim,
      Event::Status::SteadyHand, Event::Status::Sick,
    ]

    # The buffs from food. A pane draws these in a color apart from the
    # debuffs.
    BUFFS = [
      Event::Status::WellFed, Event::Status::Refreshed, Event::Status::SteadyAim,
      Event::Status::SteadyHand,
    ]

    # Whether *status* is a buff from food.
    def self.buff?(status : Event::Status) : Bool
      BUFFS.includes? status
    end

    # What runs on *player* now, in `ORDER`.
    #
    # A haste and a slow count ticks, and a blindness and a buff from food
    # count turns. One turn is one tick, so all of them read in turns.
    def self.on(player : Player) : Array(Lasting)
      found = [] of Lasting
      found << new(:hurried, player.pace.hasted) if player.pace.hurried?
      found << new(:dragging, player.pace.slowed) if player.pace.dragging?
      found << new(:blind, player.blinded) if player.blind?
      player.sustenance.statuses.each { |status| found << new(status) }
      player.buffs.each { |held| found << new(held.status, held.left) }
      found.sort_by! { |held| ORDER.index(held.status) || ORDER.size }
    end
  end
end
