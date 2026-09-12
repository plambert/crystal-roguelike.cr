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
    def self.open(rng : Rng) : Nil
      TermBuf::Terminal.open do |terminal|
        new(terminal, rng).run
      end
    end

    # The device, and the only one anything here touches.
    getter terminal : TermBuf::Terminal

    # The run's randomness.
    getter rng : Rng

    # The regions being drawn in.
    getter screen : Ui::Screen

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

      @screen = Ui::Screen.new
      @screen.fit size.columns, size.rows
      @screen.scaffold @rng.seed

      @app = Ui::Widgets::App.new @terminal, @screen.root, bounds,
        @terminal.events, @terminal.policy
      @cursor = @terminal.cursor bounds

      @app.after = ->(span : Time::Span) { @terminal.after span }
      @app.cancel = ->(nonce : UInt64) { @terminal.cancel nonce }
      @app.copy = ->(text : String) { @terminal.clipboard.copy text }
      @app.images = @terminal.images
      @app.on_event = ->(event : TermBuf::Event) { unclaimed event }

      @help = Ui::Keys.install(@app) { @leaving = true }
    end

    # Draws, waits, and does it again until something ends the run.
    def run : Nil
      loop do
        draw

        break if @leaving
        break unless @app.wait
      end
    end

    # An event no widget wanted.
    #
    # A resize is the one that matters here: the tree is laid out again at the
    # new size, and `Screen#fit` is asked whether the sidebar is still worth
    # having, before anything is drawn against the new rectangles.
    private def unclaimed(event : TermBuf::Event) : Nil
      resize = event.as? TermBuf::Events::Resize
      return unless resize

      size = resize.size
      bounds = TermBuf::Rect.full size.columns, size.rows

      @screen.fit size.columns, size.rows
      @app.resize bounds
      @cursor.region.bounds = bounds
    end

    # One frame: lay out, draw, put the terminal's own cursor where whatever
    # has the keyboard wants it, and send the difference.
    private def draw : Nil
      @app.frame do |spot|
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
