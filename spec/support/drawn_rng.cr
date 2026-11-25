# A generator that answers the values it is given, in order.
#
# `Rng#below` takes a value under its limit as it is, modulo the range, so a
# spec can choose each roll. It raises once the values run out, which makes
# a spec fail when the code under it draws more than the spec expects.
class DrawnRng < Roguelike::Rng
  def initialize(values : Enumerable(Int))
    super 0_u64
    @values = Deque(UInt32).new
    values.each { |value| @values << value.to_u32 }
  end

  def next_u : UInt32
    @values.shift? || raise IndexError.new "drew more values than were given"
  end

  # How many values have not been drawn.
  def left : Int32
    @values.size
  end
end
