# Digs whole runs and prints the plus on the armor they hold.
#
#     crystal run --release script/loot-stats.cr -- [COUNT] [FIRST]
#
# COUNT runs from seed FIRST, floors 1 to 10 of each. Defaults: 200 runs from
# seed 1. It counts the armor lying about and the armor the monsters carry
# that fits a medium wearer. It prints the spread of pluses on each floor.
# It then takes a character who picks up all of it, and prints the best plus
# in each armor slot after floors 1, 5, 8 and 10, and the commonest sets of
# five at floor 10. Set XDG_STATE_HOME to a scratch directory first.
require "../src/roguelike"

count = (ARGV[0]? || "200").to_i
first = (ARGV[1]? || "1").to_u64

# The floors the best pieces are reported after.
REPORTED = {1, 5, 8, 10}

# The plus an empty slot reports.
EMPTY = Int32::MIN

by_floor = Hash(Int32, Hash(Int32, Int32)).new { |hash, key| hash[key] = Hash(Int32, Int32).new 0 }
pieces = Hash(Int32, Int32).new 0
best_after = Hash(Int32, Hash(Int32, Int32)).new { |hash, key| hash[key] = Hash(Int32, Int32).new 0 }
sets = Hash(String, Int32).new 0
slots = Roguelike::ArmorSlot.values

count.times do |index|
  game = Roguelike::Game.dug Roguelike::Rng.new(first + index)
  best = Hash(Roguelike::ArmorSlot, Int32).new EMPTY

  (1..10).each do |depth|
    ground = depth == 1 ? game.floor : game.dig(depth)
    found = [] of Roguelike::Item
    ground.each_pile { |_column, _row, pile| found.concat pile }
    ground.each_monster { |_column, _row, creature| found.concat creature.belongings }

    found.each do |item|
      slot = item.kind.slot
      next unless slot && item.fits?(Roguelike::Size::Medium)

      by_floor[depth][item.enchantment] += 1
      pieces[depth] += 1
      best[slot] = Math.max best[slot], item.enchantment
    end

    next unless REPORTED.includes? depth

    slots.each { |slot| best_after[depth][best[slot]] += 1 }
    sets[slots.map { |slot| best[slot] }.sort!.reverse!.join(" ")] += 1 if depth == 10
  end
end

# *tally* as shares of *total*, highest plus first.
def shares(tally : Hash(Int32, Int32), total : Int32) : String
  tally.keys.sort!.reverse!.join("  ") do |plus|
    label = plus == EMPTY ? "none" : "%+d" % plus
    "#{label} #{(tally[plus] * 100.0 / total).round(1)}%"
  end
end

puts "#{count} runs from seed #{first}"
puts
puts "Armor that fits a medium wearer, by plus"
(1..10).each do |depth|
  puts "  floor #{depth}, #{(pieces[depth] / count.to_f).round(1)} pieces: #{shares by_floor[depth], pieces[depth]}"
end
puts
puts "Best plus in each slot after picking up everything on floors 1 to N"
REPORTED.each { |depth| puts "  N = #{depth}: #{shares best_after[depth], count * slots.size}" }
puts
puts "Commonest sets of five at floor 10"
sets.to_a.sort_by! { |(_, seen)| -seen }.first(8).each do |set, seen|
  puts "  #{set}: #{(seen * 100.0 / count).round(1)}%"
end
