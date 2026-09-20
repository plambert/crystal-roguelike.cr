require "../spec_helper"

Spectator.describe Roguelike::Names do
  def stream(seed : UInt64 = Playing::SEED) : Roguelike::Rng
    Roguelike::Rng.new(seed).derive "name"
  end

  describe ".roll" do
    it "rolls the same name from the same seed" do
      first = Array.new(200) { described_class.roll stream(9_u64) }
      again = Array.new(200) { described_class.roll stream(9_u64) }

      expect(again).to eq first
    end

    it "rolls a different name from a different seed" do
      expect(described_class.roll stream(1_u64))
        .not_to eq described_class.roll(stream 2_u64)
    end

    it "starts every name with a capital" do
      rng = stream

      500.times do
        found = described_class.roll rng
        expect(found[0]).to eq found[0].upcase
      end
    end

    it "rolls nothing shorter than the least" do
      rng = stream

      1_000.times do
        expect(described_class.roll(rng).size)
          .to be >= Roguelike::Names::LEAST
      end
    end

    # The status panel writes the name against a right-aligned level, and a
    # name too long for that is cut.
    it "rolls nothing longer than the panel holds" do
      rng = stream

      1_000.times { expect(described_class.roll(rng).size).to be <= 12 }
    end

    it "rolls names a save file can hold" do
      rng = stream

      1_000.times do
        expect(Roguelike::Save.slug described_class.roll(rng)).not_to be_empty
      end
    end

    it "rolls more than one name" do
      rng = stream
      found = Set(String).new
      200.times { found << described_class.roll rng }

      expect(found.size).to be > 100
    end
  end

  describe ".free" do
    it "rolls past a name already saved under" do
      store = Playing.store
      rng = stream
      taken = described_class.roll stream

      game = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)
      game.player.name = taken
      store.write game

      expect(described_class.free rng, store).not_to eq taken
    end

    it "rolls the first name with no store to check" do
      expect(described_class.free stream, nil).to eq described_class.roll(stream)
    end
  end
end
