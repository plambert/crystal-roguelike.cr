module Roguelike
  # The most columns and the most rows the game draws in.
  #
  # The game draws in the top left corner of the terminal, as if the terminal
  # were no bigger than this. It is for testing layouts without resizing the
  # window. `--max-columns` and `--max-rows` set it, and so do the debug
  # console's `max-columns` and `max-rows`.
  #
  # It is a display setting. No save, replay log or fingerprint holds it, so
  # a run plays out the same at any cap.
  class SizeCap
    # The most columns drawn in. `nil` when the columns are not capped.
    getter columns : Int32?

    # The most rows drawn in. `nil` when the rows are not capped.
    getter rows : Int32?

    # What runs after either cap changes. The session refits the screen here.
    property on_change : Proc(Nil)? = nil

    def initialize(columns : Int32? = nil, rows : Int32? = nil)
      @columns = SizeCap.held columns
      @rows = SizeCap.held rows
    end

    # Caps the columns at *columns*. Zero or `nil` clears the cap.
    def columns=(columns : Int32?) : Int32?
      @columns = SizeCap.held columns
      @on_change.try &.call
      @columns
    end

    # Caps the rows at *rows*. Zero or `nil` clears the cap.
    def rows=(rows : Int32?) : Int32?
      @rows = SizeCap.held rows
      @on_change.try &.call
      @rows
    end

    # A terminal of *columns* by *rows*, cut down to the caps.
    def apply(columns : Int32, rows : Int32) : {Int32, Int32}
      {Math.min(columns, @columns || columns), Math.min(rows, @rows || rows)}
    end

    # What a cap of *value* is kept as. Anything below one is no cap.
    protected def self.held(value : Int32?) : Int32?
      value if value && value > 0
    end
  end
end
