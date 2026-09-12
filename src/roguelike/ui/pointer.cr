module Roguelike::Ui
  # What the mouse pointer is doing, and what the terminal should be told
  # about it.
  #
  # Two things change while the pointer is over the map: the terminal's own
  # cursor goes on the square under it, which says exactly which square is
  # being read without covering anything up, and the pointer becomes a
  # crosshair, which is thinner than an arrow and points at one cell rather
  # than at the corner of four.
  #
  # Holds no terminal. It answers the sequence to send and `Session` sends it,
  # so a spec can read what a run of pointer movements would have asked for.
  class Pointer
    # What the pointer looks like over the map.
    OVER_MAP = "crosshair"

    # What it goes back to anywhere else.
    #
    # An explicit shape rather than a reset, because there is no reset that
    # works. `OSC 22` with nothing after the semicolon is kitty's reset, and
    # ghostty parses the payload as a shape name and ignores one it does not
    # recognise — so the empty form leaves a ghostty pointer on whatever it
    # was last told, which is the crosshair. `default`, `text` and `pointer`
    # are the three every terminal that has `OSC 22` at all supports, and
    # `text` is the one a terminal shows over its own text anyway, so asking
    # for it leaves the pointer looking untouched.
    ELSEWHERE = "text"

    # Where the pointer last was, in buffer cells, or `nil` when it was last
    # anywhere but the map.
    getter spot : {Int32, Int32}?

    # What the terminal has been told to draw, or `nil` before it has been
    # told anything — which is a terminal whose pointer is still its own and
    # must be left that way.
    getter shape : String?

    # Where the terminal's own cursor should be, or `nil` for hidden.
    def cursor : {Int32, Int32}?
      @spot
    end

    # The pointer is over the map, at *x*, *y* of the buffer.
    #
    # Answers the sequence to send, or `nil` when the terminal already knows.
    def over(x : Int32, y : Int32) : String?
      @spot = {x, y}
      want OVER_MAP
    end

    # It is somewhere else, or there is no pointer at all. Answers the
    # sequence to send, or `nil`.
    #
    # A terminal that was never told anything is told nothing now: a program
    # gives back what it took and no more.
    def away : String?
      @spot = nil
      @shape ? want(ELSEWHERE) : nil
    end

    # The sequence that asks for *shape*.
    #
    # `OSC 22 ; name ST`. A terminal that does not know the sequence ignores
    # it, which is what an OSC nobody recognises is for.
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
