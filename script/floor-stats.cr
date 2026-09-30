# Digs many floors and prints how they are shaped.
#
#     crystal run --release script/floor-stats.cr -- [COUNT] [FIRST] [DEPTH]
#
# COUNT floors from seed FIRST, at depth DEPTH. Defaults: 1000 floors from
# seed 1 at depth 1. It prints the spread of areas and shapes, the loops in
# each floor, the corridors that run side by side, and how many floors the
# audit rejected on the first try.
require "../src/roguelike"
require "../src/roguelike/audit"

count = (ARGV[0]? || "1000").to_i
first = (ARGV[1]? || "1").to_u64
depth = (ARGV[2]? || "1").to_i

# The area of a floor before floors varied in size.
AVERAGE = 216 * 84

# How large a body of rock has to be to count as a large loop.
LARGE = 40

# The tallies for each layout: floors, loops, large loops, pairs.
BY_PLAN = Hash(String, Array(Int32)).new { |hash, key| hash[key] = [0, 0, 0, 0] }

# Adds what *generator* dug to the tallies. Answers whether it is sound.
def measure(generator, plan, areas, shapes, loops, pairs) : Bool
  floor = generator.floor
  tally = BY_PLAN[plan]
  tally[0] += 1
  tally[1] += Roguelike::Audit.loops(floor)
  tally[2] += Roguelike::Audit.loops(floor, LARGE)
  tally[3] += Roguelike::Audit.alongside(floor)
  areas << floor.columns * floor.rows * 100.0 / AVERAGE

  wide, tall = floor.columns, floor.rows
  ratio = wide >= tall ? wide / tall : -(tall / wide)
  shapes[ratio.abs < 1.25 ? "1:1" : ratio > 0 ? "wide #{ratio.round(1)}" : "tall #{(-ratio).round(1)}"] += 1

  loops << Roguelike::Audit.loops(floor)
  pairs << Roguelike::Audit.alongside(floor)
  Roguelike::Audit.faults(floor, generator.rooms).empty?
end

areas = [] of Float64
shapes = Hash(String, Int32).new 0
layouts = Hash(String, Int32).new 0
loops = [] of Int32
pairs = [] of Int32
rejected = 0
retried = 0
unsound = 0
kinds = Hash(String, Int32).new 0

count.times do |index|
  rng = Roguelike::Rng.new first + index
  id = Roguelike::World.id depth

  {% if Roguelike::Generator.has_constant?(:TRIES) %}
    generator = Roguelike::Generator.dug rng, id, depth
    retried += 1 if generator.attempt > 0
    rejected += generator.attempt
    generator.rejected.each { |fault| kinds[fault.sub(/ at .*|^\d+ /, "")] += 1 }
    layouts[generator.plan] += 1
    unsound += 1 unless measure(generator, generator.plan, areas, shapes, loops, pairs)
  {% else %}
    generator = Roguelike::Generator.new rng, id,
      Roguelike::Generator::COLUMNS, Roguelike::Generator::ROWS, depth
    generator.dig
    first_faults = Roguelike::Audit.faults generator.floor, generator.rooms
    unless first_faults.empty?
      retried += 1
      rejected += 1
      first_faults.each { |fault| kinds[fault.sub(/ at .*|^\d+ /, "")] += 1 }
    end
    layouts["tree"] += 1
    unsound += 1 unless measure(generator, "tree", areas, shapes, loops, pairs)
  {% end %}
end

def percentile(sorted : Array, share : Float64)
  sorted[((sorted.size - 1) * share).round.to_i]
end

sorted = areas.sort
puts "#{count} floors from seed #{first} at depth #{depth}"
puts
puts "area, percent of 216 by 84"
{0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0}.each do |share|
  puts "  p%-4d %6.1f" % [(share * 100).to_i, percentile(sorted, share)]
end
{ {0, 50}, {50, 75}, {75, 100}, {100, 150}, {150, 200}, {200, 300}, {300, 401} }.each do |low, high|
  many = areas.count { |area| area >= low && area < high }
  puts "  %3d-%-3d %5d" % [low, high, many]
end
puts
puts "shapes"
shapes.to_a.sort_by { |pair| -pair[1] }.first(10).each { |name, many| puts "  %-10s %5d" % [name, many] }
puts
puts "layouts"
layouts.to_a.sort_by { |pair| -pair[1] }.each { |name, many| puts "  %-10s %5d" % [name, many] }
puts
puts "loops per floor: mean %.2f, median %d, max %d" % [loops.sum / count.to_f, loops.sort[count // 2], loops.max]
puts "  floors with no loop   #{loops.count(&.zero?)}"
puts "  floors with 1-4       #{loops.count { |many| many >= 1 && many < 5 }}"
puts "  floors with 5 or more #{loops.count { |many| many >= 5 }}"
puts
puts "by layout             floors  loops  large loops  pairs side by side"
BY_PLAN.to_a.sort_by { |pair| -pair[1][0] }.each do |name, tally|
  many = tally[0].to_f
  puts "  %-18s %6d %6.1f %12.1f %8.2f" % [name, tally[0], tally[1] / many, tally[2] / many, tally[3] / many]
end
puts "  large means a body of rock of #{LARGE} squares or more"
puts
puts "corridors side by side: #{pairs.sum} pairs, on #{pairs.count(&.positive?)} floors"
puts
puts "audit: #{retried} floors failed the first try, #{rejected} tries rejected in all"
kinds.to_a.sort_by { |pair| -pair[1] }.each { |name, many| puts "  %-40s %5d" % [name, many] }
puts "  still unsound after retries: #{unsound}"
