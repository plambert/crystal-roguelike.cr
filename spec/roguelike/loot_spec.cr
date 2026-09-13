require "../spec_helper"

Spectator.describe Roguelike::Loot do
  alias Condition = Roguelike::Condition
  alias Item = Roguelike::Item
  alias ItemClass = Roguelike::ItemClass
  alias Kind = Roguelike::ItemKind
  alias Loot = Roguelike::Loot
  alias Rng = Roguelike::Rng
  alias Species = Roguelike::Species

  # How many creatures of each species the distribution examples roll.
  ROLLS = 10_000

  # The seed they roll on. A failure names a run somebody can repeat.
  SEED = 20260912_u64

  # Everything *species* comes up with over `ROLLS` creatures.
  def rolled(species : Species, seed : UInt64 = SEED) : Array(Array(Item))
    rng = Rng.new(seed).derive "loot:#{species}"

    Array.new(ROLLS) { Loot.for species, rng }
  end

  describe ".for" do
    it "rolls the same loot twice from the same generator" do
      first = Loot.for Species::Goblin, Rng.new(7_u64)
      second = Loot.for Species::Goblin, Rng.new(7_u64)

      expect(first).to eq second
    end

    it "gives a creature nothing it should not have" do
      Species.values.each do |species|
        allowed = Loot.kinds species

        rolled(species).each do |carried|
          carried.each { |item| expect(allowed.includes? item.kind).to be_true }
        end
      end
    end

    # A slime has no hands. It has swallowed things, and it has coins in it.
    it "gives a slime no weapon and no armour" do
      rolled(Species::Slime).each do |carried|
        carried.each do |item|
          expect(item.kind.item_class.melee?).to be_false
          expect(item.kind.item_class.armour?).to be_false
        end
      end
    end

    it "lights whatever burns" do
      Species.values.each do |species|
        rolled(species).each do |carried|
          carried.each { |item| expect(item.lit?).to be_true if item.burns? }
        end
      end
    end

    it "never gives a creature two of the same draw" do
      rolled(Species::Orc).each do |carried|
        weapons = carried.count &.kind.item_class.melee?

        expect(weapons).to be <= 1
      end
    end
  end

  describe "how often a draw comes up" do
    # How far from the stated chance a share of ten thousand may land.
    #
    # Three points. The standard error of a share of ten thousand is under
    # half a point at any chance, so three is six of them: a table that
    # changed by a point would not fail this, and one that changed by five
    # would.
    TOLERANCE = 3.0

    # What share of *carried* holds a kind from *draw*.
    def share(carried : Array(Array(Item)), kinds : Hash(Kind, Int32)) : Float64
      held = carried.count do |items|
        items.any? { |item| kinds.has_key? item.kind }
      end

      held * 100.0 / carried.size
    end

    it "matches what each species' draws say" do
      Species.values.each do |species|
        carried = rolled species

        Loot.draws(species).each do |draw|
          expect(share carried, draw.kinds).to be_close draw.chance, TOLERANCE
        end
      end
    end

    it "holds from a second seed" do
      carried = rolled Species::Goblin, 99_u64

      Loot.draws(Species::Goblin).each do |draw|
        expect(share carried, draw.kinds).to be_close draw.chance, TOLERANCE
      end
    end
  end

  describe "which kind a draw comes up with" do
    # How far from its stated weight a kind's share of one draw may land.
    TOLERANCE = 3.0

    # What share of the items drawn from *kinds* is each kind.
    def shares(carried : Array(Array(Item)), kinds : Hash(Kind, Int32)) : Hash(Kind, Float64)
      found = carried.flatten.select { |item| kinds.has_key? item.kind }

      kinds.keys.to_h do |kind|
        {kind, found.count(&.kind.== kind) * 100.0 / Math.max(found.size, 1)}
      end
    end

    it "matches the weights in the weapon table" do
      found = shares rolled(Species::Orc), Loot::WEAPONS
      total = Loot::WEAPONS.values.sum

      Loot::WEAPONS.each do |kind, weight|
        expect(found[kind]).to be_close weight * 100.0 / total, TOLERANCE
      end
    end

    it "matches the weights in the armour table" do
      found = shares rolled(Species::Orc), Loot::ARMOUR
      total = Loot::ARMOUR.values.sum

      Loot::ARMOUR.each do |kind, weight|
        expect(found[kind]).to be_close weight * 100.0 / total, TOLERANCE
      end
    end
  end

  describe "how well made it is" do
    TOLERANCE = 3.0

    # Most of what a monster carries is battered. That is what makes a
    # masterwork piece off a dead orc worth something.
    it "matches the condition table" do
      made = rolled(Species::Orc).flatten.select &.kind.enchantable?
      total = Loot::CONDITIONS.sum { |pair| pair[1] }

      Loot::CONDITIONS.each do |condition, weight|
        share = made.count(&.condition.== condition) * 100.0 / made.size

        expect(share).to be_close weight * 100.0 / total, TOLERANCE
      end
    end

    it "leans further toward damaged than what is lying about the floor" do
      carried = Loot::CONDITIONS.to_h
      littered = Roguelike::Items::CONDITIONS.to_h

      expect(carried[Condition::Damaged]).to be > littered[Condition::Damaged]
    end
  end

  # What each species carries, written out.
  #
  # Every number the tables hold is in here: how often each draw comes up and
  # what share of it each kind takes. A change to any of them shows as a diff
  # rather than as a spec nobody can read.
  describe "drawn" do
    def table : Array(String)
      lines = [] of String

      Species.values.each do |species|
        carried = rolled species
        lines << "#{species.label} over #{ROLLS} of them"

        Loot.draws(species).each do |draw|
          held = carried.count { |items| items.any? { |item| draw.kinds.has_key? item.kind } }
          lines << "  %5.1f%% of the time (%d%% stated)" % [
            held * 100.0 / carried.size, draw.chance,
          ]

          found = carried.flatten.select { |item| draw.kinds.has_key? item.kind }
          draw.kinds.each_key do |kind|
            taken = found.count &.kind.== kind
            lines << "    %-16s %5.1f%%" % [
              kind.label, taken * 100.0 / Math.max(found.size, 1),
            ]
          end
        end
      end

      lines
    end

    it "rolls what it rolled last time" do
      drawn = table.join "\n"

      expect(drawn).to eq Fixture.expected("loot/tables.txt", drawn)
    end
  end
end
