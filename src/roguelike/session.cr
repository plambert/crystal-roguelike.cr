require "termbuf"
require "./ui"

module Roguelike
  # One run, from taking the terminal over to giving it back.
  #
  # This is the only thing in the game that owns a device. Everything under
  # `Ui` is a widget tree and everything under the model is state, so a spec
  # exercises either without one.
  class Session
    # Runs a game on the terminal, giving it back however the run ends —
    # including on an exception or a signal, which is what the block form of
    # `Terminal.open` is for.
    #
    # Answers false without taking the terminal over at all when the window is
    # too small to play in, having said so on stderr. The size is read before
    # the alternate screen is entered, so the message is left where the person
    # can read it rather than wiped by the screen being handed back.
    #
    # `SizeDetector` is termbuf's internal tier. It is used here because the
    # question — how big is the terminal, without opening it — has no answer
    # in the stable API, and the alternative is entering the alternate screen
    # and leaving it again to find out.
    def self.open(rng : Rng) : Bool
      size = TermBuf::SizeDetector.detect

      unless Ui::Screen.fits? size.columns, size.rows
        STDERR.puts Ui::Screen.too_small(size.columns, size.rows)
        return false
      end

      TermBuf::Terminal.open do |terminal|
        new(terminal, rng).run
      end

      true
    end

    # The device, and the only one anything here touches.
    getter terminal : TermBuf::Terminal

    # The run's randomness.
    getter rng : Rng

    # Every level of the run, and the seed that made it.
    getter world : World

    # The regions being drawn in.
    getter screen : Ui::Screen

    # The window the level is played in.
    getter map : Ui::MapPane

    # The readout of what is on one square.
    getter examine : Ui::ExaminePane

    # What points the readout, from the pointer or from the keyboard.
    getter examiner : Ui::Examiner

    # What the mouse pointer is doing, and what the terminal is being told
    # about it.
    getter pointer : Ui::Pointer

    # Whether the terminal is reporting the mouse.
    #
    # On at the start, because pointing at a square to find out what it is is
    # the quickest way to read a map, and off on `M`, because a terminal
    # reporting the mouse no longer lets the person select text with it.
    getter? mousing : Bool = false

    # The widget tree, its focus and its router.
    getter app : Ui::Widgets::App

    # The terminal's own cursor, pointed wherever the keyboard is.
    getter cursor : TermBuf::Cursor

    # The keys that work here, listed on `F1` and `?`.
    getter help : Ui::Widgets::HelpOverlay

    # Whether something has ended the run.
    getter? leaving : Bool = false

    def initialize(@terminal : TermBuf::Terminal, @rng : Rng)
      size = @terminal.size
      bounds = TermBuf::Rect.full size.columns, size.rows

      @world = World.on @rng
      level = @world.add Levels.proving_ground

      @screen = Ui::Screen.new
      @screen.fit size.columns, size.rows
      @screen.scaffold @rng.seed

      @map = Ui::MapPane.new level
      @screen.show @map.grid

      @examine = Ui::ExaminePane.new
      @screen.show_sidebar @examine.root
      @examiner = Ui::Examiner.new @map, @examine
      @pointer = Ui::Pointer.new

      @app = Ui::Widgets::App.new @terminal, @screen.root, bounds,
        @terminal.events, @terminal.policy
      @cursor = @terminal.cursor bounds

      @app.after = ->(span : Time::Span) { @terminal.after span }
      @app.cancel = ->(nonce : UInt64) { @terminal.cancel nonce }
      @app.copy = ->(text : String) { @terminal.clipboard.copy text }
      @app.images = @terminal.images
      @app.on_event = ->(event : TermBuf::Event) { unclaimed event }

      @help = Ui::Keys.install(@app) { @leaving = true }
      @app.keymap = @app.keymap
        .merge(Ui::Keys.examining(@examiner))
        .merge(Ui::Keys.moving { |direction| step direction })
        .merge(Ui::Keys.mousing { self.mousing = !mousing? })

      self.mousing = true
    end

    # Turns mouse reporting on or off, and says so on the status line.
    #
    # Nothing asks the terminal for the mouse uninvited, and giving it back is
    # `Terminal#close`'s job as well as this one's, so a run that ends any way
    # at all leaves the terminal able to select text again.
    def mousing=(wanted : Bool) : Bool
      return wanted if wanted == @mousing

      @mousing = wanted

      if wanted
        @terminal.enable TermBuf::Tty::MOUSE_SGR_ANY
      else
        @terminal.disable TermBuf::Tty::MOUSE_SGR_ANY
        pointer_away
      end

      status
      wanted
    end

    # The pointer is no longer on the map, so the terminal gets its own cursor
    # and its own pointer back.
    private def pointer_away : Nil
      return unless @pointer.shape

      @pointer.away
      @terminal.passthrough Ui::Pointer.sequence(nil)
    end

    # One step of a movement key.
    #
    # It moves the examine cursor while that is on the map. Phase 5 gives it
    # the player for every other time.
    def step(direction : Direction) : Nil
      # The keyboard is being used, and it can move the camera out from under
      # wherever the pointer was last seen.
      pointer_away
      @examiner.move direction
    end

    # Writes the status line.
    private def status : Nil
      @screen.status_text.text = "seed #{@rng.seed}    turn 0    " \
                                 "mouse #{mousing? ? "on" : "off"}    " \
                                 "x to look, ? for the keys"
    end

    # Draws, waits, and does it again until something ends the run.
    #
    # The pointer shape is put back however the run ends. `Terminal#close`
    # gives back everything termbuf asked for and nothing it does not know
    # about, and `OSC 22` is ours.
    def run : Nil
      loop do
        draw

        break if @leaving
        break unless @app.wait
      end
    ensure
      pointer_away
    end

    # An event no widget wanted.
    #
    # Two get this far: a mouse report, because the map pane draws squares and
    # does not know what is on them, and a resize, because the tree has to be
    # laid out again and `Screen#fit` asked what is still worth showing before
    # anything is drawn against the new rectangles.
    private def unclaimed(event : TermBuf::Event) : Nil
      case event
      when TermBuf::Events::Mouse  then pointed event
      when TermBuf::Events::Resize then resized event
      end
    end

    # The pointer moved, or something was clicked with it.
    #
    # Every report says where it is, so a move and a click point the readout
    # alike and neither needs a mode. A report over anything that is not the
    # map leaves the readout saying what it said.
    private def pointed(event : TermBuf::Events::Mouse) : Nil
      unless @examiner.point_at_screen event.x, event.y
        pointer_away
        return
      end

      wanted = @pointer.shape
      @pointer.over event.x, event.y
      return if wanted == @pointer.shape

      @terminal.passthrough Ui::Pointer.sequence(@pointer.shape)
    end

    private def resized(resize : TermBuf::Events::Resize) : Nil
      size = resize.size
      bounds = TermBuf::Rect.full size.columns, size.rows

      @screen.fit size.columns, size.rows
      @app.resize bounds
      @cursor.region.bounds = bounds

      # Whatever the pointer was over is not there any more.
      pointer_away
    end

    # One frame: lay out, draw, put the terminal's own cursor where whatever
    # has the keyboard wants it, and send the difference.
    private def draw : Nil
      @app.frame do |focused|
        # The pointer wins: it is being moved now, and whatever has the
        # keyboard is not.
        spot = @pointer.cursor || focused

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
