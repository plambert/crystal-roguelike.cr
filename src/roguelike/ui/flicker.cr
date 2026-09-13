module Roguelike::Ui
  # How a flame wavers.
  #
  # A burning light does not hold still. Its whole pool brightens and gutters
  # together, the way one flame does.
  #
  # Each flame moves on its own. Two torches in one room are not the same
  # flame and do not waver as one, so a shift is worked out per flame, from
  # where it stands. Where two pools overlap the squares they share take both
  # shifts: two flames guttering at once drop that ground twice as far, and
  # one guttering while the other flares leaves it where it was.
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

    # How many ticks one shift lasts.
    #
    # A value that changed on every tick would read as a strobe. Holding each
    # one for a moment reads as a flame.
    HOLD = 2

    # How likely a tick is to leave the light where it is, out of `SCALE`.
    STILL = 128

    # How likely the rest of a tick is to gutter rather than flare.
    #
    # A flame drops more often than it jumps. The two are out of what is left
    # once `STILL` is taken off.
    GUTTER = 76

    # What the chances are out of.
    SCALE = 256

    # The run's seed. Two runs from one seed flicker alike.
    getter seed : UInt64

    # Which tick the flame is on. `Session` advances it.
    property tick : Int32

    # Whether the flame moves at all.
    #
    # `--no-flicker` turns it off. A spec that is not about flicker turns it
    # off too, and reads a still map.
    property? burning : Bool

    def initialize(@seed : UInt64, @tick : Int32 = 0, @burning : Bool = true)
    end

    # How far the flames standing at *sources* have moved a square between
    # them this tick.
    #
    # The shifts add. A square no flame reaches does not move.
    def shift(sources : Array({Int32, Int32})) : Int32
      return 0 unless @burning
      return 0 if sources.empty?

      sources.sum { |flame| step_at flame[0], flame[1] }
    end

    # How far the flame standing at *x*, *y* has moved this tick.
    #
    # Between minus one and one. Most ticks leave it where it is.
    def step_at(x : Int32, y : Int32) : Int32
      return 0 unless @burning

      roll = roll_for @tick // HOLD, x, y
      drawn = (roll % SCALE).to_i
      return 0 if drawn < STILL

      (drawn - STILL) < GUTTER ? -1 : 1
    end

    # The number *phase* draws for a flame standing at *x*, *y*.
    #
    # FNV-1a over the seed, the phase and the flame, then `Rng.mix`. The same
    # derivation `Rng#derive` uses, and for the same reason: the answer has to
    # depend on all of its inputs and on nothing else.
    private def roll_for(phase : Int32, x : Int32, y : Int32) : UInt64
      hash = 0xcbf29ce484222325_u64

      {@seed, phase.to_u64!, x.to_u64!, y.to_u64!}.each do |part|
        8.times do |byte|
          hash ^= (part >> (byte * 8)) & 0xff
          hash &*= 0x100000001b3_u64
        end
      end

      Rng.mix hash
    end
  end
end
