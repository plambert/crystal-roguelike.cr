require "json"
require "./direction"

module Roguelike
  # What sort of fitting stands on a square.
  #
  # A fixture is part of the room rather than loot. It is never picked up,
  # dropped or carried, so it is not an `Item` and it takes no inventory
  # letter.
  enum FixtureKind
    # An iron bracket holding a torch. Mounted on a wall, or standing on the
    # floor on a foot of its own.
    Sconce

    # What a floor file writes for one of these, unlit.
    def mark : Char
      case self
      in .sconce? then '|'
      end
    end

    # :ditto:, lit.
    def lit_mark : Char
      case self
      in .sconce? then '!'
      end
    end

    # How far one of these throws light when it is mounted on a wall.
    def light : Int32
      case self
      in .sconce? then 7
      end
    end

    # What it is called.
    def label : String
      case self
      in .sconce? then "sconce"
      end
    end

    # Which kind a floor file's *mark* names, and whether it is alight.
    # Answers `nil` for a character that names no fixture.
    def self.from_mark?(mark : Char) : {FixtureKind, Bool}?
      values.each do |kind|
        return {kind, false} if mark == kind.mark
        return {kind, true} if mark == kind.lit_mark
      end

      nil
    end
  end

  # One fitting standing on one square of a floor.
  #
  # A sconce stands on the open square beside the wall it is bolted to, not
  # in the wall itself. Light comes out of open air, which is where the flame
  # is, and the wall keeps whatever rock it is cut from. A sconce written into
  # the wall would make a granite wall and a sandstone wall the same terrain.
  #
  # `#attached` is the wall it is bolted to. A fixture with none stands on its
  # own foot on the floor.
  class Fixture
    include JSON::Serializable

    # What sort of fitting it is.
    getter kind : FixtureKind

    # Whether it is alight.
    getter? lit : Bool

    # Which way the wall it is bolted to lies. `nil` for one standing free on
    # the floor.
    getter attached : Direction?

    def initialize(@kind : FixtureKind = FixtureKind::Sconce,
                   @lit : Bool = false,
                   @attached : Direction? = nil)
    end

    # How much less light a fixture standing on the floor throws.
    #
    # A flame up on a wall clears the furniture and reaches further than the
    # same flame at ankle height.
    FLOOR_PENALTY = 1

    # How far this fixture throws light. Zero while it is not alight.
    #
    # One bolted to a wall throws the whole radius. One standing on its own
    # foot throws less, because the flame is at ankle height.
    def light : Int32
      return 0 unless @lit
      return @kind.light if @attached

      Math.max @kind.light - FLOOR_PENALTY, 1
    end

    # Whether this fixture is bolted to a wall.
    def mounted? : Bool
      !@attached.nil?
    end

    # Sets it alight. Answers whether that was a change.
    def kindle : Bool
      return false if @lit

      @lit = true
      true
    end

    # Puts it out. Answers whether that was a change.
    def douse : Bool
      return false unless @lit

      @lit = false
      true
    end

    # What this fixture is called.
    def label : String
      @lit ? "lit #{@kind.label}" : @kind.label
    end

    # A sentence about it, for the examine pane.
    def description : String
      holding = @lit ? "a burning torch" : "a burnt-out torch"
      standing = @attached ? "An iron bracket on the wall" : "An iron stand"

      "#{standing} holding #{holding}"
    end

    def ==(other : Fixture) : Bool
      @kind == other.kind && @lit == other.lit? && @attached == other.attached
    end

    def to_s(io : IO) : Nil
      io << "Fixture(" << @kind
      io << " lit" if @lit
      io << " on " << @attached if @attached
      io << ')'
    end
  end
end
