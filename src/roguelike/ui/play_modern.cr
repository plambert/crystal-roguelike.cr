require "../../crystal-roguelike"

module Roguelike::Ui
  class Play
    property? kitty_keyboard : Bool = false

    @modern_mode : ModernMenuKind = ModernMenuKind::None
    @modern_stack = [] of ModernMenuFrame
    @modern_command : Command? = nil
    @modern_item_id : Int32? = nil
    @modern_inventory_item : Int32? = nil
    @modern_inventory_page : Int32 = 0
    @modern_inventory_index : Int32? = nil
    @modern_cancel_frame : ModernMenuFrame? = nil
    @modern_cancel_stack = [] of ModernMenuFrame

    # The selected input profile. Headless callers without saved options keep
    # the historical bindings.
    def control_scheme : Options::ControlScheme
      (Options.current || Options.new).effective_control_scheme
    end

    def modern_controls? : Bool
      control_scheme.modern?
    end

    # Stops automated movement before its input ownership changes.
    def controls_changed : Nil
      interrupted if walking? || resting?
      @character.letterless = modern_controls?
      @examine.control_scheme = control_scheme
      @history.control_scheme = control_scheme
      navigation = modern_controls? ? Widgets::Navigation.selectable : Widgets::Navigation.new
      @selection_menu.navigation = navigation
      refresh
    end

    # Ends startup after the chooser is canceled, without starting a run.
    def abort_startup : Nil
      @finished = true
    end

    # Reports an application warning in the message pane.
    def report_warning(message : String) : Nil
      say message
    end

    # Sends ordinary modern movement to the focused panel, a cursor, or the
    # character without allowing a panel key to move the character.
    def modern_move(direction : Direction) : Nil
      if @pending || @aiming || @examiner.cursoring?
        return step direction
      end

      return view_move direction if @viewer

      case @ring.current
      in .map? then step direction
      in .info?
        case direction
        in .north?                                                then up
        in .south?                                                then down
        in .west?                                                 then left
        in .east?                                                 then right
        in .north_west?, .north_east?, .south_west?, .south_east? then nil
        end
      in .log?
        scroll_rows(direction.north? ? -1 : 1) if direction.north? || direction.south?
      end
    end

    # Starts a shifted walk on the map, or moves a cursor while one owns the
    # input.
    def modern_walk(direction : Direction) : Nil
      if @pending || @aiming || @examiner.cursoring?
        return step direction
      end
      return unless @ring.map?
      return if @viewer

      dash direction
    end

    # Waits only when live play has no pending direction or target capture.
    def live_wait : Nil
      return if modern_controls? && (@pending || @aiming || @examiner.cursoring?)
      return if @viewer

      wait
    end

    # Opens the complete catalog, without applying availability filtering.
    def show_action_catalog : Nil
      return if @pending || @aiming || @examiner.cursoring?
      @modern_stack.clear
      show_command_catalog ModernMenuKind::Catalog
    end

    # Opens the available catalog, using a selected item or slot when the info
    # panel owns the focus.
    def show_available_actions : Nil
      return if @pending || @aiming || @examiner.cursoring?
      if !@viewer && (item_id = selected_panel_item_id)
        show_item_actions item_id
      elsif !@viewer && (slot = selected_panel_slot)
        show_slot_actions slot
      else
        @modern_stack.clear
        show_command_catalog ModernMenuKind::Available
      end
    end

    # Opens inventory without requiring the internal inventory letter.
    def show_modern_inventory : Nil
      if @modern_mode.inventory? && @menu.showing?
        @selection_menu.cancel
        return
      end
      return if @pending || @aiming || @examiner.cursoring?

      @modern_stack.clear
      @modern_inventory_item = nil
      @modern_inventory_page = 0
      @modern_inventory_index = nil
      show_inventory_values
    end

    # The modern action key confirms an active target, otherwise it opens the
    # available-action menu.
    def modern_available_action : Nil
      return loose if @aiming
      return if @pending || @examiner.cursoring?

      show_available_actions
    end

    def modern_explore : Nil
      return if @pending || @aiming || @examiner.cursoring?

      explore
    end

    def modern_stair_up : Nil
      return if @pending || @aiming || @examiner.cursoring?

      ascend
    end

    def modern_stair_down : Nil
      return if @pending || @aiming || @examiner.cursoring?

      descend
    end

    # A modern menu that already has a semantic item uses that item as its
    # context rather than the current mouse examiner square.
    def open_modern_item(item_id : Int32) : Nil
      return if @viewer

      show_item_actions item_id
    end

    # Opens a selectable title list whose saved-character count is not tied to
    # the legacy letter range.
    def show_modern_title : Nil
      held = saved
      @selection_menu.navigation = Widgets::Navigation.selectable
      first = value_entry(ModernChoice.new(ModernChoiceKind::TitleNew), Placards::NEW_ROW)
      entries = [first]
      held.each do |character|
        entries << value_entry(
          ModernChoice.new(ModernChoiceKind::TitleCharacter, character: character.name),
          Placards.saved_row(character))
      end
      entries << value_entry(ModernChoice.new(ModernChoiceKind::TitleOptions), Placards::OPTIONS_ROW)
      entries << value_entry(ModernChoice.new(ModernChoiceKind::TitleNews), Placards::WHATS_NEW_ROW) unless @news.empty?
      entries << value_entry(ModernChoice.new(ModernChoiceKind::TitleQuit), Placards::QUIT_ROW)

      @modern_stack.clear
      @modern_mode = ModernMenuKind::Title
      @selection_menu.on_choose = ->(choice : ModernChoice) { choose_title_choice choice }
      @selection_menu.on_back = -> { @finished = true; nil }
      @menu.column_margin = TITLE_MARGIN
      @menu.on_highlight = nil
      @selection_menu.show application, Placards.title_bar(@game.world.seed), entries
    end

    private def choose_title_choice(choice : ModernChoice) : Nil
      case choice.kind
      in .title_new?       then ask_the_name
      in .title_character? then answered_the_name(choice.character || "")
      in .title_options?   then show_options(-> { show_title; nil })
      in .title_news?      then show_news
      in .title_quit?      then @finished = true
      in .command?, .item?, .target?, .direction?, .empty?, .more_actions?
        nil
      end
    end

    private def show_command_catalog(kind : ModernMenuKind,
                                     selected_item_id : Int32? = nil,
                                     selected_slot : Slot? = nil) : Nil
      @modern_mode = kind
      @selection_menu.navigation = Widgets::Navigation.selectable
      @modern_item_id = selected_item_id
      context = command_context(selected_item_id, selected_slot)
      metadata = if kind.available? || kind.item_actions?
                   Commands.available context
                 else
                   Commands.all(@viewer != nil, @console != nil)
                 end
      metadata.reject! { |entry| unavailable_after_end?(entry.id) } if @game.over?

      pages = CommandCategory.values.map do |category|
        rows = metadata.select { |entry| entry.category == category }.map do |entry|
          choice = ModernChoice.new(ModernChoiceKind::Command, command: entry.id,
            item_id: selected_item_id, slot: selected_slot)
          value_entry choice, "#{entry.label} — #{entry.description}"
        end
        if rows.empty?
          rows << value_entry(ModernChoice.new(ModernChoiceKind::Empty), "No actions in this category",
            enabled: false)
        end
        {category_label(category), rows}
      end

      if kind.available? && selected_item_id.nil? && selected_slot.nil?
        pages.last[1] << value_entry(ModernChoice.new(ModernChoiceKind::MoreActions), "More actions…")
      end

      title = kind.available? ? "Available actions" : "Action catalog"
      if selected_item_id
        title = item_for(selected_item_id).try { |item| @game.name(item) } || "Item actions"
      end
      @selection_menu.on_choose = ->(choice : ModernChoice) { choose_modern_choice choice }
      @selection_menu.on_back = -> { back_modern_menu; nil }
      @selection_menu.show application, title, pages, 0
    end

    private def unavailable_after_end?(command : Command) : Bool
      case command
      in .walk?, .explore?, .travel?, .visit?, .ascend?, .descend?, .wait?, .rest?,
         .equip?, .remove?, .pick_up?, .drop?, .drink?, .read?, .zap?, .apply?,
         .throw?, .open_door?, .close_door?, .spike_door?, .break_door?, .fire?,
         .fire_nearest?
        true
      in .inventory?, .examine?, .pan_map?, .recenter?, .history?, .focus_next?,
         .focus_previous?, .focus_map?, .focus_info?, .focus_log?, .options?,
         .theme?, .toggle_mouse?, .help?, .whats_new?, .save_quit?,
         .replay_toggle?, .replay_forward?, .replay_back?, .replay_faster?,
         .replay_slower?, .replay_go_to?, .debug_console?
        false
      end
    end

    private def command_context(item_id : Int32? = nil, slot : Slot? = nil) : CommandContext
      CommandContext.new @game, !@viewer.nil?, !@console.nil?, item_id, slot
    end

    private def category_label(category : CommandCategory) : String
      case category
      in .movement?    then "Movement"
      in .time?        then "Time"
      in .equipment?   then "Equipment"
      in .items?       then "Items"
      in .environment? then "Environment"
      in .combat?      then "Combat"
      in .view?        then "View"
      in .system?      then "System"
      in .replay?      then "Replay"
      end
    end

    private def value_entry(choice : ModernChoice, text : String,
                            enabled : Bool = true, mark : Char? = nil,
                            mark_style : Style? = nil, tail : Char? = nil,
                            tail_style : Style? = nil,
                            shortcut : Char? = nil,
                            reason : String? = nil)
      @selection_menu.entry choice, text, enabled, mark, mark_style, tail,
        tail_style, shortcut, disabled_reason: reason
    end

    private def choose_modern_choice(choice : ModernChoice) : Nil
      case choice.kind
      in .command?
        command = choice.command
        begin_modern_command command, choice.item_id, choice.slot if command
      in .item?
        item_id = choice.item_id
        if item_id
          @modern_inventory_item = item_id
          if @viewer
            show_inventory_values
          else
            show_item_actions item_id
          end
        end
      in .target?
        command = @modern_command
        commit_modern_target command, choice if command
      in .direction?
        if direction = choice.direction
          take_modern_direction direction
        end
      in .more_actions?
        push_modern_frame
        show_command_catalog ModernMenuKind::Catalog
      in .empty?, .title_new?, .title_character?, .title_options?, .title_news?, .title_quit?
        nil
      end
    end

    private def begin_modern_command(command : Command, item_id : Int32? = nil,
                                     slot : Slot? = nil) : Nil
      context = command_context(item_id, slot)
      status = Commands.status command, context
      case command
      in .walk?, .pan_map?
        push_modern_frame
        show_modern_directions command
      in .travel?    then travel
      in .examine?   then toggle_examine
      in .inventory? then show_modern_inventory
      in .fire_nearest?
        if status.available?
          fire_at_nearest
        else
          show_empty_target command, status.reason || "There is nothing to fire at."
        end
      in .visit?
        if status.available?
          visit
        else
          show_empty_target command, status.reason || "There is nothing more to walk to."
        end
      in .fire?
        if status.available?
          fire
        else
          begin_modern_targeted command, status, item_id, slot
        end
      in .explore?, .ascend?, .descend?, .wait?, .rest?, .equip?, .remove?,
         .pick_up?, .drop?, .drink?, .read?, .zap?, .apply?, .throw?,
         .open_door?, .close_door?, .spike_door?, .break_door?, .recenter?,
         .history?, .focus_next?, .focus_previous?, .focus_map?, .focus_info?,
         .focus_log?, .options?, .theme?, .toggle_mouse?, .help?, .whats_new?,
         .save_quit?, .replay_toggle?, .replay_forward?, .replay_back?,
         .replay_faster?, .replay_slower?, .replay_go_to?, .debug_console?
        begin_modern_targeted command, status, item_id, slot
      end
    end

    private def begin_modern_targeted(command : Command, status : CommandStatus,
                                      item_id : Int32?, slot : Slot?) : Nil
      if (item_id || slot) && status.targets.size == 1 && !command.apply?
        commit_modern_target command, target_choice(status.targets.first)
        return
      end
      if status.targets.empty?
        if needs_modern_target?(command) || !status.available?
          show_empty_target command, status.reason || "This action is unavailable."
          return
        end

        dispatch_modern(command, item_id, slot)
        return
      end

      push_modern_frame
      show_modern_targets command, status.targets
    end

    private def needs_modern_target?(command : Command) : Bool
      case command
      in .pick_up?, .equip?, .remove?, .drop?, .drink?, .read?, .zap?, .apply?,
         .throw?, .open_door?, .close_door?, .spike_door?, .break_door?,
         .fire?, .fire_nearest?, .visit?, .ascend?, .descend?
        true
      in .walk?, .travel?, .examine?, .pan_map?, .wait?, .rest?, .explore?,
         .inventory?, .focus_next?, .focus_previous?, .focus_map?, .focus_info?,
         .focus_log?, .history?, .recenter?, .options?, .theme?, .toggle_mouse?,
         .help?, .whats_new?, .save_quit?, .replay_toggle?, .replay_forward?,
         .replay_back?, .replay_faster?, .replay_slower?, .replay_go_to?,
         .debug_console?
        false
      end
    end

    private def show_modern_targets(command : Command, targets : Array(CommandTarget),
                                    reason : String? = nil) : Nil
      @modern_command = command
      @modern_mode = ModernMenuKind::Targets
      directions = !targets.empty? && targets.all? { |target| !target.direction.nil? }
      @selection_menu.navigation = directions ? direction_navigation : Widgets::Navigation.selectable
      rows = targets.map do |target|
        direction = target.direction
        value_entry(target_choice(target), target_label(command, target),
          shortcut: direction.try { |found| direction_key(found) })
      end
      rows << value_entry(ModernChoice.new(ModernChoiceKind::Empty),
        "#{reason || "No usable target."} Escape goes back.",
        enabled: false) if rows.empty?
      @selection_menu.on_choose = ->(choice : ModernChoice) { choose_modern_choice choice }
      @selection_menu.on_back = -> { back_modern_menu; nil }
      @selection_menu.show application, "#{command_label(command)} — choose a target", rows
    end

    private def show_empty_target(command : Command, reason : String) : Nil
      push_modern_frame
      show_modern_targets command, [] of CommandTarget, reason
    end

    private def target_choice(target : CommandTarget) : ModernChoice
      ModernChoice.new(ModernChoiceKind::Target, command: @modern_command,
        item_id: target.item_id, slot: target.slot,
        direction: target.direction, coordinate: target.coordinate)
    end

    private def target_label(command : Command, target : CommandTarget) : String
      if item_id = target.item_id
        item = item_for item_id
        if item
          return Naming.listed @game.lore, item
        end
        return "Item no longer available"
      end
      if direction = target.direction
        return direction.label
      end
      if spot = target.coordinate
        return "Known square at #{spot[0]}, #{spot[1]}"
      end

      command_label command
    end

    private def command_label(command : Command) : String
      label = Commands.all(@viewer != nil, @console != nil).find { |entry| entry.id == command }
      label.try(&.label) || command.to_s.underscore.split('_').map(&.capitalize).join(' ')
    end

    private def show_modern_directions(command : Command) : Nil
      @modern_command = command
      @modern_mode = ModernMenuKind::Directions
      @selection_menu.navigation = direction_navigation
      rows = Direction.values.map do |direction|
        value_entry ModernChoice.new(ModernChoiceKind::Direction, direction: direction),
          direction.label, shortcut: direction_key(direction)
      end
      @selection_menu.on_choose = ->(choice : ModernChoice) { choose_modern_choice choice }
      @selection_menu.on_back = -> { back_modern_menu; nil }
      @selection_menu.show application, "#{command_label(command)} — choose a direction", rows
    end

    private def direction_navigation : Widgets::Navigation
      Widgets::Navigation.new previous_row: TermBuf::Key.parse("Up"),
        next_row: TermBuf::Key.parse("Down"),
        previous_tab: TermBuf::Key.parse("Left"),
        next_tab: TermBuf::Key.parse("Right"),
        activate: TermBuf::Key.parse("Enter f"),
        cancel: TermBuf::Key.parse("Escape"),
        row_shortcuts: true, display_shortcuts: true
    end

    private def direction_key(direction : Direction) : Char?
      Controls.moves(Options::ControlScheme::Modern).find { |_key, found| found == direction }
        .try(&.[0][0])
    end

    private def take_modern_direction(direction : Direction) : Nil
      command = @modern_command
      clear_modern_menu
      return unless command

      case command
      in .walk?       then dash direction
      in .open_door?  then act Pending::Open, direction
      in .close_door? then act Pending::Close, direction
      in .break_door? then @game.perform Action::Break.new(direction); refresh
      in .pan_map?
        spot = direction.from @map.camera[0], @map.camera[1]
        scroll_map_to spot[0], spot[1]
      in .explore?, .travel?, .visit?, .ascend?, .descend?, .wait?, .rest?,
         .equip?, .remove?, .inventory?, .pick_up?, .drop?, .drink?, .read?,
         .zap?, .apply?, .throw?, .spike_door?, .fire?, .fire_nearest?,
         .examine?, .recenter?, .history?, .focus_next?, .focus_previous?,
         .focus_map?, .focus_info?, .focus_log?, .options?, .theme?,
         .toggle_mouse?, .help?, .whats_new?, .save_quit?, .replay_toggle?,
         .replay_forward?, .replay_back?, .replay_faster?, .replay_slower?,
         .replay_go_to?, .debug_console?
        nil
      end
    end

    private def commit_modern_target(command : Command, choice : ModernChoice) : Nil
      item_id = choice.item_id
      coordinate = choice.coordinate
      direction = choice.direction
      slot = choice.slot
      cancel_frame = read_return_frame(command, item_id)
      cancel_stack = @modern_stack.dup
      clear_modern_menu
      @modern_cancel_frame = cancel_frame
      @modern_cancel_stack = cancel_stack if cancel_frame

      case command
      in .pick_up? then commit_modern_pick_up item_id
      in .equip?   then commit_modern_equip item_id
      in .remove?  then commit_modern_remove slot
      in .drop?    then commit_modern_drop item_id
      in .drink?   then commit_modern_drink item_id
      in .read?    then commit_modern_read item_id
      in .zap?     then commit_modern_zap item_id
      in .throw?   then commit_modern_throw item_id
      in .apply?, .spike_door?
        apply_modern_target item_id, coordinate
      in .open_door?
        act Pending::Open, direction if direction
      in .close_door?
        act Pending::Close, direction if direction
      in .break_door?
        @game.perform Action::Break.new(direction) if direction
        refresh
      in .fire?, .fire_nearest? then fire_at_nearest
      in .visit?                then visit
      in .ascend?               then ascend
      in .descend?              then descend
      in .walk?, .travel?, .explore?, .wait?, .rest?, .inventory?,
         .examine?, .pan_map?, .recenter?, .history?, .focus_next?,
         .focus_previous?, .focus_map?, .focus_info?, .focus_log?, .options?,
         .theme?, .toggle_mouse?, .help?, .whats_new?, .save_quit?,
         .replay_toggle?, .replay_forward?, .replay_back?, .replay_faster?,
         .replay_slower?, .replay_go_to?, .debug_console?
        nil
      end
    end

    private def commit_modern_pick_up(item_id : Int32?) : Nil
      if item_id && @game.here.any? { |item| item.id == item_id }
        action = @game.here.size == 1 ? Action::PickUp.new : Action::PickUp.new(item_id)
        @game.perform action
      end
      refresh
    end

    private def commit_modern_equip(item_id : Int32?) : Nil
      return unless letter = letter_for item_id

      wield_at letter
      refresh
    end

    private def commit_modern_remove(slot : Slot?) : Nil
      @game.perform Action::Remove.new(slot) if slot
      refresh
    end

    private def commit_modern_drop(item_id : Int32?) : Nil
      @game.perform Action::Drop.new(item_id) if item_id
      refresh
    end

    private def commit_modern_drink(item_id : Int32?) : Nil
      return unless letter = letter_for item_id

      quaff_at letter
      refresh
    end

    private def commit_modern_read(item_id : Int32?) : Nil
      return unless letter = letter_for item_id

      read_at letter
      @modern_cancel_frame = nil unless @menu.showing?
      @modern_cancel_stack.clear unless @modern_cancel_frame
      refresh
    end

    private def commit_modern_zap(item_id : Int32?) : Nil
      return unless letter = letter_for item_id

      zap_at letter
      refresh
    end

    private def commit_modern_throw(item_id : Int32?) : Nil
      letter_for(item_id).try { |letter| throw_at letter }
    end

    private def apply_modern_target(item_id : Int32?, coordinate : {Int32, Int32}?) : Nil
      target = @game.appliable.find do |candidate|
        candidate.letter ? candidate.letter.try { |letter| id_under(letter) == item_id } : candidate.aimed? && coordinate == {candidate.x, candidate.y}
      end
      if target
        @game.perform lighting(target)
      else
        say "That action is no longer available."
      end
      refresh
    end

    private def read_return_frame(command : Command, item_id : Int32?) : ModernMenuFrame?
      return unless command.read?
      return unless letter = letter_for item_id
      return unless @game.choice_needed?(letter)
      return if @game.marks_first?(letter) || @game.target_needed?(letter)
      return if @modern_mode.none?

      capture_modern_frame
    end

    private def capture_modern_frame : ModernMenuFrame
      selected = @selection_menu.selected_value
      item_id = if @modern_mode.targets?
                  @modern_item_id
                else
                  selected.try(&.item_id) || @modern_inventory_item
                end
      ModernMenuFrame.new(@modern_mode, @menu.page, @menu.selected_index,
        @modern_command, item_id, selected.try(&.slot), selected.try(&.character))
    end

    private def dispatch_modern(command : Command, item_id : Int32? = nil,
                                slot : Slot? = nil) : Nil
      clear_modern_menu
      case command
      in .walk?           then show_modern_directions command
      in .explore?        then explore
      in .travel?         then travel
      in .visit?          then visit
      in .ascend?         then ascend
      in .descend?        then descend
      in .wait?           then live_wait
      in .rest?           then rest
      in .equip?          then item_id.try { |id| letter_for(id).try { |letter| wield_at letter } }
      in .remove?         then @game.perform(Action::Remove.new(slot)) if slot
      in .inventory?      then show_modern_inventory
      in .pick_up?        then pick_up
      in .drop?           then item_id.try { |id| @game.perform Action::Drop.new(id) }
      in .drink?          then item_id.try { |id| letter_for(id).try { |letter| quaff_at letter } }
      in .read?           then item_id.try { |id| letter_for(id).try { |letter| read_at letter } }
      in .zap?            then item_id.try { |id| letter_for(id).try { |letter| zap_at letter } }
      in .apply?          then apply
      in .throw?          then item_id.try { |id| letter_for(id).try { |letter| throw_at letter } }
      in .open_door?      then open_door
      in .close_door?     then close_door
      in .spike_door?     then apply
      in .break_door?     then say "There is no known stuck door to break."
      in .fire?           then fire
      in .fire_nearest?   then fire_at_nearest
      in .examine?        then toggle_examine
      in .pan_map?        then show_modern_directions command
      in .recenter?       then recenter
      in .history?        then toggle_history
      in .focus_next?     then @ring.next
      in .focus_previous? then @ring.previous
      in .focus_map?      then @ring.focus FocusRing::Panel::Map
      in .focus_info?     then @ring.focus FocusRing::Panel::Info
      in .focus_log?      then @ring.focus FocusRing::Panel::Log
      in .options?        then show_options
      in .theme?          then show_options(-> { @options_screen.show_theme_editor(application); nil })
      in .toggle_mouse?   then @on_mouse.try &.call
      in .help?           then @on_help.try &.call
      in .whats_new?      then show_news
      in .save_quit?      then confirm_quit
      in .replay_toggle?  then toggle_playback
      in .replay_forward? then view_forward
      in .replay_back?    then view_back
      in .replay_faster?  then view_faster
      in .replay_slower?  then view_slower
      in .replay_go_to?   then ask_for_turn
      in .debug_console?  then toggle_console
      end
    end

    private def show_inventory_values : Nil
      wanted_item = @modern_inventory_item
      @modern_mode = ModernMenuKind::Inventory
      @selection_menu.navigation = Widgets::Navigation.selectable
      @modern_inventory_page = @modern_inventory_page.clamp(0, PACK_CLASSES.size)
      held = @game.player.inventory.entries
      pages = [{EVERYTHING, inventory_entries(held)}]
      PACK_CLASSES.each do |name|
        entries = held.select { |(_letter, item)| Play.pack_class(item.kind.item_class) == name }
        rows = inventory_entries entries
        rows << value_entry(ModernChoice.new(ModernChoiceKind::Empty), "Nothing in this category",
          enabled: false) if rows.empty?
        pages << {name, rows}
      end
      if pages[0][1].empty?
        pages[0][1] << value_entry(ModernChoice.new(ModernChoiceKind::Empty), "You are carrying nothing",
          enabled: false)
      end
      @selection_menu.on_choose = ->(choice : ModernChoice) { choose_modern_choice choice }
      @selection_menu.on_back = -> { back_modern_menu; nil }
      @selection_menu.on_highlight = ->(choice : ModernChoice?) do
        @modern_inventory_item = choice.try(&.item_id) if choice.try(&.kind.item?)
        @modern_inventory_page = @menu.page
        @modern_inventory_index = @menu.selected_index
        nil
      end
      @selection_menu.show application, "Inventory", pages, @modern_inventory_page
      @modern_inventory_item = wanted_item
      restored = restore_inventory_selection
      unless restored
        @selection_menu.select_index [@modern_inventory_index || 0, @menu.entries.size - 1].min
      end
    end

    private def inventory_entries(held : Array({Char, Item}))
      held.map do |(letter, item)|
        slot = @game.slot_of letter
        named = Naming.listed @game.lore, item
        mark = Palette.blessing(item)
        tail = Play.tail_of item, slot
        value_entry ModernChoice.new(ModernChoiceKind::Item, item_id: item.id, slot: slot),
          named, mark: mark.try(&.glyph), mark_style: mark.try(&.style),
          tail: tail.try(&.glyph), tail_style: tail.try(&.style)
      end
    end

    private def restore_inventory_selection : Bool
      wanted = @modern_inventory_item
      return false unless wanted
      choice = ModernChoice.new(ModernChoiceKind::Item, item_id: wanted,
        slot: selected_inventory_slot(wanted))
      @selection_menu.restore_value choice, page: @modern_inventory_page
    end

    private def show_item_actions(item_id : Int32) : Nil
      return if @viewer

      push_modern_frame unless @modern_mode.item_actions? || @modern_mode.none?
      @modern_inventory_item = item_id
      @modern_mode = ModernMenuKind::ItemActions
      @selection_menu.navigation = Widgets::Navigation.selectable
      @modern_item_id = item_id
      context = command_context(item_id)
      metadata = Commands.available context
      rows = metadata.map do |entry|
        value_entry ModernChoice.new(ModernChoiceKind::Command, command: entry.id,
          item_id: item_id), "#{entry.label} — #{entry.description}"
      end
      rows << value_entry(ModernChoice.new(ModernChoiceKind::Empty), "No actions are available for this item",
        enabled: false) if rows.empty?
      @selection_menu.on_choose = ->(choice : ModernChoice) { choose_modern_choice choice }
      @selection_menu.on_back = -> { back_modern_menu; nil }
      item = item_for item_id
      title = item ? Naming.listed(@game.lore, item) : "Item actions"
      @selection_menu.show application, title, rows
    end

    private def show_slot_actions(slot : Slot) : Nil
      context = command_context(slot: slot)
      metadata = Commands.available context
      rows = metadata.map do |entry|
        value_entry ModernChoice.new(ModernChoiceKind::Command, command: entry.id, slot: slot),
          "#{entry.label} — #{entry.description}"
      end
      rows << value_entry(ModernChoice.new(ModernChoiceKind::Empty), "No actions are available for this slot",
        enabled: false) if rows.empty?
      @modern_stack.clear
      @modern_mode = ModernMenuKind::ItemActions
      @selection_menu.navigation = Widgets::Navigation.selectable
      @selection_menu.on_choose = ->(choice : ModernChoice) { choose_modern_choice choice }
      @selection_menu.on_back = -> { back_modern_menu; nil }
      @selection_menu.show application, "Equipment actions", rows
    end

    private def push_modern_frame : Nil
      return if @modern_mode.none?

      selected = @selection_menu.selected_value
      item_id = @modern_mode.inventory? ? selected.try(&.item_id) : @modern_inventory_item
      @modern_stack << ModernMenuFrame.new(@modern_mode, @menu.page,
        @menu.selected_index, @modern_command, item_id,
        selected.try(&.slot), selected.try(&.character))
    end

    private def back_modern_menu : Nil
      if frame = @modern_stack.pop?
        restore_modern_frame frame
      else
        old_mode = @modern_mode
        clear_modern_menu
        @modern_mode = ModernMenuKind::None
        show_title if old_mode.title?
        refresh
      end
    end

    private def restore_modern_frame(frame : ModernMenuFrame) : Nil
      @modern_command = frame.command
      @modern_inventory_item = frame.item_id if frame.item_id
      @modern_item_id = frame.item_id
      case frame.kind
      in .catalog?, .available? then show_command_catalog frame.kind
      in .inventory?            then show_inventory_values
      in .item_actions?
        if item_id = frame.item_id
          show_item_actions item_id
        else
          show_slot_actions frame.slot || Slot::Melee
        end
      in .targets?
        command = frame.command
        if command
          status = Commands.status command, command_context(@modern_item_id)
          show_modern_targets command, status.targets
        end
      in .directions? then show_modern_directions(frame.command || Command::Walk)
      in .title?      then show_modern_title
      in .none?       then clear_modern_menu
      end
      if frame.kind.inventory? && frame.item_id
        @modern_inventory_page = frame.page
        restore_inventory_selection
      else
        @selection_menu.restore_selection(frame.index || 0, page: frame.page)
      end
    end

    private def finish_modern_read_choice(key : Char?) : Nil
      if key.nil?
        frame = @modern_cancel_frame
        if frame
          @modern_stack = @modern_cancel_stack.dup
          @modern_cancel_frame = nil
          @modern_cancel_stack.clear
          restore_modern_frame frame
        end
      else
        @modern_cancel_frame = nil
        @modern_cancel_stack.clear
      end
    end

    private def clear_modern_menu : Nil
      @modern_mode = ModernMenuKind::None
      @modern_command = nil
      @modern_item_id = nil
      @modern_stack.clear
    end

    private def selected_panel_item_id : Int32?
      return unless @ring.current.info?
      row = @info_panel.selected_row
      return unless row

      index = @character.pack.index(&.same?(row))
      index ? @game.player.inventory.entries[index]?.try(&.[1].id) : nil
    end

    private def selected_panel_slot : Slot?
      return unless @ring.current.info?
      row = @info_panel.selected_row
      return unless row

      Slot.listed.find { |slot| @character.slot_row(slot).same?(row) }
    end

    private def item_for(item_id : Int32?) : Item?
      return unless item_id

      @game.player.inventory.each_item do |_letter, item|
        return item if item.id == item_id
      end
      @game.here.find { |item| item.id == item_id }
    end

    private def letter_for(item_id : Int32?) : Char?
      return unless item_id

      @game.player.inventory.each_item do |letter, item|
        return letter if item.id == item_id
      end
      nil
    end

    private def selected_inventory_slot(item_id : Int32) : Slot?
      letter_for(item_id).try { |letter| @game.slot_of letter }
    end
  end
end
