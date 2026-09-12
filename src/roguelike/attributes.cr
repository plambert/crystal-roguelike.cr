require "json"

module Roguelike
  # What a creature is made of.
  #
  # Five scores. Each runs from `MINIMUM` to `MAXIMUM`, and `AVERAGE` is what
  # an unremarkable person has. `#modifier` turns a score into the number that
  # goes into a roll.
  struct Attributes
    include JSON::Serializable

    # The lowest a score goes.
    MINIMUM = 3

    # The highest a score goes without magic.
    MAXIMUM = 18

    # What an unremarkable person has. It gives a modifier of zero.
    AVERAGE = 10

    # How much a creature carries, and how hard it hits with a held weapon.
    getter strength : Int32

    # How well a creature dodges, and how well it throws and shoots.
    getter dexterity : Int32

    # How much punishment a creature takes. Hit points come from this.
    getter constitution : Int32

    # How well a creature reads a scroll or aims a wand.
    getter intelligence : Int32

    # How quietly a creature moves. Detection ranges come from this.
    getter stealth : Int32

    def initialize(@strength : Int32 = AVERAGE,
                   @dexterity : Int32 = AVERAGE,
                   @constitution : Int32 = AVERAGE,
                   @intelligence : Int32 = AVERAGE,
                   @stealth : Int32 = AVERAGE)
    end

    # The number *score* adds to a roll.
    #
    # Zero at `AVERAGE`. One more for every two points above it. One less for
    # every two points below.
    def self.modifier(score : Int32) : Int32
      (score - AVERAGE) // 2
    end

    # :ditto:
    def modifier(which : Which) : Int32
      Attributes.modifier self[which]
    end

    # The score *which* names.
    def [](which : Which) : Int32
      case which
      in .strength?     then @strength
      in .dexterity?    then @dexterity
      in .constitution? then @constitution
      in .intelligence? then @intelligence
      in .stealth?      then @stealth
      end
    end

    # A copy with *which* set to *score*.
    def with(which : Which, score : Int32) : Attributes
      held = Attributes::Which.values.map { |name| name == which ? score : self[name] }

      Attributes.new held[0], held[1], held[2], held[3], held[4]
    end

    # Every score, in the order `Which` names them.
    def to_a : Array(Int32)
      Which.values.map { |which| self[which] }
    end

    def to_s(io : IO) : Nil
      io << "Attributes("
      Which.values.each_with_index do |which, index|
        io << ' ' if index > 0
        io << which.short << '=' << self[which]
      end
      io << ')'
    end

    # Which of the five a number is.
    #
    # The members are in the order a status line writes them.
    enum Which
      Strength
      Dexterity
      Constitution
      Intelligence
      Stealth

      # Two letters, for a status line with no room for more.
      def short : String
        case self
        in .strength?     then "St"
        in .dexterity?    then "Dx"
        in .constitution? then "Cn"
        in .intelligence? then "In"
        in .stealth?      then "Sl"
        end
      end

      # The whole word, for a readout with room for it.
      def label : String
        to_s.downcase
      end
    end
  end
end
