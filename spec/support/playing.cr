require "file_utils"
require "./headless"

# A `Roguelike::Ui::Play` over a buffer, wired the way `Session` wires it.
#
# `Session` owns a terminal. `Play` owns everything else. So this module is
# the whole game short of the device. It builds the same widget tree, the same
# keymap and the same mouse handling. A spec presses keys at the code the game
# runs. It does not press keys at a copy.
module Playing
  # The seed every spec uses. A spec may pass another. A failure then names a
  # run a person can start.
  SEED = 20260911_u64

  # One wired game, and everything a spec needs to drive it.
  class Run
    # The game and everything it draws.
    getter play : Roguelike::Ui::Play

    # The buffer the game draws into.
    getter session : Headless::Session

    # Every sequence the terminal would have been sent. Oldest first. The
    # pointer shapes arrive here.
    getter told : Array(String)

    def initialize(@play : Roguelike::Ui::Play,
                   @session : Headless::Session,
                   @told : Array(String))
    end

    # Whether the what's new screen is up.
    def news_page_open? : Bool
      @play.news_page.open?
    end

    delegate game, screen, map, examine, examiner, nearby, pointer, prompt, pager, menu,
      console, placard, entry, store, viewer, to: @play

    # Whether the run should end.
    def finished? : Bool
      @play.finished?
    end

    delegate render, rows, row, text, buffer, to: @session

    # Drives the clock. A run opened without one has nothing to drive.
    delegate tick, run_timers, armed, armed_for, to: @session

    # Where the character is.
    def at : {Int32, Int32}
      game.player.at
    end

    # What has just happened, oldest first.
    def log : Array(String)
      game.log.lines
    end

    # The most recent message.
    def said : String
      game.log.last? || ""
    end

    # How many turns have been taken.
    def turn : Int32
      game.turn
    end

    # Presses the keys *description* names.
    def press(description : String) : Nil
      @session.press description
      @session.render
    end

    # :ditto: Presses each in turn. A walk uses this.
    def press(*descriptions : String) : Nil
      descriptions.each { |description| press description }
    end

    # Types *text*, one character at a time, at whatever has the keyboard.
    #
    # `#press` parses its argument, so a space in it is a separator rather
    # than a keystroke. A console command has spaces in it.
    def type(text : String) : Nil
      text.each_char do |character|
        @session.send TermBuf::Events::Key.new(
          TermBuf::Key.character(character), Bytes.empty)
      end

      @session.render
    end

    # Where the cell *x*, *y* of the map pane is in the buffer.
    #
    # The map pane does not start at the buffer's origin. The info panel and
    # its rule are to the left of it.
    def on_map(x : Int32, y : Int32) : {Int32, Int32}
      box = screen.map.rect
      {box.x + x, box.y + y}
    end

    # Row *y* of the map pane, from its first column to the buffer's edge.
    def map_row(y : Int32) : String
      box = screen.map.rect
      row(box.y + y).ljust(box.right)[box.x..]
    end

    # A motion report with no button held over cell *x*, *y* of the map
    # pane.
    def hover_map(x : Int32, y : Int32) : Nil
      hover *on_map(x, y)
    end

    # The left button going down over cell *x*, *y* of the map pane.
    def click_map(x : Int32, y : Int32) : Nil
      click *on_map(x, y)
    end

    # A motion report with no button held. Mode 1003 sends these.
    def hover(x : Int32, y : Int32) : Nil
      @session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::None, x, y,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Motion)
      @session.render
    end

    # The left button going down at *x*, *y* of the buffer.
    def click(x : Int32, y : Int32) : Nil
      @session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, x, y,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)
      @session.render
    end

    # A report of *button* doing *action* at *x*, *y* of the buffer.
    def mouse(button : TermBuf::Input::Mouse::Button,
              action : TermBuf::Input::Mouse::Action,
              x : Int32, y : Int32) : Nil
      @session.send TermBuf::Events::Mouse.new(
        button, x, y, TermBuf::Modifiers::None, action)
      @session.render
    end

    # The right button going down at *from*, the pointer moving with it held
    # to *to*, and the button coming up there.
    def right_drag(from : {Int32, Int32}, to : {Int32, Int32}) : Nil
      right = TermBuf::Input::Mouse::Button::Right
      mouse right, TermBuf::Input::Mouse::Action::Press, *from
      mouse right, TermBuf::Input::Mouse::Action::Motion, *to
      mouse right, TermBuf::Input::Mouse::Action::Release, *to
    end

    # A wheel notch at *x*, *y* of the buffer. *up* rolls it back.
    def wheel(x : Int32, y : Int32, up : Bool = true) : Nil
      button = up ? TermBuf::Input::Mouse::Button::WheelUp : TermBuf::Input::Mouse::Button::WheelDown

      @session.send TermBuf::Events::Mouse.new(
        button, x, y, TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)
      @session.render
    end

    # Takes every creature off the floor.
    #
    # A spec about doors, drawing or the log is not about being chased.
    # Phase 19 gave every awake band a plan, and one of them walking into
    # the route is a different spec's subject.
    def clear_monsters : Nil
      game.floor.monsters.clear
      play.refresh
      @session.render
    end

    # Resizes the terminal under the game. Dragging a window does the
    # same.
    def resize(columns : Int32, rows : Int32) : Nil
      @session.resize columns, rows
      @play.fit columns, rows
      @session.render
    end
  end

  # A lit torch, for a spec that wants light without saying much about it.
  def self.torch : Roguelike::Item
    Roguelike::Item.new Roguelike::ItemKind::Torch, lit: true
  end

  # Lights every square of *floor*, and answers it.
  #
  # Phase 13 made a floor dark until somebody brings a light. A spec that is
  # not about light says this once and the floor reads the way it did before.
  def self.daylight(floor : Roguelike::Floor) : Roguelike::Floor
    floor.ambient = 1
    floor
  end

  # A game on one open room of *columns* by *rows*. The character starts in
  # the middle.
  #
  # The shipped floor has every door shut until phase 6 opens them. The
  # character cannot leave the room they start in. The camera never has to
  # move. A spec about walking a long way needs somewhere to walk.
  def self.field(columns : Int32 = 120, rows : Int32 = 60,
                 seed : UInt64 = SEED) : Roguelike::Game
    map = Array.new(rows) do |row|
      String.build(columns) do |line|
        columns.times do |column|
          edge = row.zero? || column.zero? || row == rows - 1 || column == columns - 1
          middle = row == rows // 2 && column == columns // 2
          line << (edge ? '#' : middle ? '<' : '.')
        end
      end
    end

    floor = daylight Roguelike::Floor.parse("field", map)
    world = Roguelike::World.new seed, {floor.id => floor}

    Roguelike::Game.new world,
      Roguelike::Player.new(floor.id, *Roguelike::Game.entrance(floor))
  end

  # A store on a directory of its own.
  #
  # Nothing a spec does is allowed to reach the person's own saved
  # characters, so `open` takes no store unless a spec names one, and this is
  # what a spec names.
  #
  # Every one goes when the specs are over.
  def self.store : Roguelike::Save::Store
    root = Path[File.tempname "roguelike-spec", nil]
    at_exit { @@stores.each { |made| FileUtils.rm_rf made.to_s } } if @@stores.empty?
    @@stores << root

    Roguelike::Save::Store.under root
  end

  @@stores = [] of Path

  # A run on *game*, drawn in a window of *columns* by *rows*.
  #
  # *title* puts the title screen up the way `Session` does. It is off by
  # default: a spec that is not about the title screen presses its first key
  # at the game rather than at a box asking to begin.
  #
  # *store* is where the run is saved. Nothing is saved without one.
  # *clock* gives the application timers a spec fires by hand. Without it
  # `App#after` arms nothing, and anything drawn on a timer happens inside the
  # call that started it. Most specs want that: they press a key and read what
  # it did.
  #
  # *motion* turns on the panels' animations. They are off otherwise, so a
  # fixture draws their end state.
  def self.open(game : Roguelike::Game? = nil,
                columns : Int32 = 80,
                rows : Int32 = 24,
                console : Bool = false,
                title : Bool = false,
                clock : Bool = false,
                store : Roguelike::Save::Store? = nil,
                news : Array(Roguelike::WhatsNew::Section) = [] of Roguelike::WhatsNew::Section,
                viewer : Roguelike::Replay::Viewer? = nil,
                motion : Bool = false,
                startup_controls : Bool = false,
                control_options : Roguelike::Options? = nil,
                options_root : Path? = nil,
                kitty_keyboard : Bool = false) : Run
    # A spec that builds its own run with `Game.new` has not numbered what is
    # in it. `Game.start`, `Game.dug` and a save read back all call `#enroll`,
    # and a hand-built floor has been through none of the three. `Ui::Play`
    # names an item by its id when it builds an action, so a run with no ids
    # would refuse every verb that names one.
    found = viewer
    wanted = found.try(&.game) || game || Roguelike::Game.start(Roguelike::Rng.new(SEED))
    wanted.enroll unless found

    play = Roguelike::Ui::Play.new wanted, console

    # The banner takes a row from the message pane, and the keymap below
    # reads the viewer. `Session` orders these the same way.
    play.view found if found

    play.store = store
    play.news = news
    play.fit columns, rows

    session = Headless.open play.root, columns, rows, motion
    session.clock if clock
    play.app = session.app
    told = [] of String

    help = Roguelike::Ui::Help.new wanted.world.seed
    Roguelike::Ui::Keys.install(session.app, help, play,
      kitty_keyboard: kitty_keyboard) { play.confirm_quit }
    play.on_help = -> { help.open session.app; nil }
    play.on_options = ->(options : Roguelike::Options) do
      options.apply
      play.controls_changed
      Roguelike::Ui::Keys.install(session.app, help, play,
        kitty_keyboard: kitty_keyboard) { play.confirm_quit }
      play.options_screen.rebind_controls session.app
      nil
    end
    session.app.on_event = ->(event : TermBuf::Event) do
      case event
      when TermBuf::Events::Mouse
        sequence = play.reported event
        told << sequence if sequence
      when TermBuf::Events::Focus
        play.map.idle = !event.focused
      end

      nil
    end

    # Nothing here ticks the flames on a timer, so every event may change
    # what the map shows. A click moves the focus first, as in `Session`.
    session.app.on_deliver = ->(event : TermBuf::Event) do
      play.map.forget_frames
      play.focus_under event
    end

    # One layout runs before the camera is pointed. `Session` does the
    # same.
    session.render
    play.look_at_player
    show_startup_controls startup_controls, control_options, options_root,
      kitty_keyboard, title, found, play, session.app, help
    session.render

    Run.new play, session, told
  end

  private def self.show_startup_controls(startup_controls : Bool,
                                         control_options : Roguelike::Options?,
                                         options_root : Path?,
                                         kitty_keyboard : Bool,
                                         title : Bool,
                                         viewer : Roguelike::Replay::Viewer?,
                                         play : Roguelike::Ui::Play,
                                         app : TermBuf::Widgets::ObservedApp,
                                         help : Roguelike::Ui::Help) : Nil
    options = control_options || Roguelike::Options.new
    unless startup_controls && Roguelike::Ui::ControlSchemeSetup.needed?(options)
      play.show_title if title && viewer.nil?
      return
    end

    Roguelike::Options.current = options
    setup = Roguelike::Ui::ControlSchemeSetup.new(options_root || Roguelike::Submit.root)
    setup.on_change = ->(changed : Roguelike::Options) do
      Roguelike::Options.current = changed
      play.controls_changed
      Roguelike::Ui::Keys.install(app, help, play, kitty_keyboard: kitty_keyboard) do
        play.confirm_quit
      end
      nil
    end
    setup.show app, options do |result|
      finish_startup_controls result, title, viewer, play
    end
  end

  private def self.finish_startup_controls(result : Roguelike::Ui::ControlSchemeSetup::Result,
                                           title : Bool,
                                           viewer : Roguelike::Replay::Viewer?,
                                           play : Roguelike::Ui::Play) : Nil
    if result.accepted?
      if warning = result.error
        play.report_warning warning
      end
      play.show_title if title && viewer.nil?
    else
      play.abort_startup
    end
  end
end
