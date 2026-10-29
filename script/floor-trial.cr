# Starts the cautious trial bot on each floor and counts how its runs end.
#
#     crystal run --release script/floor-trial.cr -- [RUNS] [TURNS] [FIRST] [LAST] [SEED]
#
# RUNS games for each floor from FIRST to LAST, from seed SEED. Defaults: 40
# runs of at most 3000 turns on every floor from 1 to the amulet chamber, from
# seed 7000. Each run digs down to the floor, stands the character on its up
# staircase with that floor's `Trial::Matchup` kit and two potions of
# healing, and plays until the character dies, wins, leaves the floor or runs
# out of turns. A floor deeper than the last kit takes the last kit.
require "../src/roguelike"

# The cautious bot, playing a game already dug down to a floor.
class FloorBot < Roguelike::Trial::Cautious
  def initialize(seed : UInt64, game : Roguelike::Game)
    super(seed, false)
    @game = game
    @start = game.player.at
    @on = game.player.floor
  end
end

# A game from *seed* with the character on the up staircase of *depth*,
# carrying *kit*.
def arrive(seed : UInt64, depth : Int32, kit) : Roguelike::Game
  game = Roguelike::Game.dug Roguelike::Rng.new(seed)
  (depth - 1).times do
    stairs = game.floor.find(Roguelike::Terrain::StairsDown)
    raise "no staircase down on #{game.floor.id}" unless stairs

    game.player.move_to stairs
    game.descend
  end

  player = game.player
  player.gain Roguelike::Advancement.threshold(kit.level)
  player.heal 1000
  kit.gear.each do |piece|
    item = piece.item
    letter = player.inventory.add item
    slot = Roguelike::Slot.for item
    player.equipment.put slot, letter if slot && letter
  end
  2.times { player.inventory.add Roguelike::Item.new(Roguelike::ItemKind::HealingPotion) }
  game
end

runs = (ARGV[0]? || "40").to_i
turns = (ARGV[1]? || "3000").to_i
first = (ARGV[2]? || "1").to_i
last = (ARGV[3]? || Roguelike::World::VAULT.to_s).to_i
seed = (ARGV[4]? || "7000").to_u64
kits = Roguelike::Trial::Matchup::KITS

(first..last).each do |depth|
  kit = kits[(depth - 1).clamp(0, kits.size - 1)]
  tally = Hash(String, Int32).new 0
  killers = Hash(String, Int32).new 0

  runs.times do |index|
    game = arrive seed + index, depth, kit
    bot = FloorBot.new seed + index, game

    (turns * 2).times do
      break if game.over? || game.depth > depth || game.turn >= turns

      bot.turn
    end

    ending = if game.over?
               game.outcome.to_s.downcase
             elsif game.depth > depth
               "went down"
             else
               "still there"
             end
    tally[ending] += 1
    killer = game.killer
    killers[killer] += 1 if killer && game.outcome.died?
  end

  line = "floor #{depth} (kit D#{kit.depth}): " +
         tally.to_a.sort.map { |name, count| "#{name} #{count}" }.join(", ")
  unless killers.empty?
    line += "; killed by " +
            killers.to_a.sort_by { |_name, count| -count }.map { |name, count| "#{name} #{count}" }.join(", ")
  end
  puts line
end
