require "termbuf"
require "../crystal-roguelike"

module Roguelike
  # One run, from taking the terminal over to giving it back.
  #
  # This is the only class in the game that owns a device. `Ui::Play` owns
  # everything shown and everything the keys do. `Ui::Play` owns no device, so
  # specs drive it over a buffer. What is left here is the frame loop, the
  # mouse and the cursor.
  class Session
    # Runs games on the terminal until nobody asks for another. Gives the
    # terminal back however the last one ends. That includes an exception and
    # a signal. The block form of `Terminal.open` does that.
    #
    # Answers the session that ran last, which is what the caller reports on.
    # Answers `nil` when the window is too small to play in. It writes the
    # reason to stderr in that case. It does not take the terminal over at
    # all.
    #
    # *seed* is the run's seed, or `nil` for a fresh one. A person who asks
    # for another run gets the same seed when one was named and a fresh seed
    # when none was, so `--seed N` goes on reproducing N and a run started
    # without it is a new dungeon every time.
    #
    # *size_cap* limits how much of the terminal the game draws in. Every run
    # shares it, so a cap the debug console set carries into the next run.
    #
    # *tester_root* is the state directory to write the tester file in. The
    # first run asks for a tester name before the title screen when it is
    # given. A later run does not ask again.
    #
    # This method reads the size before it enters the alternate screen. The
    # message then stays where the person can read it. Handing the screen back
    # would wipe it.
    #
    # `SizeDetector` is termbuf's internal tier. The stable API cannot answer
    # how big a terminal is without opening it. The other way to find out is
    # to enter the alternate screen and leave it again.
    def self.open(seed : UInt64?, flicker : Bool? = nil,
                  generate : Bool = true, console : Bool = false,
                  store : Save::Store? = nil, character : String? = nil,
                  news : Array(WhatsNew::Section) = [] of WhatsNew::Section,
                  size_cap : SizeCap = SizeCap.new,
                  tester_root : Path? = nil) : Session?
      size = TermBuf::SizeDetector.detect
      columns, rows = size_cap.apply size.columns, size.rows

      unless Ui::Screen.fits? columns, rows
        STDERR.puts Ui::Screen.too_small(columns, rows)
        return
      end

      ran = nil.as Session?
      previous = nil.as String?
      refused = nil.as String?

      TermBuf::Terminal.open do |terminal|
        # The colours are known only once the terminal has been asked, which
        # `Terminal.open` does. A terminal without enough of them is handed
        # back before anything is drawn on it, and told why afterwards.
        refused = Ui::Screen.too_few_colors terminal.capabilities
        next if refused

        options = display_preferences

        # A signal stops the process without running `at_exit`, so the
        # replay log's footer is written here or not at all.
        terminal.signals.before_exit { Replay::Log.signalled }

        loop do
          playing_flicker = flicker.nil? ? options.flicker? : flicker
          played = new terminal, Rng.for(seed), playing_flicker, generate, console,
            store, character, previous, news: news, size_cap: size_cap,
            tester_root: tester_root, mouse: options.mouse?
          options.apply played
          played.flickering = flicker unless flicker.nil?
          ran = played
          played.run

          # The name was asked for once. A second run starts from the title
          # screen again, so it asks again. What it asks offers the name the
          # run that just ended was under, because that is what somebody who
          # answered "play again" usually wants.
          character = nil
          tester_root = nil
          previous = played.play.game.player.name.presence

          break unless played.again?
        end
      end

      if refused
        STDERR.puts refused
        return
      end

      ran
    end

    # Plays *viewer* back on the terminal. Answers the session that ran it.
    #
    # Answers `nil` when the window is too small, the way `.open` does.
    #
    # There is no loop around it. A recorded run plays once, and somebody who
    # wants it again runs the command again.
    def self.view(viewer : Replay::Viewer, flicker : Bool? = nil) : Session?
      size = TermBuf::SizeDetector.detect

      unless Ui::Screen.fits? size.columns, size.rows
        STDERR.puts Ui::Screen.too_small(size.columns, size.rows)
        return
      end

      ran = nil.as Session?
      refused = nil.as String?

      TermBuf::Terminal.open do |terminal|
        refused = Ui::Screen.too_few_colors terminal.capabilities
        next if refused

        options = display_preferences
        playing_flicker = flicker.nil? ? options.flicker? : flicker
        played = new terminal, Rng.for(viewer.game.world.seed), playing_flicker,
          viewer: viewer, mouse: options.mouse?
        options.apply played
        played.flickering = flicker unless flicker.nil?
        ran = played
        played.run
      end

      if refused
        STDERR.puts refused
        return
      end

      ran
    end

    # Loads display preferences after terminal capabilities are known and
    # before the first frame is drawn.
    def self.display_preferences(root : Path = Submit.root) : Options
      options = Options.current || Options.arrange_display(root)
      Options.current = options
      options.apply
      Ui::Theme.current = Ui::Theme.read root
      Ui::Palette.rebuild
      options
    end

    # The run a session begins on.
    protected def self.starting(viewer : Replay::Viewer?, rng : Rng,
                                generate : Bool) : Game
      found = viewer
      return found.game if found

      generate ? Game.dug(rng) : Game.start(rng)
    end

    # The device. This class touches no other.
    getter terminal : TermBuf::Terminal

    # The run's randomness.
    getter rng : Rng

    # Everything that is shown. Everything the keys do.
    getter play : Ui::Play

    # The widget tree, its focus and its router.
    getter app : Ui::Widgets::ObservedApp

    # The terminal's own cursor.
    getter cursor : TermBuf::Cursor

    # The list of keys that work here. `F1` and `?` show it.
    getter help : Ui::Help

    # The most columns and rows the game draws in.
    getter size_cap : SizeCap

    # Whether the terminal is reporting the mouse.
    #
    # This starts on. Pointing at a square is the quickest way to read a map.
    # `M` turns it off. A terminal reporting the mouse no longer lets the
    # person select text with it.
    getter? mousing : Bool = false

    # Whether the terminal's window has the focus.
    #
    # A terminal that reports focus says when this changes. One that does not
    # leaves it true. The map pane is idle while it is false, so the flames
    # go on moving at a small part of the cost.
    getter? focused : Bool = true

    # The timer the next tick of the flames is armed under. `nil` when none
    # is armed.
    @wavering : UInt64? = nil

    def initialize(@terminal : TermBuf::Terminal, @rng : Rng,
                   flicker : Bool = true, generate : Bool = true,
                   console : Bool = false, store : Save::Store? = nil,
                   character : String? = nil, previous : String? = nil,
                   viewer : Replay::Viewer? = nil,
                   news : Array(WhatsNew::Section) = [] of WhatsNew::Section,
                   @size_cap : SizeCap = SizeCap.new,
                   tester_root : Path? = nil,
                   mouse : Bool = true)
      bounds = drawn_in @terminal.size

      @play = Ui::Play.new Session.starting(viewer, @rng, generate), console

      # The banner takes a row from the message pane, and `#bindings` reads
      # the viewer, so this comes before the fit and before the keymap.
      @play.view viewer if viewer

      @play.store = store
      @play.previous_name = previous
      @play.news = news
      @play.fit bounds.width, bounds.height

      # The theme stores 24 bit colors. A terminal without them draws the
      # nearest of the 256, so the picker offers only those.
      unless @terminal.capabilities.includes? TermBuf::Capability::TrueColor
        @play.color_depth = Ui::Widgets::Depth::Indexed256
      end

      @app = Ui::Widgets::ObservedApp.new @terminal, @play.root, bounds,
        @terminal.events, @terminal.policy
      @cursor = @terminal.cursor bounds
      @play.app = @app

      @app.after = ->(span : Time::Span) { @terminal.after span }
      @app.cancel = ->(nonce : UInt64) { @terminal.cancel nonce }
      @app.copy = ->(text : String) { @terminal.clipboard.copy text }
      @app.images = @terminal.images
      @app.on_event = ->(event : TermBuf::Event) { unclaimed event }
      @app.on_deliver = ->(event : TermBuf::Event) { noticed event }
      @app.on_outside = ->(_event : TermBuf::Event) { tell @play.pointer_away }

      @help = Ui::Help.new @play.game.world.seed
      @help.screen_rows = bounds.height

      @size_cap.on_change = -> { sized @terminal.size }
      @play.console.try &.console.size_cap = @size_cap
      Ui::Keys.install(@app, @help, @play, -> { self.mousing = !mousing?; nil }) { @play.confirm_quit }

      self.mousing = mouse
      @play.on_options = ->(options : Options) { options.apply self; nil }

      # The window reports when it gains and loses the focus. `Terminal#close`
      # turns the reports off again.
      @terminal.enable TermBuf::Tty::FOCUS_EVENTS

      # One layout runs before the camera is pointed. An unmeasured window
      # has no middle to put anything in.
      @app.frame { }
      @play.look_at_player

      self.flickering = flicker

      # A recorded run is already under way. It asks nobody who is playing.
      return if viewer

      # `--character` says who is playing, so the title screen and the name
      # question are both answered already.
      begin_play = -> do
        character ? @play.play_as(character) : @play.show_title
        nil
      end

      if tester_root
        @play.ask_the_tester tester_root, begin_play
      else
        begin_play.call
      end
    end

    # Whether the flames waver.
    def flickering? : Bool
      @play.flicker.burning?
    end

    # Starts the flames wavering, or holds them still. The options screen
    # turns this on and off during a run.
    def flickering=(on : Bool) : Bool
      @play.flicker.burning = on

      if on
        waver unless @wavering
      elsif armed = @wavering
        @app.cancel armed
        @wavering = nil
      end

      on
    end

    # Schedules the next tick of the flames, and the one after it.
    #
    # This is the one thing in the game driven by a clock rather than a turn.
    # The timer arrives on the same channel as the keystrokes, in order with
    # them, so a tick cannot land in the middle of a turn.
    #
    # It moves nothing the game decides. `Play#waver` shifts which shade a
    # lit square draws at and no more, so the paint that follows sends the
    # squares whose color moved and nothing else.
    private def waver : Nil
      @wavering = @app.after(Ui::Flicker::PERIOD) do
        @play.waver
        waver
      end
    end

    # Sees *event* before the widget tree does.
    #
    # Anything but a tick of the flames may change what the map shows. The
    # map pane drops the drawings it keeps while it is idle.
    #
    # A left click moves the focus to the panel it lands in, whatever in the
    # panel answers it.
    private def noticed(event : TermBuf::Event) : Nil
      return if event.is_a?(TermBuf::Events::Timer) && event.nonce == @wavering

      @play.map.forget_frames
      @play.focus_under event
    end

    # Records whether the window has the focus. The map pane is idle while
    # it does not.
    def focused=(focused : Bool) : Bool
      @focused = focused
      @play.map.idle = !focused
      focused
    end

    # The run.
    def game : Game
      @play.game
    end

    # Whether the person asked for another run when this one ended.
    def again? : Bool
      @play.again?
    end

    # Draws, waits, and repeats until something ends the run.
    #
    # The `ensure` puts the pointer shape back however the run ends.
    # `Terminal#close` restores every mode termbuf set. termbuf never sets
    # `OSC 22`. This class set it. This class restores it.
    def run : Nil
      loop do
        draw

        break if @play.finished?
        break unless @app.wait
      end
    ensure
      tell @play.pointer_away
    end

    # Turns mouse reporting on or off. Writes the new state to the status
    # line.
    #
    # Nothing asks the terminal for the mouse uninvited. `Terminal#close`
    # restores mouse reporting as well as this method. A run that ends any way
    # at all leaves the terminal able to select text again.
    def mousing=(wanted : Bool) : Bool
      return wanted if wanted == @mousing

      @mousing = wanted

      if wanted
        @terminal.enable TermBuf::Tty::MOUSE_SGR_ANY
      else
        @terminal.disable TermBuf::Tty::MOUSE_SGR_ANY
        tell @play.pointer_away
      end

      status
      wanted
    end

    # Tells the status line whether the mouse is reporting. The terminal knows
    # that. The game does not.
    private def status : Nil
      @play.mousing = mousing?
    end

    # Sends *sequence*. Sends nothing when *sequence* is `nil`.
    private def tell(sequence : String?) : Nil
      @terminal.passthrough sequence if sequence
    end

    # An event no widget wanted.
    #
    # Three kinds get this far. A mouse report gets here because the map pane
    # draws squares and holds nothing about what is on them. A resize gets
    # here because the tree has to be laid out again. `Screen#fit` then decides
    # what is still worth showing, before anything draws against the new
    # rectangles. A focus report gets here because no widget cares whether
    # the window has the focus.
    private def unclaimed(event : TermBuf::Event) : Nil
      case event
      when TermBuf::Events::Mouse  then tell @play.reported(event)
      when TermBuf::Events::Resize then sized event.size
      when TermBuf::Events::Focus  then self.focused = event.focused
      end
    end

    # The part of a terminal of *size* the game draws in. It is the top left
    # corner, cut down to the caps.
    private def drawn_in(size : TermBuf::ScreenSize) : TermBuf::Rect
      columns, rows = @size_cap.apply size.columns, size.rows
      TermBuf::Rect.full columns, rows
    end

    # Lays the game out again for a terminal of *size*. A resize and a change
    # of cap both come here.
    #
    # Nothing draws outside the area, so cells the game drew in before stay
    # on the screen when the area shrinks. The terminal is cleared once then,
    # and the next frame fills the area again.
    private def sized(size : TermBuf::ScreenSize) : Nil
      bounds = drawn_in size
      @terminal.clear unless bounds.contains? @app.tree.screen

      # The tree takes its new size first, so the layout `Play#fit` asks for
      # measures the map at that size when it brings the character into view.
      @app.resize bounds
      @play.fit bounds.width, bounds.height
      @cursor.region.bounds = bounds
      @help.screen_rows = bounds.height

      # The square the pointer was over has moved.
      tell @play.pointer_away
    end

    # One frame. Lay out, draw, place the terminal's own cursor, and send the
    # difference.
    private def draw : Nil
      @app.frame do |focused|
        # The pointer wins, then the examine cursor. The person is moving one
        # of those now. The person is not moving whatever has the keyboard.
        spot = @play.cursor || focused

        if spot
          @cursor.move_to spot[0], spot[1]
          @terminal.hardware_cursor = @cursor
        else
          @terminal.hide_cursor
        end
      end

      @terminal.paint
    end
  end
end
