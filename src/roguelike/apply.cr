require "../roguelike"

module Roguelike
  # Something the character could apply.
  #
  # Three things answer to `a`. A carried torch or candle is named by its
  # inventory letter. A sconce is named by where it stands on the floor. An
  # iron spike is named by its letter and by the door it goes into. One record
  # covers all three, so the menu that offers them is one list.
  #
  # A `#letter` says it is carried. No letter says it is the fixture at
  # `#x`, `#y`. A letter with `#aimed?` says it goes into the door at `#x`,
  # `#y`.
  record Apply,
    letter : Char? = nil,
    x : Int32 = 0,
    y : Int32 = 0,
    aimed : Bool = false do
    # The carried item under *letter*.
    def self.carried(letter : Char) : Apply
      new letter: letter
    end

    # The fixture at *x*, *y*.
    def self.fixture(x : Int32, y : Int32) : Apply
      new x: x, y: y
    end

    # The carried item under *letter*, used on the square *x*, *y*.
    def self.aimed(letter : Char, x : Int32, y : Int32) : Apply
      new letter: letter, x: x, y: y, aimed: true
    end

    # Whether this names a carried item rather than a sconce.
    def carried? : Bool
      !letter.nil?
    end

    # Whether this names a carried item used on a square.
    def aimed? : Bool
      aimed
    end
  end
end
