require "termbuf"
require "./ui"

module Roguelike
  # One run, from taking the terminal over to giving it back.
  #
  # The only thing in the game that owns a device. Everything it shows and
  # everything its keys do is `Ui::Play`, which owns no device, so the
  # interesting half is driven by specs over a buffer and what is left here is
  # the frame loop, the mouse and the cursor.
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

    # Everything that is shown and everything the keys do.
    getter play : Ui::Play

    # The widget tree, its focus and its router.
    getter app : Ui::Widgets::App

    # The terminal's own cursor, pointed wherever it belongs.
    getter cursor : TermBuf::Cursor

    # The keys that work here, listed on `F1` and `?`.
    getter help : Ui::Widgets::HelpOverlay

    # Whether the terminal is reporting the mouse.
    #
    # On at the start, because pointing at a square to find out what it is is
    # the quickest way to read a map, and off on `M`, because a terminal
    # reporting the mouse no longer lets the person select text with it.
    getter? mousing : Bool = false

    # Whether something has ended the run.
    getter? leaving : Bool = false

    def initialize(@terminal : TermBuf::Terminal, @rng : Rng)
      size = @terminal.size
      bounds = TermBuf::Rect.full size.columns, size.rows

      @play = Ui::Play.new Game.start(@rng)
      @play.fit size.columns, size.rows

      @app = Ui::Widgets::App.new @terminal, @play.root, bounds,
        @terminal.events, @terminal.policy
      @cursor = @terminal.cursor bounds

      @app.after = ->(span : Time::Span) { @terminal.after span }
      @app.cancel = ->(nonce : UInt64) { @terminal.cancel nonce }
      @app.copy = ->(text : String) { @terminal.clipboard.copy text }
      @app.images = @terminal.images
      @app.on_event = ->(event : TermBuf::Event) { unclaimed event }

      @help = Ui::Keys.install(@app) { @leaving = true }
      @app.keymap = @app.keymap
        .merge(@play.bindings)
        .merge(Ui::Keys.mousing { self.mousing = !mousing? })

      self.mousing = true

      # One layout before the camera is pointed, because a window that has not
      # been measured has no middle to put anything in.
      @app.frame { }
      @play.look_at_player
    end

    # The run.
    def game : Game
      @play.game
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
      tell @play.pointer_away
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
        tell @play.pointer_away
      end

      status
      wanted
    end

    # Writes the status line, which is the one thing on the screen the play
    # cannot work out for itself.
    private def status : Nil
      @play.screen.status_text.text = @play.status mousing?
    end

    # Sends *sequence*, if there is one to send.
    private def tell(sequence : String?) : Nil
      @terminal.passthrough sequence if sequence
    end

    # An event no widget wanted.
    #
    # Two get this far: a mouse report, because the map pane draws squares and
    # does not know what is on them, and a resize, because the tree has to be
    # laid out again and `Screen#fit` asked what is still worth showing before
    # anything is drawn against the new rectangles.
    private def unclaimed(event : TermBuf::Event) : Nil
      case event
      when TermBuf::Events::Mouse  then tell @play.pointed(event.x, event.y)
      when TermBuf::Events::Resize then resized event
      end
    end

    private def resized(resize : TermBuf::Events::Resize) : Nil
      size = resize.size
      bounds = TermBuf::Rect.full size.columns, size.rows

      @play.fit size.columns, size.rows
      @app.resize bounds
      @cursor.region.bounds = bounds

      # Whatever the pointer was over is not there any more.
      tell @play.pointer_away
    end

    # One frame: lay out, draw, put the terminal's own cursor where it
    # belongs, and send the difference.
    private def draw : Nil
      @app.frame do |focused|
        # The pointer wins: it is being moved now, and whatever has the
        # keyboard is not.
        spot = @play.pointer.cursor || focused

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
