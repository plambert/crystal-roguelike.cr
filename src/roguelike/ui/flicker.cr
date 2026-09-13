module Roguelike::Ui
  # How a flame wavers.
  #
  # A burning light does not hold still. Its pool brightens and gutters, and
  # the edge of it moves most, because that is where one step of brightness is
  # the width of a square.
  #
  # This is drawn rather than played. It shifts which step of `Palette::RAMP`
  # a square is drawn at and changes nothing the game decides: no square comes
  # into sight or goes out of it, nothing is remembered or forgotten, and no
  # turn is taken. A run started from a seed plays out the same whatever the
  # clock did while it was running.
  #
  # `Session` advances `#tick` on a timer through `App#after`. That is the one
  # thing in the game driven by a clock rather than a turn.
  #
  # The shift for a square is worked out from the seed, the tick and the
  # square, so it holds no state and the same tick always looks the same.
  class Flicker
    # How long one tick lasts.
    PERIOD = 140.milliseconds

    # What a square's light level has to be under for it to waver at all.
    #
    # The edge of a pool moves. The square the flame stands on does not.
    EDGE = 6

    # How likely a square at the very edge is to move, out of `SCALE`.
    MOST = 80

    # How much less likely each step further in is.
    FALLOFF = 13

    # What the chances are out of.
    SCALE = 256

    # The run's seed. Two runs from one seed flicker alike.
    getter seed : UInt64

    # Which tick the flame is on. `Session` advances it.
    property tick : Int32

    # Whether the flame moves at all. A spec that is not about flicker turns
    # it off and reads a still map.
    property? burning : Bool

    def initialize(@seed : UInt64, @tick : Int32 = 0, @burning : Bool = true)
    end

    # How far to shift the drawn step of *x*, *y*.
    #
    # A square with no flame on it does not move. Nor does one deep inside a
    # pool, where the light is strong enough that one step either way would
    # not show.
    def shift(x : Int32, y : Int32, level : Int32, kind : LightKind?) : Int32
      return 0 unless @burning
      return 0 unless kind.try &.flame?
      return 0 if level <= 0 || level >= EDGE

      odds = chance level
      roll = roll_for x, y
      return 0 if roll % SCALE >= odds

      (roll // SCALE) % 2 == 0 ? -1 : 1
    end

    # How likely a square at *level* is to move, out of `SCALE`.
    def chance(level : Int32) : Int32
      return 0 if level <= 0 || level >= EDGE

      Math.max MOST - (level - 1) * FALLOFF, 1
    end

    # The number this tick draws for *x*, *y*.
    #
    # FNV-1a over the seed, the tick and the square, then `Rng.mix`. The same
    # derivation `Rng#derive` uses, and for the same reason: the answer has to
    # depend on all of its inputs and on nothing else.
    private def roll_for(x : Int32, y : Int32) : UInt64
      hash = 0xcbf29ce484222325_u64

      {@seed, @tick.to_u64!, x.to_u64!, y.to_u64!}.each do |part|
        8.times do |byte|
          hash ^= (part >> (byte * 8)) & 0xff
          hash &*= 0x100000001b3_u64
        end
      end

      Rng.mix hash
    end
  end
end
