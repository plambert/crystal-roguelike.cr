require "../spec_helper"

Spectator.describe Roguelike::Rng do
  # Enough draws that two generators agreeing by chance is not the
  # explanation, and few enough that the spec stays instant.
  def draws(rng : Roguelike::Rng, count : Int32 = 64) : Array(Int32)
    Array.new(count) { rng.rand 1_000_000 }
  end

  describe "reproducibility" do
    it "draws the same sequence from the same seed" do
      expect(draws(described_class.new(20260911_u64)))
        .to eq draws(described_class.new(20260911_u64))
    end

    it "draws a different sequence from a different seed" do
      expect(draws(described_class.new(20260911_u64)))
        .not_to eq draws(described_class.new(20260912_u64))
    end

    it "reproduces a run from the seed and stream it reports" do
      first = described_class.random.derive "worldgen", 3
      taken = draws first

      expect(draws(described_class.new(first.seed, first.stream))).to eq taken
    end
  end

  describe ".for" do
    it "takes the seed it is given" do
      expect(described_class.for(99_u64).seed).to eq 99_u64
    end

    it "finds a seed of its own when given none" do
      expect(described_class.for(nil).seed).to be_a UInt64
    end

    it "finds a different seed each time" do
      seeds = Array.new(16) { described_class.for(nil).seed }

      expect(seeds.uniq.size).to eq seeds.size
    end

    it "starts on the root stream" do
      expect(described_class.for(1_u64).stream).to eq Roguelike::Rng::ROOT_STREAM
    end
  end

  describe "#derive" do
    let(master) { described_class.new 20260911_u64 }

    it "keeps the run's seed, so every generator names the same run" do
      expect(master.derive("worldgen", 3).seed).to eq master.seed
    end

    it "answers the same sequence for the same name" do
      expect(draws(master.derive("worldgen", 3)))
        .to eq draws(master.derive("worldgen", 3))
    end

    it "answers a different sequence for a different name" do
      expect(draws(master.derive("worldgen", 3)))
        .not_to eq draws(master.derive("worldgen", 4))
    end

    it "separates domains sharing an id" do
      expect(draws(master.derive("worldgen", 3)))
        .not_to eq draws(master.derive("ai", 3))
    end

    it "separates runs sharing a name" do
      expect(draws(master.derive("worldgen", 3)))
        .not_to eq draws(described_class.new(20260912_u64).derive("worldgen", 3))
    end

    # The property the whole design exists for: what a child draws does not
    # depend on what the parent, or any sibling, did first.
    it "answers the same child however much the parent has been drawn from" do
      before = draws master.derive("worldgen", 3)
      1_000.times { master.rand 100 }
      master.derive "ai", 12
      master.derive "loot", 7

      expect(draws(master.derive("worldgen", 3))).to eq before
    end

    it "is path dependent, so a nested name is not a flattened one" do
      expect(master.derive("worldgen").derive("3").stream)
        .not_to eq master.derive("worldgen", 3).stream
    end

    it "does not commute" do
      expect(master.derive("a").derive("b").stream)
        .not_to eq master.derive("b").derive("a").stream
    end

    # Pinned so that changing the hash is a failing spec rather than a silent
    # break of every seed ever recorded. Regenerate these deliberately, never
    # to make a red spec green.
    it "derives a stream that is the same in every process and every build" do
      expect(master.derive("worldgen", 3).stream).to eq 16630584740655075460_u64
      expect(master.derive("ai", 12).stream).to eq 670043370366468092_u64
      expect(master.derive("worldgen").derive("3").stream)
        .to eq 12661003630200279824_u64
    end
  end

  describe "the Random surface" do
    it "answers everything Random builds on #next_u" do
      rng = described_class.new 7_u64

      expect(rng.rand(1..6)).to be_between 1, 6
      expect(%w[a b c].sample(rng)).to be_a String
      expect([1, 2, 3].shuffle(rng).sort!).to eq [1, 2, 3]
      expect([true, false]).to contain rng.next_bool
    end

    it "shuffles the same way under the same seed" do
      deck = (1..52).to_a

      expect(deck.shuffle(described_class.new(5_u64)))
        .to eq deck.shuffle(described_class.new(5_u64))
    end
  end

  describe "#to_s" do
    it "names the seed and the stream, which is what reproduces a failure" do
      expect(described_class.new(42_u64).to_s).to eq "Rng(seed=42, stream=0)"
      expect(described_class.new(42_u64, 9_u64).to_s)
        .to eq "Rng(seed=42, stream=9)"
    end
  end
end
