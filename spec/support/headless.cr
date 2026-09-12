require "termbuf-widgets"

# Driving a whole application with no terminal anywhere.
#
# `TermBuf::Widgets::App` is given a `TermBuf::Drawing` and an event channel
# rather than a `TermBuf::Terminal`, so a spec can hand it a plain
# `TermBuf::Buffer` and read the cells back as text. Nothing here opens a
# device, puts a terminal in raw mode, or needs a tty to exist, which is what
# makes every drawing phase of this game testable in CI.
module Headless
  DEFAULT_COLUMNS = 80
  DEFAULT_ROWS    = 24

  # One application, its buffer, and the channel its events arrive on.
  class Session
    # The cells the application drew into.
    getter buffer : TermBuf::Buffer

    # The application under test.
    getter app : TermBuf::Widgets::App

    # Where an event goes to reach it.
    getter events : Channel(TermBuf::Event)

    def initialize(@buffer : TermBuf::Buffer,
                   @app : TermBuf::Widgets::App,
                   @events : Channel(TermBuf::Event))
    end

    # Lays out, draws, and answers what the screen now holds.
    def render : String
      @app.frame
      @buffer.to_text
    end

    # The screen as rows, with the blanks each one ends in taken off, which is
    # what a fixture wants to be diffed against.
    def rows : Array(String)
      render.lines.map &.rstrip
    end

    # The row at *index*, for asserting on one line of a pane.
    def row(index : Int32) : String
      rows[index]
    end

    # Puts *event* on the channel and lets the tree answer it.
    def send(event : TermBuf::Event) : Nil
      @events.send event
      @app.pump
    end

    # The keys *description* names, pressed in order.
    #
    # `TermBuf::Key.parse` reads a whole sequence, so `"Ctrl+X s"` is two
    # presses and arrives as two events, which is what a multi-key binding
    # needs to see.
    def press(description : String) : Nil
      TermBuf::Key.parse(description).each do |key|
        send TermBuf::Events::Key.new(key, Bytes.empty)
      end
    end

    # Lays the application out at a new size, as a resize would.
    def resize(columns : Int32, rows : Int32) : Nil
      @buffer.resize columns, rows
      @app.resize TermBuf::Rect.full(columns, rows)
    end
  end

  # An application over *root*, drawn into a buffer of *columns* by *rows*.
  def self.open(root : TermBuf::Widgets::Widget,
                columns : Int32 = DEFAULT_COLUMNS,
                rows : Int32 = DEFAULT_ROWS) : Session
    buffer = TermBuf::Buffer.new columns, rows
    events = Channel(TermBuf::Event).new 64

    app = TermBuf::Widgets::App.new TermBuf::BufferSurface.new(buffer), root,
      TermBuf::Rect.full(columns, rows), events

    Session.new buffer, app, events
  end
end
