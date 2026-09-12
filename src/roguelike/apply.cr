module Roguelike
  # Something the character could apply.
  #
  # Two things answer to `a`. A carried torch or candle is named by its
  # inventory letter. A wall sconce is named by where it is on the floor. One
  # record covers both, so the menu that offers them is one list.
  #
  # A `#letter` says it is carried. No letter says it is the sconce at
  # `#x`, `#y`.
  record Apply,
    letter : Char? = nil,
    x : Int32 = 0,
    y : Int32 = 0 do
    # The carried item under *letter*.
    def self.carried(letter : Char) : Apply
      new letter: letter
    end

    # The sconce at *x*, *y*.
    def self.sconce(x : Int32, y : Int32) : Apply
      new x: x, y: y
    end

    # Whether this names a carried item rather than a sconce.
    def carried? : Bool
      !letter.nil?
    end
  end
end
