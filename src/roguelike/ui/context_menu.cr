require "../../crystal-roguelike"

module Roguelike::Ui
  # What the context menu on a map square can do. Members are only ever
  # appended.
  enum ContextVerb
    # Points the readout at the square.
    Examine

    # Walks to the square.
    Walk

    # Opens the shut door on the square.
    Open

    # Shuts the open door on the square.
    Close

    # Drives a spike into the shut door on the square.
    Spike

    # Goes down the staircase on the square.
    Descend

    # Goes up the staircase on the square.
    Ascend

    # Drinks at the fountain on the square.
    Drink

    # Fills the waterskin at the fountain on the square.
    Fill

    # Picks up what lies on the square.
    PickUp

    # Where the character has to stand to do this.
    def reach : ContextReach
      case self
      in .examine?                                       then ContextReach::Anywhere
      in .walk?                                          then ContextReach::Anywhere
      in .open?, .close?, .spike?                        then ContextReach::Beside
      in .descend?, .ascend?, .drink?, .fill?, .pick_up? then ContextReach::On
      end
    end
  end

  # Where the character stands to do a `ContextVerb`.
  enum ContextReach
    # Nowhere in particular. The verb does not need a walk first.
    Anywhere

    # On a square next to the target, and not on it.
    Beside

    # On the target.
    On
  end

  # One row of the menu.
  record ContextRow, verb : ContextVerb, label : String, hint : String?, enabled : Bool

  # What a verb is waiting on. A pending verb walks first, then acts when the
  # walk ends where it was meant to.
  record ContextErrand,
    verb : ContextVerb,
    target : {Int32, Int32},
    stand : {Int32, Int32},
    floor : String

  # The rows of the right-click menu on a map square, and where the character
  # stands to use them.
  #
  # Every answer comes from what the character knows. A door that was opened
  # out of sight shows as shut until somebody looks again.
  module ContextMenu
    # The key that does what a row does, by control scheme. A verb with no
    # entry has no key in that scheme.
    TRADITIONAL_KEYS = {
      ContextVerb::Examine => "x",
      ContextVerb::Walk    => "_",
      ContextVerb::Open    => "o",
      ContextVerb::Close   => "c",
      ContextVerb::Spike   => "c",
      ContextVerb::Descend => ">",
      ContextVerb::Ascend  => "<",
      ContextVerb::Drink   => "U",
      ContextVerb::Fill    => "U",
      ContextVerb::PickUp  => ",",
    }

    # :ditto:
    MODERN_KEYS = {
      ContextVerb::Descend => ">",
      ContextVerb::Ascend  => "<",
      ContextVerb::PickUp  => "g",
    }

    # The key hint for *verb* under *scheme*. `nil` when it has none.
    def self.hint(verb : ContextVerb, scheme : Options::ControlScheme) : String?
      keys = scheme.modern? ? MODERN_KEYS : TRADITIONAL_KEYS
      keys[verb]?
    end

    # The rows for *spot*. Empty when the character knows nothing of it.
    #
    # A row for a verb that exists and cannot be done now is shown dimmed.
    def self.rows(game : Game, spot : {Int32, Int32},
                  scheme : Options::ControlScheme) : Array(ContextRow)
      knowledge = game.knowledge
      return [] of ContextRow unless knowledge.known? spot

      memory = knowledge[spot]
      terrain = memory.try &.terrain
      here = spot == game.player.at
      sustenance = game.player.sustenance
      found = [] of ContextRow

      add = ->(verb : ContextVerb, label : String, enabled : Bool) do
        found << ContextRow.new(verb, label, hint(verb, scheme), enabled)
        nil
      end

      if terrain
        case terrain
        when .closed_door?
          add.call ContextVerb::Open, "Open", true
          if game.spike_carried
            add.call ContextVerb::Spike, "Spike", !memory.try(&.spiked?)
          end
        when .open_door?
          add.call ContextVerb::Close, "Close", !here
        when .stairs_down?
          add.call ContextVerb::Descend, "Descend", true
        when .stairs_up?
          add.call ContextVerb::Ascend, "Ascend", true
        when .fountain?
          add.call ContextVerb::Drink, "Drink", !sustenance.quenched?
          add.call ContextVerb::Fill, "Fill waterskin", !game.skin_full?
        end
      end

      add.call ContextVerb::PickUp, "Pick up", true if memory.try &.items?
      add.call ContextVerb::Walk, "Walk here", true if !here && knowledge.crossable?(spot)
      add.call ContextVerb::Examine, "Examine", true

      found
    end

    # Whether the character stands where *verb* can be done on *target*.
    def self.reached?(verb : ContextVerb, game : Game, target : {Int32, Int32}) : Bool
      here = game.player.at

      case verb.reach
      in .anywhere? then true
      in .beside?   then here != target && Notice.touching?(here, target)
      in .on?       then here == target
      end
    end

    # The square the character walks to before doing *verb* on *target*.
    # `nil` when no known way leads there.
    #
    # A verb done on the spot needs the target itself. A verb done beside the
    # target needs the nearest known square next to it, so the walk never
    # steps onto a door that is about to be shut. A square the way to which
    # does not pass through the target comes first.
    def self.stand_for(verb : ContextVerb, game : Game,
                       target : {Int32, Int32}) : {Int32, Int32}?
      return target unless verb.reach.beside?

      knowledge = game.knowledge
      options = Direction.values.compact_map do |direction|
        square = direction.from target[0], target[1]
        next unless knowledge.walkable? square

        route = game.way_to square
        next if route.size < 2

        door = knowledge[square].try(&.terrain.door?) || false
        {square, {route.includes?(target) ? 1 : 0, door ? 1 : 0, route.size, square[1], square[0]}}
      end

      options.min_by?(&.[1]).try &.[0]
    end
  end
end
