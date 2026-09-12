require "termbuf-widgets"

# Drives a whole application with no terminal anywhere.
#
# `TermBuf::Widgets::App` takes a `TermBuf::Drawing` and an event channel. It
# does not take a `TermBuf::Terminal`. So a spec passes it a plain
# `TermBuf::Buffer` and reads the cells back as text.
#
# Nothing here opens a device. Nothing here puts a terminal in raw mode.
# Nothing here needs a tty. Every drawing phase of this game is testable in
# CI.
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

    # The screen as rows. Trailing blanks come off each row. A fixture diffs
    # better that way.
    def rows : Array(String)
      render.lines.map &.rstrip
    end

    # The screen as one string, with trailing blanks trimmed. For comparing
    # against a `Fixture`.
    def text : String
      rows.join '\n'
    end

    # The row at *index*. For asserting on one line of a pane.
    def row(index : Int32) : String
      rows[index]
    end

    # Puts *event* on the channel. Lets the tree answer it.
    def send(event : TermBuf::Event) : Nil
      @events.send event
      @app.pump
    end

    # Presses the keys *description* names, in order.
    #
    # `TermBuf::Key.parse` reads a whole sequence. `"Ctrl+X s"` is two
    # presses. It arrives as two events. A multi-key binding needs to see
    # both.
    def press(description : String) : Nil
      TermBuf::Key.parse(description).each do |key|
        send TermBuf::Events::Key.new(key, Bytes.empty)
      end
    end

    # Lays the application out at a new size. A resize does the same.
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
