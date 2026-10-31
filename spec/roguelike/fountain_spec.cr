require "../spec_helper"

Spectator.describe "a fountain" do
  alias Generator = Roguelike::Generator
  alias Rng = Roguelike::Rng
  alias Terrain = Roguelike::Terrain
  alias World = Roguelike::World
  alias Library = Roguelike::Ui::ThemeLibrary
  alias Palette = Roguelike::Ui::Palette

  # How many seeds the share of watered floors is measured over.
  SEEDS = 2000

  describe "the terrain" do
    it "is walked through and seen through" do
      expect(Terrain::Fountain.passable?).to be_true
      expect(Terrain::Fountain.blocks_sight?).to be_false
    end

    it "is written in a floor file as {" do
      expect(Terrain::Fountain.mark).to eq '{'
      expect(Terrain.from_mark '{').to eq Terrain::Fountain
    end

    it "is not bare floor, so nothing else is put down on it" do
      expect(Terrain::Fountain.floor?).to be_false
    end

    it "reads at 4.5 to 1 on the ground in every built-in theme" do
      Library::BUILT_INS.each do |named|
        theme = named.theme
        ratio = Palette.contrast theme["fountain"], theme["ground"]
        expect(ratio).to be >= 4.5, "#{named.name}: the fountain is #{ratio.round 2} to 1"
      end
    end
  end

  describe "where the generator puts one" do
    it "is never on floor 1 or in the chamber under the last floor" do
      (1_u64..200_u64).each do |seed|
        rng = Rng.new seed
        expect(Generator.fountain?(rng, World.id(1))).to be_false
        expect(Generator.fountain?(rng, World.id(World::VAULT))).to be_false
      end
    end

    it "is decided by the seed alone" do
      (1_u64..50_u64).each do |seed|
        first = Generator::WATERED.map { |depth| Generator.fountain? Rng.new(seed), World.id(depth) }
        again = Generator::WATERED.map { |depth| Generator.fountain? Rng.new(seed), World.id(depth) }
        expect(again).to eq first
      end
    end

    it "is on about 60 floors in a hundred" do
      watered = 0
      total = 0
      (1_u64..SEEDS.to_u64).each do |seed|
        rng = Rng.new seed
        Generator::WATERED.each do |depth|
          total += 1
          watered += 1 if Generator.fountain? rng, World.id(depth)
        end
      end

      share = watered * 100.0 / total
      expect(share).to be_within(3.0).of(Generator::FOUNTAIN)
    end

    it "leaves two floors in a row dry in most runs" do
      dry = (1_u64..SEEDS.to_u64).count do |seed|
        rng = Rng.new seed
        flags = Generator::WATERED.map { |depth| Generator.fountain? rng, World.id(depth) }
        flags.each_cons_pair.any? { |one, two| !one && !two }
      end

      expect(dry * 100.0 / SEEDS).to be >= 50.0
    end

    it "puts one fountain in a room of each floor that has one, and none elsewhere" do
      (1_u64..60_u64).each do |seed|
        depth = 2 + (seed % 9).to_i
        id = World.id depth
        rng = Rng.new seed
        dug = Generator.dug rng, id, depth
        found = [] of {Int32, Int32}
        dug.floor.each { |column, row, tile| found << {column, row} if tile.terrain.fountain? }

        unless Generator.fountain? rng, id
          expect(found).to be_empty, "seed #{seed} floor #{depth}"
          next
        end

        expect(found.size).to eq(1), "seed #{seed} floor #{depth}"
        expect(dug.zones.any? &.holds?(*found.first)).to be_true
      end
    end

    it "is not in the chamber under the last floor" do
      chamber = Generator.chamber
      expect(chamber.find Terrain::Fountain).to be_nil
    end
  end
end
