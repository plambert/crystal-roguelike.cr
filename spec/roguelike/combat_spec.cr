require "../spec_helper"

Spectator.describe Roguelike::Combat do
  alias Blow = Roguelike::Blow
  alias Combat = Roguelike::Combat
  alias Dice = Roguelike::Dice
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Rng = Roguelike::Rng
  alias Slot = Roguelike::Slot
  alias Species = Roguelike::Species

  describe ".lands?" do
    it "lands when the face and the bonus reach the target plus the armor" do
      expect(Combat.lands? 12, 0, 2).to be_true
      expect(Combat.lands? 10, 2, 2).to be_true
    end

    it "misses when they fall short" do
      expect(Combat.lands? 11, 0, 2).to be_false
      expect(Combat.lands? 9, 0, 0).to be_false
    end

    it "lands on the top face whatever the armor is" do
      expect(Combat.lands? Combat::CRITICAL, -20, 99).to be_true
    end

    it "misses on the bottom face whatever the bonus is" do
      expect(Combat.lands? Combat::FUMBLE, 99, 0).to be_false
    end
  end

  describe ".swing" do
    it "rolls damage on a hit and none on a miss" do
      hits = 0
      misses = 0

      200.times do |index|
        blow = Combat.swing Rng.new(7_u64, index.to_u64), 0, 2, Dice.new(1, 6)

        if blow.hit?
          hits += 1
          expect(blow.damage).to be >= Combat::LEAST
        else
          misses += 1
          expect(blow.damage).to eq 0
        end
      end

      expect(hits).to be > 0
      expect(misses).to be > 0
    end

    it "never lets a landed swing do less than the least damage" do
      # A slime's strength takes one off its 1d4. A one on the die would
      # otherwise do nothing at all. The bottom face still misses, and a miss
      # does nothing by design.
      100.times do |index|
        blow = Combat.swing Rng.new(11_u64, index.to_u64), 20, 0, Dice.new(1, 4, -1)
        next unless blow.hit?

        expect(blow.damage).to be >= Combat::LEAST
      end
    end

    it "rolls the same numbers from the same generator" do
      one = Combat.swing Rng.new(99_u64), 1, 3, Dice.new(1, 8)
      two = Combat.swing Rng.new(99_u64), 1, 3, Dice.new(1, 8)

      expect(one.roll).to eq two.roll
      expect(one.damage).to eq two.damage
    end

    it "records what the swing was against" do
      blow = Combat.swing Rng.new(5_u64), 2, 4, Dice.new(1, 6)

      expect(blow.bonus).to eq 2
      expect(blow.against).to eq 4
      expect(blow.total).to eq blow.roll + 2
    end
  end

  describe Roguelike::Blow do
    it "knows the face that always lands" do
      expect(Blow.new(Combat::CRITICAL, 0, 0, true, 3).critical?).to be_true
      expect(Blow.new(19, 0, 0, true, 3).critical?).to be_false
    end

    it "knows the face that never lands" do
      expect(Blow.new(Combat::FUMBLE, 0, 0, false, 0).fumble?).to be_true
      expect(Blow.new(2, 0, 0, false, 0).fumble?).to be_false
    end

    it "writes itself out" do
      expect(Blow.new(14, 2, 3, true, 5).to_s).to eq "Blow(d20 14+2 vs 3 hit 5)"
      expect(Blow.new(4, -1, 3, false, 0).to_s).to eq "Blow(d20 4-1 vs 3 miss)"
    end
  end

  describe "what a creature brings to a fight" do
    it "adds a monster's dexterity to its swing" do
      goblin = Monster.new Species::Goblin, 0, 0, "band"

      expect(goblin.to_hit).to eq Roguelike::Attributes.modifier(13)
    end

    it "adds a monster's hide and dexterity to its armor class" do
      expect(Monster.new(Species::Goblin, 0, 0, "band").armor_class).to eq 3
      expect(Monster.new(Species::Orc, 0, 0, "band").armor_class).to eq 4
    end

    # A slime is slow enough that its dexterity takes more off than its hide
    # puts on. Armor class stops at zero rather than going below it.
    it "never gives a monster an armor class below zero" do
      expect(Monster.new(Species::Slime, 0, 0, "band").armor_class).to eq 0
    end

    it "adds a monster's strength to its damage" do
      orc = Monster.new Species::Orc, 0, 0, "band"

      expect(orc.damage).to eq Species::Orc.damage.with_bonus(2)
    end

    it "adds the character's dexterity to their swing" do
      player = Player.new "floor", 0, 0,
        Roguelike::Attributes.new(dexterity: 16)

      expect(player.to_hit).to eq 3
    end

    it "adds the wielded weapon's enchantment and condition" do
      player = Player.new "floor", 0, 0
      sword = Item.new Kind::ShortSword, enchantment: 2,
        condition: Roguelike::Condition::Damaged
      letter = player.inventory.add sword
      player.equipment.put Slot::Melee, letter if letter

      expect(player.to_hit).to eq 1
    end
  end

  # A hundred exchanges from one seed, written out.
  #
  # Every number the maths reads is in here: the character's swing bonus and
  # dice, each species' armor class, swing bonus and dice, and both rolls of
  # every exchange. A change to any of them shows as a diff rather than as a
  # spec nobody can read.
  describe "a hundred exchanges" do
    # The seed the fixture was written from.
    SEED = 20260912_u64

    # Which species takes exchange *index*. The three take turns, so every
    # species' numbers are in the fixture.
    def combatant(index : Int32) : Species
      Species.values[index % Species.values.size]
    end

    def transcript : Array(String)
      rng = Rng.new(SEED).derive "combat"
      player = Player.new "floor", 0, 0
      lines = [] of String

      100.times do |index|
        if index == 50
          letter = player.inventory.add Item.new(Kind::ShortSword)
          player.equipment.put Slot::Melee, letter if letter
        end

        creature = Monster.new combatant(index), 1, 0, "band"

        forward = Combat.swing rng, player.to_hit, creature.armor_class,
          player.damage
        back = Combat.swing rng, creature.to_hit, player.armor_class,
          creature.damage

        lines << ("%3d %-6s  you %s  it %s" % [
          index, creature.label, written(forward), written(back),
        ]).rstrip
      end

      lines
    end

    # One swing on one line, the same width every time.
    def written(blow : Blow) : String
      "d%-2d %+d vs %d %s" % [
        blow.roll, blow.bonus, blow.against,
        blow.hit? ? "hit %2d" % blow.damage : "miss  ",
      ]
    end

    it "rolls what it rolled last time" do
      drawn = transcript.join "\n"

      expect(drawn).to eq Fixture.expected("combat/exchanges.txt", drawn)
    end

    it "rolls the same sequence twice from the same seed" do
      expect(transcript).to eq transcript
    end
  end
end
