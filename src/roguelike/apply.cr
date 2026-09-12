module Roguelike
  # Something the character could apply.
  #
  # Two things answer to `a`. A carried torch or candle is named by its
  # inventory letter. A sconce is named by where it stands on the floor. One
  # record covers both, so the menu that offers them is one list.
  #
  # A `#letter` says it is carried. No letter says it is the fixture at
  # `#x`, `#y`.
  record Apply,
    letter : Char? = nil,
    x : Int32 = 0,
    y : Int32 = 0 do
    # The carried item under *letter*.
    def self.carried(letter : Char) : Apply
      new letter: letter
    end

    # The fixture at *x*, *y*.
    def self.fixture(x : Int32, y : Int32) : Apply
      new x: x, y: y
    end

    # Whether this names a carried item rather than a sconce.
    def carried? : Bool
      !letter.nil?
    end
  end
end
