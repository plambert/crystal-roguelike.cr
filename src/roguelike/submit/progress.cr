require "../../roguelike"

module Roguelike
  module Submit
    # The progress line a send shows on standard error.
    #
    # One line per piece. On a terminal it is redrawn in place with a
    # carriage return. Anywhere else it is written once, when the piece has
    # been sent, so a log holds one line per piece.
    module Progress
      # An IO that counts the bytes read from another.
      #
      # *on_read* gets the running total after each read.
      class Counter < IO
        # The bytes read so far.
        getter count : Int64 = 0

        def initialize(@io : IO, &@on_read : Int64 -> Nil)
        end

        def read(slice : Bytes) : Int32
          bytes = @io.read slice
          @count += bytes
          @on_read.call @count
          bytes
        end

        def write(slice : Bytes) : Nil
          raise IO::Error.new "a counter is read only"
        end
      end

      # How many cells the bar has.
      WIDTH = 24

      # The line for *name* with *sent* of *total* bytes gone.
      #
      # On a terminal the line has a bar. Elsewhere it has only the counts.
      def self.line(name : String, sent : Int, total : Int, bar : Bool = true) : String
        counts = "#{Outbox.sized sent} of #{Outbox.sized total}"
        return "#{name.ljust 6} #{counts}" unless bar

        filled = total > 0 ? (WIDTH * sent.clamp(0, total) // total).to_i : WIDTH
        "#{name.ljust 6} [#{"#" * filled}#{"-" * (WIDTH - filled)}] #{counts}"
      end

      # Shows one piece at a time on *output*.
      #
      # A write that fails turns the reporter off for the rest of the run.
      # The upload does not notice.
      class Reporter
        @name = ""
        @total = 0_i64
        @sent = 0_i64
        @shown = ""
        @off = false

        # Whether *output* is a terminal, which decides how lines are drawn.
        getter? tty : Bool

        def initialize(@output : IO, tty : Bool? = nil)
          @tty = tty.nil? ? (@output.as?(IO::FileDescriptor).try(&.tty?) || false) : tty
        end

        # Shows *body* being sent as *name*. The block sends it, and gets
        # an IO to read the body from.
        def piece(name : String, body : IO, total : Int64, & : IO -> T) : T forall T
          start name, total
          counter = Counter.new(body) { |sent| update sent }
          begin
            yield counter
          ensure
            finish
          end
        end

        private def start(name : String, total : Int64) : Nil
          @name = name
          @total = total
          @sent = 0
          @shown = ""
          draw
        end

        private def update(sent : Int64) : Nil
          @sent = sent
          draw
        end

        # Draws the line again when it has changed. Only a terminal sees
        # the lines before the last.
        private def draw : Nil
          return if @off || !@tty

          text = Progress.line @name, @sent, @total
          return if text == @shown

          @shown = text
          @output.print '\r', text
          @output.flush
        rescue IO::Error
          @off = true
        end

        private def finish : Nil
          return if @off

          if @tty
            draw
            @output.puts
          else
            @output.puts Progress.line(@name, @sent, @total, bar: false)
          end
          @output.flush
        rescue IO::Error
          @off = true
        end
      end
    end
  end
end
