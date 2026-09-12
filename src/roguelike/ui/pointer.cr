module Roguelike::Ui
  # What the mouse pointer is doing. What the terminal should be told about
  # it.
  #
  # Two things change while the pointer is over the map. The terminal's own
  # cursor goes on the square under the pointer. That says which square the
  # readout describes. It covers nothing. The pointer itself becomes a
  # crosshair. A crosshair is thinner than an arrow. It points at one cell
  # rather than at the corner of four.
  #
  # This class holds no terminal. It answers the sequence to send. `Session`
  # sends it. A spec reads what a run of pointer movements asked for.
  class Pointer
    # What the pointer looks like over the map.
    OVER_MAP = "crosshair"

    # What the pointer goes back to anywhere else.
    #
    # This is a named shape rather than a reset. No reset works across the
    # three terminals. `OSC 22` with nothing after the semicolon is kitty's
    # reset. Ghostty parses the payload as a shape name. It ignores a name
    # that is not in its list. The empty form leaves a ghostty pointer on the
    # crosshair.
    #
    # `default`, `text` and `pointer` are the three shapes every terminal with
    # `OSC 22` supports. A terminal draws `text` over its own text. Asking for
    # `text` leaves the pointer looking untouched.
    ELSEWHERE = "text"

    # Where the pointer last was, in buffer cells. `nil` when the pointer was
    # last anywhere but the map.
    getter spot : {Int32, Int32}?

    # What the terminal has been told to draw. `nil` before it has been told
    # anything. A terminal that has been told nothing keeps its own pointer.
    getter shape : String?

    # Where the terminal's own cursor belongs. `nil` hides it.
    def cursor : {Int32, Int32}?
      @spot
    end

    # Records that the pointer is over the map, at *x*, *y* of the buffer.
    #
    # Answers the sequence to send. Answers `nil` when the terminal already
    # draws that shape.
    def over(x : Int32, y : Int32) : String?
      @spot = {x, y}
      want OVER_MAP
    end

    # Records that the pointer is elsewhere. Answers the sequence to send, or
    # `nil`.
    #
    # A terminal that was never told anything is told nothing now. A program
    # restores what it changed. It changes nothing else.
    def away : String?
      @spot = nil
      @shape ? want(ELSEWHERE) : nil
    end

    # The sequence that asks for *shape*.
    #
    # The form is `OSC 22 ; name ST`. A terminal without `OSC 22` ignores the
    # sequence.
    def self.sequence(shape : String) : String
      "\e]22;#{shape}\e\\"
    end

    private def want(shape : String) : String?
      return if @shape == shape

      @shape = shape
      Pointer.sequence shape
    end
  end
end
