require "../../roguelike"

module Roguelike::Ui
  # A command is a UI flow, not a key or a model action.
  enum Command
    Walk
    Explore
    Travel
    Visit
    Ascend
    Descend
    Wait
    Rest
    Equip
    Remove
    Inventory
    PickUp
    Drop
    Drink
    Read
    Zap
    Apply
    Throw
    OpenDoor
    CloseDoor
    SpikeDoor
    BreakDoor
    Fire
    FireNearest
    Examine
    PanMap
    Recenter
    History
    FocusNext
    FocusPrevious
    FocusMap
    FocusInfo
    FocusLog
    Options
    Theme
    ToggleMouse
    Help
    WhatsNew
    SaveQuit
    ReplayToggle
    ReplayForward
    ReplayBack
    ReplayFaster
    ReplaySlower
    ReplayGoTo
    DebugConsole
  end

  # The stable catalog grouping for a command.
  enum CommandCategory
    Movement
    Time
    Equipment
    Items
    Environment
    Combat
    View
    System
    Replay
  end

  # Key-free information for one command.
  record CommandMetadata,
    id : Command,
    label : String,
    category : CommandCategory,
    description : String,
    order : Int32

  # A semantic target. Item identities are model IDs, never inventory letters.
  record CommandTarget,
    item_id : Int32? = nil,
    slot : Roguelike::Slot? = nil,
    direction : Roguelike::Direction? = nil,
    coordinate : {Int32, Int32}? = nil

  # The model state and UI mode used for read-only availability queries.
  record CommandContext,
    game : Roguelike::Game,
    viewing : Bool = false,
    debug : Bool = false,
    selected_item_id : Int32? = nil,
    selected_slot : Roguelike::Slot? = nil,
    selected_coordinate : {Int32, Int32}? = nil,
    vision : Roguelike::Vision? = nil

  # The read-only result for a command in one context.
  record CommandStatus,
    id : Command,
    available : Bool,
    reason : String?,
    targets : Array(CommandTarget) do
    def available? : Bool
      @available
    end
  end

  # Stable command metadata and read-only target eligibility.
  module Commands
    alias Game = Roguelike::Game
    alias Item = Roguelike::Item
    alias Slot = Roguelike::Slot
    alias Terrain = Roguelike::Terrain
    alias Vision = Roguelike::Vision

    private record Snapshot,
      context : CommandContext,
      vision : Vision,
      knowledge : Roguelike::Knowledge do
      def game : Game
        @context.game
      end
    end

    private record CarriedItem,
      letter : Char,
      item : Item,
      slot : Slot?

    private METADATA = [
      CommandMetadata.new(Command::Walk, "Walk", CommandCategory::Movement,
        "Walk in a selected direction.", 0),
      CommandMetadata.new(Command::Explore, "Explore", CommandCategory::Movement,
        "Walk toward reachable unexplored ground and remembered items.", 1),
      CommandMetadata.new(Command::Travel, "Travel", CommandCategory::Movement,
        "Choose a known square and walk there.", 2),
      CommandMetadata.new(Command::Visit, "Visit discoveries", CommandCategory::Movement,
        "Walk to an item found during the last explore.", 3),
      CommandMetadata.new(Command::Ascend, "Ascend", CommandCategory::Movement,
        "Use or route to known stairs leading up.", 4),
      CommandMetadata.new(Command::Descend, "Descend", CommandCategory::Movement,
        "Use or route to known stairs leading down.", 5),
      CommandMetadata.new(Command::Wait, "Wait", CommandCategory::Time,
        "Pass one turn.", 6),
      CommandMetadata.new(Command::Rest, "Rest", CommandCategory::Time,
        "Rest until healed or interrupted.", 7),
      CommandMetadata.new(Command::Equip, "Equip", CommandCategory::Equipment,
        "Wield or wear a carried item.", 8),
      CommandMetadata.new(Command::Remove, "Remove equipment", CommandCategory::Equipment,
        "Take a readied item off.", 9),
      CommandMetadata.new(Command::Inventory, "Inventory", CommandCategory::Items,
        "Browse carried items and their details.", 10),
      CommandMetadata.new(Command::PickUp, "Pick up", CommandCategory::Items,
        "Pick up an item from underfoot.", 11),
      CommandMetadata.new(Command::Drop, "Drop", CommandCategory::Items,
        "Drop a carried item group.", 12),
      CommandMetadata.new(Command::Drink, "Drink a potion", CommandCategory::Items,
        "Choose a carried potion to drink.", 13),
      CommandMetadata.new(Command::Read, "Read a scroll", CommandCategory::Items,
        "Choose a carried scroll to read.", 14),
      CommandMetadata.new(Command::Zap, "Zap a wand", CommandCategory::Items,
        "Choose a carried wand to use.", 15),
      CommandMetadata.new(Command::Apply, "Apply", CommandCategory::Items,
        "Use a carried light, fixture, or spike.", 16),
      CommandMetadata.new(Command::Throw, "Throw", CommandCategory::Items,
        "Choose a carried item and aim it.", 17),
      CommandMetadata.new(Command::OpenDoor, "Open door", CommandCategory::Environment,
        "Open a known shut door beside you.", 18),
      CommandMetadata.new(Command::CloseDoor, "Close door", CommandCategory::Environment,
        "Close a known open door beside you.", 19),
      CommandMetadata.new(Command::SpikeDoor, "Spike door", CommandCategory::Environment,
        "Drive a carried spike into a known shut door.", 20),
      CommandMetadata.new(Command::BreakDoor, "Break door", CommandCategory::Environment,
        "Break a known door that is stuck shut.", 21),
      CommandMetadata.new(Command::Fire, "Fire", CommandCategory::Combat,
        "Aim the readied ranged weapon.", 22),
      CommandMetadata.new(Command::FireNearest, "Fire at nearest enemy", CommandCategory::Combat,
        "Fire at the nearest visible enemy with a clear shot.", 23),
      CommandMetadata.new(Command::Examine, "Examine", CommandCategory::View,
        "Read what is known about a square.", 24),
      CommandMetadata.new(Command::PanMap, "Pan map", CommandCategory::View,
        "Move the map view without taking a turn.", 25),
      CommandMetadata.new(Command::Recenter, "Recenter map", CommandCategory::View,
        "Center the map on the character.", 26),
      CommandMetadata.new(Command::History, "Message history", CommandCategory::View,
        "Browse the message history.", 27),
      CommandMetadata.new(Command::FocusNext, "Next panel", CommandCategory::View,
        "Focus the next visible panel.", 28),
      CommandMetadata.new(Command::FocusPrevious, "Previous panel", CommandCategory::View,
        "Focus the previous visible panel.", 29),
      CommandMetadata.new(Command::FocusMap, "Focus map", CommandCategory::View,
        "Focus the map panel.", 30),
      CommandMetadata.new(Command::FocusInfo, "Focus information", CommandCategory::View,
        "Focus the information panel.", 31),
      CommandMetadata.new(Command::FocusLog, "Focus messages", CommandCategory::View,
        "Focus the message panel.", 32),
      CommandMetadata.new(Command::Options, "Options", CommandCategory::System,
        "Change application options.", 33),
      CommandMetadata.new(Command::Theme, "Color theme", CommandCategory::System,
        "Change the color theme.", 34),
      CommandMetadata.new(Command::ToggleMouse, "Toggle mouse", CommandCategory::System,
        "Turn mouse reporting on or off.", 35),
      CommandMetadata.new(Command::Help, "Help", CommandCategory::System,
        "Read help for the current controls.", 36),
      CommandMetadata.new(Command::WhatsNew, "What is new", CommandCategory::System,
        "Read the release notes.", 37),
      CommandMetadata.new(Command::SaveQuit, "Save and quit", CommandCategory::System,
        "Save the run and leave the game.", 38),
      CommandMetadata.new(Command::DebugConsole, "Debug console", CommandCategory::System,
        "Open the debug console.", 39),
      CommandMetadata.new(Command::ReplayToggle, "Play or pause", CommandCategory::Replay,
        "Start or pause replay playback.", 40),
      CommandMetadata.new(Command::ReplayForward, "Step forward", CommandCategory::Replay,
        "Advance one recorded action.", 41),
      CommandMetadata.new(Command::ReplayBack, "Step backward", CommandCategory::Replay,
        "Go back one recorded action.", 42),
      CommandMetadata.new(Command::ReplayFaster, "Increase replay speed", CommandCategory::Replay,
        "Increase replay playback speed.", 43),
      CommandMetadata.new(Command::ReplaySlower, "Decrease replay speed", CommandCategory::Replay,
        "Decrease replay playback speed.", 44),
      CommandMetadata.new(Command::ReplayGoTo, "Go to replay turn", CommandCategory::Replay,
        "Choose a turn in the recording.", 45),
    ] of CommandMetadata

    private ITEM_ACTIONS = {
      Command::Equip, Command::Remove, Command::Drop, Command::Drink,
      Command::Read, Command::Zap, Command::Apply, Command::Throw,
    }

    private GAMEPLAY = {
      Command::Walk, Command::Explore, Command::Travel, Command::Visit,
      Command::Ascend, Command::Descend, Command::Wait, Command::Rest,
      Command::Equip, Command::Remove, Command::PickUp, Command::Drop,
      Command::Drink, Command::Read, Command::Zap, Command::Apply,
      Command::Throw, Command::OpenDoor, Command::CloseDoor,
      Command::SpikeDoor, Command::BreakDoor, Command::Fire,
      Command::FireNearest,
    }

    private REPLAY = {
      Command::ReplayToggle, Command::ReplayForward, Command::ReplayBack,
      Command::ReplayFaster, Command::ReplaySlower, Command::ReplayGoTo,
    }

    # All commands supported in the selected application mode, in stable order.
    def self.all(viewing : Bool = false, debug : Bool = false) : Array(CommandMetadata)
      METADATA.select do |metadata|
        command = metadata.id
        next false if command.debug_console? && !debug
        next false if REPLAY.includes?(command) && !viewing
        next false if viewing && GAMEPLAY.includes?(command)

        true
      end
    end

    # Currently available commands for a game or selected semantic target.
    def self.available(game : Game, viewing : Bool = false, debug : Bool = false,
                       selected_item_id : Int32? = nil,
                       selected_slot : Slot? = nil,
                       selected_coordinate : {Int32, Int32}? = nil,
                       vision : Vision? = nil) : Array(CommandMetadata)
      context = CommandContext.new game, viewing, debug, selected_item_id,
        selected_slot, selected_coordinate, vision
      available context
    end

    # Currently available commands for a context.
    def self.available(context : CommandContext) : Array(CommandMetadata)
      metadata = all context.viewing, context.debug
      candidates = if context.selected_item_id
                     metadata.select { |entry| ITEM_ACTIONS.includes?(entry.id) }
                   elsif context.selected_slot
                     metadata.select(&.id.remove?)
                   else
                     metadata
                   end
      query = snapshot context
      candidates.select { |entry| status_in(entry.id, query).available? }
    end

    # Whether a command is available in this context.
    def self.available?(command : Command, context : CommandContext) : Bool
      status(command, context).available?
    end

    # The read-only reason and target candidates for one command.
    def self.status(command : Command, context : CommandContext) : CommandStatus
      unless supported?(command, context.viewing, context.debug)
        return CommandStatus.new command, false, mode_reason(command, context),
          [] of CommandTarget
      end

      status_in command, snapshot(context)
    end

    # An unavailable command's explanation, or `nil` when it is available.
    def self.reason(command : Command, context : CommandContext) : String?
      status(command, context).reason
    end

    # Known target candidates for a command, using stable semantic identities.
    def self.targets(command : Command, context : CommandContext) : Array(CommandTarget)
      status(command, context).targets
    end

    private def self.snapshot(context : CommandContext) : Snapshot
      game = context.game
      seen = context.vision || game.sight
      Snapshot.new context, seen, game.knowledge
    end

    private def self.supported?(command : Command, viewing : Bool, debug : Bool) : Bool
      return false if command.debug_console? && !debug
      return false if REPLAY.includes?(command) && !viewing
      return false if viewing && GAMEPLAY.includes?(command)

      true
    end

    private def self.mode_reason(command : Command, context : CommandContext) : String
      return "The debug console is not enabled." if command.debug_console? && !context.debug
      return "Replay controls are available only while viewing a recording." if REPLAY.includes?(command)
      return "Gameplay commands are unavailable while viewing a recording." if context.viewing

      "This command is unavailable in the current mode."
    end

    private def self.status_in(command : Command, query : Snapshot) : CommandStatus
      candidates = target_candidates command, query
      available = case command
                  in .wait? then !query.context.viewing && !query.game.over?
                  in .rest? then rest_available?(query)
                  in .walk? then !query.game.over?
                  in .travel?
                    !query.game.over? && (!selected_coordinate?(query) || !candidates.empty?)
                  in .examine?      then !selected_coordinate?(query) || !candidates.empty?
                  in .explore?      then explore_available?(query)
                  in .read?         then !query.game.cannot_read && !candidates.empty?
                  in .fire?         then !query.game.cannot_fire
                  in .fire_nearest? then !query.game.cannot_fire && !candidates.empty?
                  in .inventory?, .pan_map?, .recenter?, .history?,
                     .focus_next?, .focus_previous?, .focus_map?, .focus_info?,
                     .focus_log?, .options?, .theme?, .toggle_mouse?, .help?,
                     .whats_new?, .save_quit?, .replay_toggle?, .replay_forward?,
                     .replay_back?, .replay_faster?, .replay_slower?, .replay_go_to?,
                     .debug_console? then true
                  in .pick_up?, .equip?, .remove?, .drop?, .drink?, .zap?, .apply?,
                     .throw?, .open_door?, .close_door?, .spike_door?, .break_door?,
                     .visit?, .ascend?, .descend? then !candidates.empty?
                  end
      reason = available ? nil : unavailable_reason(command, query)
      CommandStatus.new command, available, reason, candidates
    end

    private def self.target_candidates(command : Command, query : Snapshot) : Array(CommandTarget)
      case command
      in .inventory? then carried_targets(query)
      in .pick_up?   then floor_item_targets(query)
      in .equip?, .remove?, .drop?, .drink?, .read?, .zap?, .throw?
        item_targets(command, query)
      in .apply?, .spike_door?  then apply_targets(command, query)
      in .open_door?            then door_targets(Terrain::ClosedDoor, query, open: true)
      in .close_door?           then door_targets(Terrain::OpenDoor, query)
      in .break_door?           then break_targets(query)
      in .fire?, .fire_nearest? then fire_targets(query)
      in .visit?                then visit_targets(query)
      in .ascend?               then stair_targets(Terrain::StairsUp, query)
      in .descend?              then stair_targets(Terrain::StairsDown, query)
      in .travel?               then travel_targets(query)
      in .examine?              then coordinate_targets(query)
      in .wait?, .rest?, .walk?, .explore?, .pan_map?, .recenter?, .history?,
         .focus_next?, .focus_previous?, .focus_map?, .focus_info?, .focus_log?,
         .options?, .theme?, .toggle_mouse?, .help?, .whats_new?, .save_quit?,
         .replay_toggle?, .replay_forward?, .replay_back?, .replay_faster?,
         .replay_slower?, .replay_go_to?, .debug_console?
        [] of CommandTarget
      end
    end

    private def self.item_targets(command : Command, query : Snapshot) : Array(CommandTarget)
      selected = selected_item query
      if query.context.selected_item_id
        return [] of CommandTarget unless selected
        return [] of CommandTarget unless selected_item_action?(command, selected)

        return [CommandTarget.new item_id: selected.item.id,
          slot: selected.slot]
      end

      if command.remove? && query.context.selected_slot
        return query.game.readied
          .select { |(slot, _item)| slot == query.context.selected_slot }
          .map { |(slot, item)| CommandTarget.new item_id: item.id, slot: slot }
      end

      query.game.player.inventory.entries.compact_map do |letter, _item|
        item = carried query, letter
        next unless item
        next unless item_action_for_group?(command, item.item, item.slot)

        CommandTarget.new item_id: item.item.id, slot: item.slot
      end
    end

    private def self.selected_item_action?(command : Command, item : CarriedItem) : Bool
      return item.slot.nil? && !Slot.for(item.item).nil? if command.equip?

      item_action_for_group? command, item.item, item.slot
    end

    private def self.item_action_for_group?(command : Command, item : Item,
                                            slot : Slot?) : Bool
      case command
      in .equip?         then !Slot.for(item).nil?
      in .remove?        then !slot.nil?
      in .drink?         then item.kind.item_class.potion?
      in .read?          then item.kind.item_class.scroll? && item_readable?(item)
      in .zap?           then item.kind.item_class.wand?
      in .apply?         then false
      in .throw?, .drop? then true
      in .walk?, .explore?, .travel?, .visit?, .ascend?, .descend?, .wait?, .rest?,
         .inventory?, .pick_up?, .open_door?, .close_door?, .spike_door?,
         .break_door?, .fire?, .fire_nearest?, .examine?, .pan_map?, .recenter?,
         .history?, .focus_next?, .focus_previous?, .focus_map?, .focus_info?,
         .focus_log?, .options?, .theme?, .toggle_mouse?, .help?, .whats_new?,
         .save_quit?, .replay_toggle?, .replay_forward?, .replay_back?,
         .replay_faster?, .replay_slower?, .replay_go_to?, .debug_console? then false
      end
    end

    private def self.item_readable?(item : Item) : Bool
      item.kind.item_class.scroll?
    end

    private def self.carried(query : Snapshot, letter : Char) : CarriedItem?
      item = query.game.carried letter
      return unless item

      CarriedItem.new letter, item, query.game.slot_of(letter)
    end

    private def self.selected_item(query : Snapshot) : CarriedItem?
      wanted = query.context.selected_item_id
      return unless wanted

      query.game.player.inventory.each_item do |letter, item|
        next unless item.id == wanted

        return carried query, letter
      end
      nil
    end

    private def self.carried_targets(query : Snapshot) : Array(CommandTarget)
      query.game.player.inventory.entries.compact_map do |letter, _item|
        item = carried query, letter
        CommandTarget.new(item_id: item.item.id, slot: item.slot) if item
      end
    end

    private def self.floor_item_targets(query : Snapshot) : Array(CommandTarget)
      query.game.here.map { |item| CommandTarget.new item_id: item.id }
    end

    private def self.apply_targets(command : Command, query : Snapshot) : Array(CommandTarget)
      selected = selected_item query if query.context.selected_item_id
      return [] of CommandTarget if query.context.selected_item_id && !selected

      query.game.appliable.compact_map do |target|
        letter = target.letter
        item = letter ? carried(query, letter) : nil
        next unless applicable_target?(command, target, item, selected, query)

        CommandTarget.new(item_id: item.try(&.item.id),
          coordinate: target.aimed? || !letter ? {target.x, target.y} : nil)
      end
    end

    private def self.applicable_target?(command : Command, target : Roguelike::Apply,
                                        item : CarriedItem?, selected : CarriedItem?,
                                        query : Snapshot) : Bool
      return false if command.spike_door? && !spike_target?(target, item)
      return false unless apply_target_known?(command, target, query)

      selected_item_matches? item, selected
    end

    private def self.spike_target?(target : Roguelike::Apply, item : CarriedItem?) : Bool
      target.aimed? && item.try(&.item.kind.spike?) == true
    end

    private def self.apply_target_known?(command : Command, target : Roguelike::Apply,
                                         query : Snapshot) : Bool
      return true unless command.apply? || command.spike_door?
      return true unless target.aimed? || target.letter.nil?

      known? query, {target.x, target.y}
    end

    private def self.selected_item_matches?(item : CarriedItem?, selected : CarriedItem?) : Bool
      selected.nil? || item.try(&.item.id) == selected.item.id
    end

    private def self.door_targets(terrain : Terrain, query : Snapshot,
                                  open : Bool = false) : Array(CommandTarget)
      Direction.values.compact_map do |direction|
        coordinate = direction.from query.game.player.x, query.game.player.y
        next unless known_terrain(query, coordinate) == terrain
        next if open && query.knowledge.barred? coordinate[0], coordinate[1]
        next if selected_coordinate?(query) && query.context.selected_coordinate != coordinate

        CommandTarget.new direction: direction, coordinate: coordinate
      end
    end

    private def self.break_targets(query : Snapshot) : Array(CommandTarget)
      return [] of CommandTarget unless query.game.armed?

      Direction.values.compact_map do |direction|
        coordinate = direction.from query.game.player.x, query.game.player.y
        next unless query.knowledge.barred? coordinate[0], coordinate[1]
        next unless known_terrain(query, coordinate).try(&.closed_door?)
        next if selected_coordinate?(query) && query.context.selected_coordinate != coordinate

        CommandTarget.new direction: direction, coordinate: coordinate
      end
    end

    private def self.fire_targets(query : Snapshot) : Array(CommandTarget)
      targets = query.game.monsters_in_sight(query.vision).select do |creature|
        query.game.reachable? creature.at
      end
      targets.sort_by! do |creature|
        across = creature.x - query.game.player.x
        down = creature.y - query.game.player.y
        {across * across + down * down, creature.y, creature.x}
      end
      targets.map { |creature| CommandTarget.new coordinate: creature.at }
    end

    private def self.visit_targets(query : Snapshot) : Array(CommandTarget)
      target = query.game.next_sighting
      target ? [CommandTarget.new coordinate: target] : [] of CommandTarget
    end

    private def self.stair_targets(terrain : Terrain, query : Snapshot) : Array(CommandTarget)
      target = if query.game.standing_on == terrain
                 query.game.player.at
               else
                 query.game.remembered_stairs terrain
               end
      return [] of CommandTarget unless target
      return [] of CommandTarget if selected_coordinate?(query) && query.context.selected_coordinate != target

      [CommandTarget.new coordinate: target]
    end

    private def self.travel_targets(query : Snapshot) : Array(CommandTarget)
      coordinate = query.context.selected_coordinate
      return [] of CommandTarget unless coordinate
      return [] of CommandTarget if coordinate == query.game.player.at
      return [] of CommandTarget unless query.knowledge.crossable? coordinate

      [CommandTarget.new coordinate: coordinate]
    end

    private def self.coordinate_targets(query : Snapshot) : Array(CommandTarget)
      coordinate = query.context.selected_coordinate
      return [] of CommandTarget unless coordinate
      return [] of CommandTarget unless query.game.floor.contains? coordinate[0], coordinate[1]

      [CommandTarget.new coordinate: coordinate]
    end

    private def self.selected_coordinate?(query : Snapshot) : Bool
      !query.context.selected_coordinate.nil?
    end

    private def self.known?(query : Snapshot, coordinate : {Int32, Int32}) : Bool
      query.vision.includes?(coordinate) || !query.knowledge[coordinate].nil?
    end

    private def self.known_terrain(query : Snapshot, coordinate : {Int32, Int32}) : Terrain?
      return unless query.game.floor.contains? coordinate[0], coordinate[1]
      return query.game.floor.terrain coordinate[0], coordinate[1] if query.vision.includes? coordinate

      query.knowledge[coordinate].try(&.terrain)
    end

    private def self.explore_available?(query : Snapshot) : Bool
      game = query.game
      return false if game.over?

      Roguelike::Explore.going? query.knowledge, game.player.at,
        game.floor.columns, game.floor.rows
    end

    private def self.rest_available?(query : Snapshot) : Bool
      !query.context.viewing && !query.game.over? && query.game.resting.halt.nil?
    end

    private def self.unavailable_reason(command : Command, query : Snapshot) : String
      return "The run has ended." if query.game.over? && GAMEPLAY.includes?(command)
      return "The selected item is no longer carried." if query.context.selected_item_id && selected_item(query).nil?

      case command
      in .pick_up? then "There is nothing here to pick up."
      in .equip?   then "You have nothing to wield or wear."
      in .remove?  then "You are not wearing or holding anything."
      in .drop?    then "You are carrying nothing."
      in .drink?   then "You have nothing to drink."
      in .read?
        query.game.cannot_read || "You have nothing to read."
      in .zap?        then "You have nothing to zap."
      in .apply?      then "You have nothing to light or spike, and there is no sconce beside you."
      in .spike_door? then "There is no known shut door to spike."
      in .open_door?  then "There is no known shut door beside you."
      in .close_door? then "There is no known open door beside you."
      in .break_door? then "There is no known stuck door to break."
      in .fire?       then query.game.cannot_fire || "There is no usable shot."
      in .fire_nearest?
        fire_nearest_reason query
      in .rest?    then "You cannot rest now."
      in .explore? then "There is nothing known to explore."
      in .visit?   then "There is nothing more to walk to."
      in .travel?  then "Choose a known square to travel to."
      in .ascend?  then "There are no known stairs leading up."
      in .descend? then "There are no known stairs leading down."
      in .wait?    then "You cannot wait while viewing a recording."
      in .walk?    then "The run has ended."
      in .examine? then "Choose a square to examine."
      in .throw?   then "You have nothing to throw."
      in .inventory?, .pan_map?, .recenter?, .history?, .focus_next?,
         .focus_previous?, .focus_map?, .focus_info?, .focus_log?, .options?,
         .theme?, .toggle_mouse?, .help?, .whats_new?, .save_quit?,
         .replay_toggle?, .replay_forward?, .replay_back?, .replay_faster?,
         .replay_slower?, .replay_go_to?, .debug_console?
        "This command is unavailable now."
      end
    end

    private def self.fire_nearest_reason(query : Snapshot) : String
      complaint = query.game.cannot_fire
      return complaint if complaint
      return "There is nothing to fire at." if query.game.monsters_in_sight(query.vision).empty?

      "There is no clear shot."
    end
  end
end
