require "json"

module Roguelike
  # How fast one actor is, and how much of its next action it has paid for.
  #
  # Energy rather than division. An actor gains its speed in energy on every
  # tick, and an action costs a whole number of ticks. Over a hundred ticks a
  # normal actor gains ten thousand energy and takes a hundred one-tick
  # actions. A slime at eighty gains eight thousand and takes eighty.
  #
  # Leftover energy carries to the next tick, so the ratio holds over a run of
  # any length. Dividing the cost by the speed instead would round on every
  # action, and the error would accumulate.
  class Pace
    include JSON::Serializable

    # The energy in one tick.
    #
    # A normal actor gains this much per tick, and a one-tick action costs
    # this much.
    TICK = 100

    # What a normal actor gains in a tick.
    NORMAL = TICK

    # The slowest anything moves. An actor at no speed at all would never act
    # again, and the tick loop would not end.
    LEAST = 25

    # The fastest anything moves.
    MOST = 300

    # What a haste adds to the speed while it lasts.
    HASTE = 50

    # What a slow takes off it.
    SLOW = 40

    # What this actor gains in a tick before a haste or a slow.
    #
    # `Species#speed` for a creature, and `NORMAL` for the character.
    #
    # It has a default so that a save written before this field existed
    # loads. A field is optional in JSON only when its declaration carries
    # one.
    property base : Int32 = NORMAL

    # Energy banked toward the next action.
    #
    # It goes negative when an action costs more than was banked, which is
    # what makes an action of several ticks cost several ticks.
    property energy : Int32 = TICK

    # Ticks left on a haste. Zero for an actor nothing has hurried.
    getter hasted : Int32 = 0

    # Ticks left on a slow.
    getter slowed : Int32 = 0

    # A new pace at *base*, with one action already paid for.
    #
    # An actor starts ready. One that started empty would lose a tick to its
    # first step.
    def initialize(@base : Int32 = NORMAL, @energy : Int32 = TICK)
    end

    # What this actor gains in a tick as it stands.
    def speed : Int32
      found = @base
      found += HASTE if hurried?
      found -= SLOW if dragging?

      found.clamp LEAST, MOST
    end

    # Whether an action has been paid for.
    def ready? : Bool
      @energy >= TICK
    end

    # Whether something is hurrying this actor.
    def hurried? : Bool
      @hasted > 0
    end

    # Whether something is holding it back.
    def dragging? : Bool
      @slowed > 0
    end

    # Whether it is going at anything other than its own pace.
    def altered? : Bool
      hurried? || dragging?
    end

    # Banks one tick's worth of energy.
    def gain : Nil
      @energy += speed
    end

    # Holds an actor that is not acting at one action's worth.
    #
    # A sleeping creature is held here rather than banking, so it acts on the
    # tick it wakes and cannot bank a hundred turns of standing still into a
    # hundred steps.
    def rest : Nil
      @energy = TICK
    end

    # Takes the cost of an action off.
    def spend(cost : Int32) : Nil
      @energy -= cost
    end

    # Hurries this actor for *ticks* more.
    #
    # A second haste lasts longer rather than going faster. Five potions are
    # five times the time, not five times the speed.
    def hurry(ticks : Int32) : Nil
      @hasted += ticks
    end

    # Holds it back for *ticks* more.
    def drag(ticks : Int32) : Nil
      @slowed += ticks
    end

    # Takes a haste and a slow straight off.
    def settle : Nil
      @hasted = 0
      @slowed = 0
    end

    # Counts the two timers down one tick.
    def pass : Nil
      @hasted -= 1 if @hasted > 0
      @slowed -= 1 if @slowed > 0
    end

    # How many actions this actor takes while a normal one takes *actions*.
    #
    # For a readout and for a spec. It reads the speed rather than the energy,
    # so it says what the actor is doing now rather than where the rounding
    # happens to stand.
    def per(actions : Int32) : Int32
      actions * speed // NORMAL
    end

    def to_s(io : IO) : Nil
      io << "Pace(" << speed
      io << " energy=" << @energy
      io << " hasted=" << @hasted if hurried?
      io << " slowed=" << @slowed if dragging?
      io << ')'
    end
  end
end
