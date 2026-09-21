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
    #
    # It pumps twice. `App#pump` delivers what is posted before it delivers
    # what is waiting, so a message a widget emitted while answering this
    # event is delivered on the pump after it. `Session#run` gets that second
    # pump from `App#wait`.
    def send(event : TermBuf::Event) : Nil
      @events.send event
      @app.pump
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

    # Timers armed and not yet fired, oldest first.
    getter armed : Array(UInt64) = [] of UInt64

    # The nonce the last timer was armed under.
    @nonce : UInt64 = 0

    # Gives the application a clock it can arm timers on.
    #
    # `App#after` needs one and a terminal is what usually provides it. This
    # one arms nothing real: `#tick` sends the timer event back by hand, so a
    # spec drives an animation a step at a time instead of waiting on a
    # wall clock.
    def clock : Nil
      @app.after = ->(_span : Time::Span) do
        @nonce += 1
        @armed << @nonce
        @nonce
      end

      @app.cancel = ->(nonce : UInt64) { @armed.delete nonce; nil }
    end

    # Fires the timer armed first. Answers whether there was one.
    def tick : Bool
      nonce = @armed.shift?
      return false unless nonce

      send TermBuf::Input::Events::Timer.new(nonce)
      true
    end

    # Fires timers until none is armed. Answers how many went off.
    #
    # *most* is a stop against an animation that arms a timer every time one
    # goes off and never finishes.
    def run_timers(most : Int32 = 500) : Int32
      fired = 0
      while fired < most && tick
        fired += 1
      end

      fired
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
