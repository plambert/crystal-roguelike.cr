require "../../crystal-roguelike"

module Roguelike::Ui
  # The bindings that belong to the whole application.
  #
  # This module sits apart from `Session`. `Session` owns a terminal. This
  # module owns none. A spec builds an `App` over a buffer, installs these
  # bindings, and sends synthetic key events.
  #
  # Each set is built on its own. A caller merges whichever sets apply. A spec
  # installs only the set it is about.
  module Keys
    # The eight keys that move.
    #
    # NetHack made this layout standard. `hjkl` are the cardinals. `yubn` are
    # the corners. Each key sits on the keyboard where its direction points.
    #
    # These keys are bound once. Whatever is listening decides what they move.
    # The examine cursor moves while it is on the map. The character moves
    # otherwise.
    MOVES = {
      "h" => Direction::West,
      "j" => Direction::South,
      "k" => Direction::North,
      "l" => Direction::East,
      "y" => Direction::NorthWest,
      "u" => Direction::NorthEast,
      "b" => Direction::SouthWest,
      "n" => Direction::SouthEast,
    }

    # A group of keys with a name, which is how the help screen shows them.
    #
    # *notes* are rows the help screen shows after the bindings, each a key
    # and what it does. They are for keys a menu answers while it is up.
    # Nothing binds them here.
    record Section, title : String, bindings : Widgets::Bindings,
      notes : Array({String, String}) = [] of {String, String}

    # Keeps caller bindings while replacing the profile-owned sets.
    class Installer
      private property app : Widgets::App? = nil
      private property base : Widgets::Bindings = Widgets::Bindings.new
      private property owned_sequences : Array(Array(TermBuf::Key)) = [] of Array(TermBuf::Key)

      def install(app : Widgets::App, owned : Widgets::Bindings) : Nil
        if current = @app
          if current.same?(app)
            @base = @base.merge without_owned(app.keymap)
          else
            @base = app.keymap
            @owned_sequences.clear
          end
        else
          @base = app.keymap
        end

        @app = app
        @owned_sequences = owned.bindings.map(&.keys)
        app.keymap = @base.merge owned
      end

      private def without_owned(bindings : Widgets::Bindings) : Widgets::Bindings
        kept = Widgets::Bindings.new
        bindings.bindings.each do |binding|
          kept.bind binding unless @owned_sequences.includes? binding.keys
        end
        kept
      end
    end

    # Binds the application's own keys on *app*, and every section of *play*,
    # and puts the help screen on `F1` and `?`. Answers the help screen.
    #
    # The application's own group is first: leaving, help, examining and
    # taking back what is waiting. *on_quit* runs when the player asks to
    # leave, and *on_mouse* when they turn the mouse on or off. Each is the
    # caller's, because what either means depends on what owns the loop.
    def self.install(app : Widgets::App, help : Help = Help.new, play : Play? = nil,
                     on_mouse : Proc(Nil)? = nil,
                     kitty_keyboard : Bool = false,
                     installer : Installer = Installer.new, &on_quit : -> Nil) : Help
      play.try(&.kitty_keyboard=(kitty_keyboard))
      scheme = play.try(&.control_scheme) ||
               (Options.current || Options.new).effective_control_scheme
      own = application(scheme, play, &on_quit).merge(helping(help, app))
      if play && scheme.traditional?
        own = own.merge(Keys.examining(play)).merge(Keys.preferring(play))
      end
      sections = [Section.new("application", own)]
      sections.concat play.sections if play
      sections << Section.new("mouse", mousing(&on_mouse)) if on_mouse

      help.sections = sections
      help.first = -> { play.try { |game| Help.title_for game.ring.current } } if play
      all = sections.reduce(Widgets::Bindings.new) { |bindings, section| bindings.merge section.bindings }
      all = all.merge play.unlisted if play
      installer.install app, all
      help
    end

    # The movement bindings in *bindings*, by the direction each moves, or
    # nothing when none of them move. The help screen draws these as a
    # diagram rather than as rows.
    def self.directions(bindings : Widgets::Bindings) : Hash(Direction, String)
      found = {} of Direction => String
      bindings.bindings.each do |binding|
        Direction.each do |direction|
          found[direction] = binding.to_s if binding.description == "move #{direction.label}"
        end
      end
      found
    end

    # `F1` and `?` put *help* up.
    def self.helping(help : Help, app : Widgets::App) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        {"F1", "?"}.each do |key|
          map.bind TermBuf::Key.parse(key), "show the keys that work here",
            ->(_context : Widgets::Context) { help.open app; nil }
        end
      end
    end

    # What the application answers after every widget declines a key.
    def self.application(scheme : Options::ControlScheme = Options::ControlScheme::Traditional,
                         play : Play? = nil, &on_quit : -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        if scheme.traditional?
          map.bind TermBuf::Key.parse("Q"), "leave the game",
            ->(_context : Widgets::Context) { on_quit.call; nil }
        end
        if play
          map.bind TermBuf::Key.parse("F2"), "open the action catalog",
            ->(_context : Widgets::Context) { play.show_action_catalog; nil }
        end
      end
    end

    # The eight movement keys. Each passes its direction to *on_move*.
    def self.moving(&on_move : Direction -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        MOVES.each do |key, direction|
          map.bind TermBuf::Key.parse(key), "move #{direction.label}",
            ->(_context : Widgets::Context) { on_move.call direction; nil }
        end
      end
    end

    # `x` puts the examine cursor on the map and takes it off again.
    def self.examining(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("x"), "look at a square",
          ->(_context : Widgets::Context) { play.toggle_examine; nil }
      end
    end

    # `O` opens the options screen.
    def self.preferring(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("O"), "change the options",
          ->(_context : Widgets::Context) { play.show_options; nil }
      end
    end

    # The keys the options screen answers while it is up.
    #
    # The form binds the arrows, `Tab`, `Home`, `End`, the page keys and
    # `Enter`, and each row's input binds its own. The notes list those. The
    # bindings here add the letters and `Escape`. A row that takes text gets
    # a letter or `?` it takes as typing, as a number row takes a digit.
    def self.options_screen(screen : OptionsScreen, app : Widgets::App) : Section
      bindings = Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Escape"), "close the options",
          ->(_context : Widgets::Context) { screen.dismiss; nil }
        map.bind TermBuf::Key.parse("F1"), "show the keys that work here",
          ->(_context : Widgets::Context) { screen.show_help app; nil }
        map.bind TermBuf::Key.parse("?"), "show the keys that work here",
          ->(context : Widgets::Context) { screen.show_help app unless screen.typed? context; nil }
        if screen.modern_controls?
          map.bind TermBuf::Key.parse("f"), "activate the focused row",
            ->(context : Widgets::Context) { screen.activate context; nil }
          map.bind TermBuf::Key.parse("s"), "the row below",
            ->(context : Widgets::Context) { screen.step 1, context; nil }
          map.bind TermBuf::Key.parse("w"), "the row above",
            ->(context : Widgets::Context) { screen.step(-1, context); nil }
          map.bind TermBuf::Key.parse("a"), "the choice before, or a step down",
            ->(context : Widgets::Context) { screen.turn(-1, context); nil }
          map.bind TermBuf::Key.parse("d"), "the choice after, or a step up",
            ->(context : Widgets::Context) { screen.turn 1, context; nil }
        else
          map.bind TermBuf::Key.parse("j"), "the row below",
            ->(context : Widgets::Context) { screen.step 1, context; nil }
          map.bind TermBuf::Key.parse("k"), "the row above",
            ->(context : Widgets::Context) { screen.step(-1, context); nil }
          map.bind TermBuf::Key.parse("h"), "the choice before, or a step down",
            ->(context : Widgets::Context) { screen.turn(-1, context); nil }
          map.bind TermBuf::Key.parse("l"), "the choice after, or a step up",
            ->(context : Widgets::Context) { screen.turn 1, context; nil }
        end
      end

      notes = [
        {screen.modern_controls? ? "W S Up Down" : "Up Down", "the row above or below"},
        {"Tab Shift+Tab", "the next or the previous row"},
        {screen.modern_controls? ? "f Space Enter" : "Space Enter", "activate a row, turn a toggle, or take the next choice"},
        {screen.modern_controls? ? "A D Left Right" : "Left Right", "the choice before or after, or step a number"},
        {"Home End", "the first or the last row"},
        {"PageUp PageDown", "a screenful up or down"},
      ]

      Section.new "options", bindings, notes
    end

    # The keys the theme editor answers while it is up.
    #
    # The form binds the arrows, `Tab`, `Home`, `End`, the page keys and
    # `Enter`, and a color row opens its picker on `Enter` and `Space`. The
    # bindings here add the letters and `Escape`.
    def self.theme_editor(editor : ThemeEditor, app : Widgets::App) : Section
      bindings = Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Escape"), "back to the options",
          ->(_context : Widgets::Context) { editor.dismiss; nil }
        map.bind TermBuf::Key.parse("F1"), "show the keys that work here",
          ->(_context : Widgets::Context) { editor.show_help app; nil }
        map.bind TermBuf::Key.parse("?"), "show the keys that work here",
          ->(_context : Widgets::Context) { editor.show_help app; nil }
        if editor.modern_controls?
          map.bind TermBuf::Key.parse("f"), "activate the focused row",
            ->(context : Widgets::Context) { editor.activate context; nil }
          map.bind TermBuf::Key.parse("s"), "the row below",
            ->(context : Widgets::Context) { editor.step 1, context; nil }
          map.bind TermBuf::Key.parse("w"), "the row above",
            ->(context : Widgets::Context) { editor.step(-1, context); nil }
          map.bind TermBuf::Key.parse("a"), "the first row of the group above",
            ->(context : Widgets::Context) { editor.leap(-1, context); nil }
          map.bind TermBuf::Key.parse("d"), "the first row of the group below",
            ->(context : Widgets::Context) { editor.leap 1, context; nil }
        else
          map.bind TermBuf::Key.parse("j"), "the row below",
            ->(context : Widgets::Context) { editor.step 1, context; nil }
          map.bind TermBuf::Key.parse("k"), "the row above",
            ->(context : Widgets::Context) { editor.step(-1, context); nil }
          map.bind TermBuf::Key.parse("h"), "the first row of the group above",
            ->(context : Widgets::Context) { editor.leap(-1, context); nil }
          map.bind TermBuf::Key.parse("l"), "the first row of the group below",
            ->(context : Widgets::Context) { editor.leap 1, context; nil }
          map.bind TermBuf::Key.parse("r"), "put this color back to the game's own",
            ->(_context : Widgets::Context) { editor.reset_row; nil }
        end
      end

      notes = [
        {editor.modern_controls? ? "W S Up Down" : "Up Down", "the row above or below"},
        {"Tab Shift+Tab", "the next or the previous row"},
        {editor.modern_controls? ? "f Enter Space" : "Enter Space", "choose a color, or activate a reset action"},
        {editor.modern_controls? ? "A D" : "H L", "the first row of the group above or below"},
        {"Home End", "the first or the last row"},
        {"PageUp PageDown", "a screenful up or down"},
      ]

      Section.new "color theme", bindings, notes
    end

    # `Tab` and `Shift+Tab` move the focus among the map, the info panel and
    # the log. `Escape` gives it back to the map, and on the map it takes
    # back whatever is waiting.
    #
    # `Tab` aims at the next monster while something is being aimed. An
    # overlay pushes a focus scope with its own keys, so none of these
    # reach the panels while one is up.
    def self.panels(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Tab"), "focus the next panel, or aim at the next monster",
          ->(_context : Widgets::Context) { play.tab; nil }
        map.bind TermBuf::Key.parse("Shift+Tab"), "focus the previous panel",
          ->(_context : Widgets::Context) { play.tab_back; nil }
        map.bind TermBuf::Key.parse("Escape"), "back to the map, or stop what is waiting",
          ->(_context : Widgets::Context) { play.escape; nil }
      end
    end

    # The scrolling keys of the map, and `Enter` for it.
    #
    # `Shift+Up` and `Shift+Down` scroll a row, `Shift+Left` and
    # `Shift+Right` a column, `PageUp` and `PageDown` a page, and `Home` and
    # `End` go to the top and bottom of the floor. Every panel binds the
    # same keys, and `Play` acts on the panel with the focus.
    #
    # `Enter` looses the shot or walks to the square a pick is waiting on.
    # With nothing waiting, it brings the character into view when they are
    # off screen.
    def self.map_panel(play : Play) : Widgets::Bindings
      own = Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Shift+Left"), "scroll the map left a column",
          ->(_context : Widgets::Context) { play.scroll_columns(-1); nil }
        map.bind TermBuf::Key.parse("Shift+Right"), "scroll the map right a column",
          ->(_context : Widgets::Context) { play.scroll_columns(1); nil }
        map.bind TermBuf::Key.parse("Enter"),
          "fire, walk to the square, or find the character",
          ->(_context : Widgets::Context) { play.enter; nil }
      end

      scrolling(play, "the map", "the top of the floor", "the bottom of the floor").merge own
    end

    # The scrolling keys of the info panel, and the keys that move its
    # selection.
    #
    # `Up` and `Down` move among the section headers and the rows of an
    # open section. `Left` and `Right` close and open the selected section,
    # and go out of its rows and into them. `Enter` does what a click on the
    # selection does. `Play` answers these for the focused panel, so the
    # replay viewer's `Left` and `Right` go through the same methods.
    def self.info_panel(play : Play) : Widgets::Bindings
      own = Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Up"), "select the section or row above",
          ->(_context : Widgets::Context) { play.up; nil }
        map.bind TermBuf::Key.parse("Down"), "select the section or row below",
          ->(_context : Widgets::Context) { play.down; nil }
        map.bind TermBuf::Key.parse("Left"), "close the section, or go back to its header",
          ->(_context : Widgets::Context) { play.left; nil }
        map.bind TermBuf::Key.parse("Right"), "open the section, or go into its rows",
          ->(_context : Widgets::Context) { play.right; nil }
        map.bind TermBuf::Key.parse("Enter"), "do what a click on the selection does",
          ->(_context : Widgets::Context) { play.enter; nil }
        if play.modern_controls?
          map.bind TermBuf::Key.parse("w"), "select the row above",
            ->(_context : Widgets::Context) { play.up; nil }
          map.bind TermBuf::Key.parse("s"), "select the row below",
            ->(_context : Widgets::Context) { play.down; nil }
          map.bind TermBuf::Key.parse("a"), "close the section or go back",
            ->(_context : Widgets::Context) { play.left; nil }
          map.bind TermBuf::Key.parse("d"), "open the section or enter its rows",
            ->(_context : Widgets::Context) { play.right; nil }
        end
      end

      scrolling(play, "the info panel", "the top of the panel", "the bottom of the panel").merge own
    end

    # The scrolling keys of the log, and `Enter` for it.
    #
    # `Space` pages the log down whichever panel has the focus. It takes no
    # turn. A recorded run keeps `Space` for its transport.
    def self.log_panel(play : Play) : Widgets::Bindings
      own = Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Enter"), "scroll to the newest message",
          ->(_context : Widgets::Context) { play.enter; nil }

        unless play.viewer
          map.bind TermBuf::Key.parse("Space"), "page the log down, from any panel",
            ->(_context : Widgets::Context) { play.page_log; nil }
        end
      end

      scrolling(play, "the log", "the oldest message", "the newest message").merge own
    end

    # The keys every panel scrolls by. *what* names the panel, and *top* and
    # *bottom* say where `Home` and `End` go in it.
    private def self.scrolling(play : Play, what : String, top : String,
                               bottom : String) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Shift+Up"), "scroll #{what} up a row",
          ->(_context : Widgets::Context) { play.scroll_rows(-1); nil }
        map.bind TermBuf::Key.parse("Shift+Down"), "scroll #{what} down a row",
          ->(_context : Widgets::Context) { play.scroll_rows(1); nil }
        map.bind TermBuf::Key.parse("PageUp"), "scroll #{what} up a page",
          ->(_context : Widgets::Context) { play.scroll_pages(-1); nil }
        map.bind TermBuf::Key.parse("PageDown"), "scroll #{what} down a page",
          ->(_context : Widgets::Context) { play.scroll_pages(1); nil }
        map.bind TermBuf::Key.parse("Home"), "go to #{top}",
          ->(_context : Widgets::Context) { play.scroll_to_edge(false); nil }
        map.bind TermBuf::Key.parse("End"), "go to #{bottom}",
          ->(_context : Widgets::Context) { play.scroll_to_edge(true); nil }
      end
    end

    # `.` waits, `G` runs and `R` rests.
    def self.timing(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("."), "wait a turn",
          ->(_context : Widgets::Context) { play.live_wait; nil }
        if play.kitty_keyboard?
          map.bind TermBuf::Key.parse("Shift+Space"), "wait a turn",
            ->(_context : Widgets::Context) { play.live_wait; nil }
        end
        map.bind TermBuf::Key.parse("G"), "run until something stops you",
          ->(_context : Widgets::Context) { play.start_running; nil }
        map.bind TermBuf::Key.parse("R"), "rest until you are healed",
          ->(_context : Widgets::Context) { play.rest; nil }
      end
    end

    # `X` explores and `_` picks a square to walk to. `v` walks to what the
    # last explore stopped for.
    #
    # `x` is the examine key, so explore takes the capital.
    def self.exploring(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("X"), "explore until something stops you",
          ->(_context : Widgets::Context) { play.explore; nil }
        map.bind TermBuf::Key.parse("_"), "pick a square and walk there",
          ->(_context : Widgets::Context) { play.travel; nil }
        map.bind TermBuf::Key.parse("v"), "walk to what explore stopped for",
          ->(_context : Widgets::Context) { play.visit; nil }
      end
    end

    # `o` opens a door. `c` closes one, or spikes a shut one. `<` and `>`
    # take a staircase.
    #
    # *play* answers each of these. A door needs a direction, and `Play` finds
    # it or asks for it.
    def self.passing(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("o"), "open a door",
          ->(_context : Widgets::Context) { play.open_door; nil }
        map.bind TermBuf::Key.parse("c"), "close or spike a door",
          ->(_context : Widgets::Context) { play.close_door; nil }
        map.bind TermBuf::Key.parse(">"), "go down the staircase",
          ->(_context : Widgets::Context) { play.descend; nil }
        map.bind TermBuf::Key.parse("<"), "climb out of the dungeon",
          ->(_context : Widgets::Context) { play.ascend; nil }
      end
    end

    # What the character wields and wears.
    def self.wearing(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("w"), "wield a weapon or wear armor",
          ->(_context : Widgets::Context) { play.wield; nil }
        map.bind TermBuf::Key.parse("T"), "take something off",
          ->(_context : Widgets::Context) { play.take_off; nil }
      end
    end

    # Keys that do what a listed key does and are left off the help screen.
    #
    # `W` once wore armor. It now does what `w` does.
    def self.unlisted(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("W"), "wield a weapon or wear armor",
          ->(_context : Widgets::Context) { play.wield; nil }
      end
    end

    # The pack, and what is done with the things in it.
    def self.handling(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("i"), "look at what you are carrying",
          ->(_context : Widgets::Context) { play.show_inventory; nil }
        map.bind TermBuf::Key.parse(","), "pick up what is here",
          ->(_context : Widgets::Context) { play.pick_up; nil }
        map.bind TermBuf::Key.parse("d"), "drop something",
          ->(_context : Widgets::Context) { play.drop; nil }
        map.bind TermBuf::Key.parse("q"), "drink a potion",
          ->(_context : Widgets::Context) { play.quaff; nil }
        map.bind TermBuf::Key.parse("r"), "read a scroll",
          ->(_context : Widgets::Context) { play.read; nil }
        map.bind TermBuf::Key.parse("z"), "zap a wand",
          ->(_context : Widgets::Context) { play.zap; nil }
        map.bind TermBuf::Key.parse("a"), "light or put out a flame",
          ->(_context : Widgets::Context) { play.apply; nil }
      end
    end

    # The keys the inventory answers while it is up, and the keys of the menu
    # an item's letter puts up.
    #
    # The menu does not bind these globally. They are listed so a person
    # reading the help screen can find them.
    def self.in_the_pack : Section
      actions = Play::Handle.values
      notes = [
        {"a-z A-Z", "what to do with that item"},
        {"Left Right", "show one class of item at a time"},
        {actions.join(" ", &.key), actions.join(", ", &.label)},
      ]

      Section.new "in the inventory", Widgets::Bindings.new, notes
    end

    # The message history.
    def self.reading(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse(HistoryPane::TOGGLE), "read the messages again",
          ->(_context : Widgets::Context) { play.toggle_history; nil }
      end
    end

    # `f` fires, `F` fires at the nearest monster, and `t` throws. `Tab` aims
    # at the next monster, and `.panels` binds it. `Enter` looses the shot, or
    # walks to the square `_` picked, and `.map_panel` binds it.
    #
    # The movement keys are already bound, and `Play` sends them to the
    # targeting cursor the same way it sends them to the examine cursor.
    def self.aiming(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("f"), "fire the readied ranged weapon",
          ->(_context : Widgets::Context) { play.fire; nil }
        map.bind TermBuf::Key.parse("F"), "fire at the nearest monster",
          ->(_context : Widgets::Context) { play.fire_at_nearest; nil }
        map.bind TermBuf::Key.parse("t"), "throw something",
          ->(_context : Widgets::Context) { play.throw; nil }
      end
    end

    # The keys that drive a recorded run.
    #
    # `Play#sections` offers these instead of the groups that take turns
    # while `replay view` is up. Nothing here takes a turn. Each key moves
    # the run through actions the file already holds.
    def self.viewing(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Space"), "play the run, or stop it",
          ->(_context : Widgets::Context) { play.toggle_playback; nil }
        map.bind TermBuf::Key.parse("Right"), "one action forward",
          ->(_context : Widgets::Context) { play.right; nil }
        map.bind TermBuf::Key.parse("Left"), "one action back",
          ->(_context : Widgets::Context) { play.left; nil }
        map.bind TermBuf::Key.parse("g"), "go to a turn",
          ->(_context : Widgets::Context) { play.ask_for_turn; nil }
        map.bind TermBuf::Key.parse("+"), "one speed faster",
          ->(_context : Widgets::Context) { play.view_faster; nil }
        map.bind TermBuf::Key.parse("-"), "one speed slower",
          ->(_context : Widgets::Context) { play.view_slower; nil }

        Play::VIEW_SPEEDS.each_index do |index|
          speed = index + 1
          map.bind TermBuf::Key.parse(speed.to_s), "play at speed #{speed}",
            ->(_context : Widgets::Context) { play.view_speed = speed; nil }
        end
      end
    end

    # `` ` `` puts the debug console up and takes it down.
    #
    # `Play` merges this only when it has a console, so the key is unbound in
    # a run started without `--debug-console`.
    def self.debugging(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse(ConsolePane::TOGGLE), "open the debug console",
          ->(_context : Widgets::Context) { play.toggle_console; nil }
      end
    end

    # Modern controls, with movement confined to the map and navigation
    # delegated to the focused information or message panel.
    def self.modern_sections(play : Play) : Array(Section)
      if play.viewer
        return [
          Section.new("panels", Keys.panels(play)),
          Section.new("map", Keys.map_panel(play)),
          Section.new("info panel", Keys.info_panel(play)),
          Section.new("log", Keys.log_panel(play)),
          Section.new("moving", modern_moving(play, viewer: true)),
          Section.new("actions", modern_viewer_actions(play)),
          Section.new("playing the run", Keys.viewing(play)),
        ]
      end

      sections = [
        Section.new("panels", Keys.panels(play)),
        Section.new("map", Keys.map_panel(play)),
        Section.new("info panel", Keys.info_panel(play)),
        Section.new("log", Keys.log_panel(play)),
        Section.new("moving", modern_moving(play),
          [{"Shift+Q W E A D Z S X", "walk in that direction"}]),
        Section.new("actions", modern_actions(play)),
        Section.new("time", modern_timing(play)),
        Section.new("doors and stairs", modern_stairs(play)),
      ]
      sections << Section.new("debug", Keys.debugging(play)) if play.console
      sections
    end

    private def self.modern_moving(play : Play, viewer : Bool = false) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        Controls.moves(Options::ControlScheme::Modern).each do |key, direction|
          map.bind TermBuf::Key.parse(key), "move #{direction.label}",
            ->(_context : Widgets::Context) do
              if viewer
                play.view_move direction
              else
                play.modern_move direction
              end
              nil
            end
          next if viewer

          shifted_keys(key).each do |shifted|
            map.bind shifted, "walk #{direction.label}",
              ->(_context : Widgets::Context) { play.modern_walk(direction); nil }
          end
        end
      end
    end

    private def self.shifted_keys(key : String) : Array(TermBuf::Key)
      letter = key[0].upcase.to_s
      [
        TermBuf::Key.parse_one(letter),
        TermBuf::Key.parse_one("Shift+#{key}"),
        TermBuf::Key.parse_one("Shift+#{letter}"),
      ]
    end

    private def self.modern_actions(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("r"), "open the complete action catalog",
          ->(_context : Widgets::Context) { play.show_action_catalog; nil }
        map.bind TermBuf::Key.parse("f"), "open actions or confirm the target",
          ->(_context : Widgets::Context) { play.modern_available_action; nil }
        map.bind TermBuf::Key.parse("F"), "fire at the nearest monster",
          ->(_context : Widgets::Context) { play.modern_fire_at_nearest; nil }
        map.bind TermBuf::Key.parse("i"), "open inventory",
          ->(_context : Widgets::Context) { play.show_modern_inventory; nil }
        map.bind TermBuf::Key.parse("g"), "pick up what is here",
          ->(_context : Widgets::Context) { play.modern_pick_up; nil }
        map.bind TermBuf::Key.parse("Ctrl+X"), "explore until interrupted",
          ->(_context : Widgets::Context) { play.modern_explore; nil }
      end
    end

    private def self.modern_viewer_actions(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("r"), "open the replay action catalog",
          ->(_context : Widgets::Context) { play.show_action_catalog; nil }
        map.bind TermBuf::Key.parse("f"), "open currently available replay actions",
          ->(_context : Widgets::Context) { play.show_available_actions; nil }
        map.bind TermBuf::Key.parse("i"), "browse the read-only inventory",
          ->(_context : Widgets::Context) { play.show_modern_inventory; nil }
      end
    end

    private def self.modern_timing(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("."), "wait a turn",
          ->(_context : Widgets::Context) { play.live_wait; nil }
        if play.kitty_keyboard?
          map.bind TermBuf::Key.parse("Shift+Space"), "wait a turn",
            ->(_context : Widgets::Context) { play.live_wait; nil }
        end
      end
    end

    private def self.modern_stairs(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse(">"), "use or route to the stairs down",
          ->(_context : Widgets::Context) { play.modern_stair_down; nil }
        map.bind TermBuf::Key.parse("<"), "use or route to the stairs up",
          ->(_context : Widgets::Context) { play.modern_stair_up; nil }
      end
    end

    # `M` turns mouse reporting on and off.
    #
    # This is a toggle. A terminal reporting the mouse no longer lets the
    # person select and copy with it, so the two cannot both be had at
    # once.
    def self.mousing(&on_toggle : -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("M"), "turn the mouse on or off",
          ->(_context : Widgets::Context) { on_toggle.call; nil }
      end
    end
  end
end
