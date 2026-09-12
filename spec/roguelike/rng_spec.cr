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

    it "reproduces a run from the seed it reports" do
      first = described_class.random
      taken = draws first

      expect(draws(described_class.new(first.seed))).to eq taken
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
    it "names the seed, which is what makes a failure reproducible" do
      expect(described_class.new(42_u64).to_s).to eq "Rng(seed=42)"
    end
  end
end
