module Roguelike::Ui
  # What the mouse pointer is doing, and what the terminal should be told
  # about it.
  #
  # Two things change while the pointer is over the map: the terminal's own
  # cursor goes on the square under it, which says exactly which square is
  # being read without covering anything up, and the pointer itself becomes a
  # crosshair, which is thinner than an arrow and points at one cell rather
  # than at a corner of four.
  #
  # The pointer cannot be hidden. `OSC 22` is the only control for it that
  # terminals agree on, ghostty, kitty and iTerm2 all have it, and every shape
  # it takes is a CSS cursor name — none of which means "no pointer". Hiding
  # the pointer while it is still is a setting in each of those terminals
  # (`mouse-hide-while-typing`, `mouse_hide_wait`) and is theirs to make, not
  # an application's to ask for.
  #
  # Holds no terminal, so a spec drives one and reads the sequences it asks
  # for.
  class Pointer
    # What the pointer looks like over the map.
    OVER_MAP = "crosshair"

    # Where it last was, in buffer cells, or `nil` when it was last anywhere
    # but the map.
    getter spot : {Int32, Int32}?

    # What the pointer is being drawn as, or `nil` for the terminal's own.
    getter shape : String?

    # Whether the terminal's own cursor should be showing, and where.
    def cursor : {Int32, Int32}?
      @spot
    end

    # The pointer is over the map, at *x*, *y* of the buffer.
    def over(x : Int32, y : Int32) : Nil
      @spot = {x, y}
      @shape = OVER_MAP
    end

    # It is somewhere else, or there is no pointer at all.
    def away : Nil
      @spot = nil
      @shape = nil
    end

    # The sequence that asks for *shape*, or for the terminal's own when it is
    # `nil`.
    #
    # `OSC 22 ; name ST`. A terminal that does not know it ignores it, which
    # is what an OSC nobody recognises is for.
    def self.sequence(shape : String?) : String
      "\e]22;#{shape}\e\\"
    end
  end
end
