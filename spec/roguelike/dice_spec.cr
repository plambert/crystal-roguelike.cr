require "../spec_helper"

Spectator.describe Roguelike::Dice do
  describe ".parse" do
    it "reads dice with a bonus" do
      dice = described_class.parse "2d6+1"

      expect(dice.count).to eq 2
      expect(dice.sides).to eq 6
      expect(dice.bonus).to eq 1
    end

    it "reads dice without one" do
      expect(described_class.parse("1d8").bonus).to eq 0
    end

    it "reads a penalty" do
      expect(described_class.parse("1d8-2").bonus).to eq -2
    end

    it "reads a bonus on its own" do
      dice = described_class.parse "+3"

      expect(dice.count).to eq 0
      expect(dice.bonus).to eq 3
    end

    it "refuses anything else" do
      expect { described_class.parse "wat" }.to raise_error ArgumentError, /not dice/
      expect { described_class.parse "" }.to raise_error ArgumentError, /not dice/
    end

    it "reads back what it writes" do
      %w[2d6+1 1d8 1d8-2 +3].each do |text|
        expect(described_class.parse(text).to_s).to eq text
      end
    end
  end

  describe "the range of a throw" do
    it "knows the lowest and the highest" do
      dice = described_class.new 2, 6, 1

      expect(dice.minimum).to eq 3
      expect(dice.maximum).to eq 13
    end

    it "knows the mean" do
      expect(described_class.new(2, 6, 1).average).to eq 8.0
      expect(described_class.new(1, 6).average).to eq 3.5
    end
  end

  describe "#roll" do
    it "stays inside the range, over many throws" do
      dice = described_class.new 3, 6, 2
      rng = Roguelike::Rng.new 20260911_u64

      1_000.times do
        thrown = dice.roll rng
        expect(thrown).to be >= dice.minimum
        expect(thrown).to be <= dice.maximum
      end
    end

    it "throws the same sequence from the same seed" do
      dice = described_class.new 2, 8
      first = Array.new(50) { dice.roll Roguelike::Rng.new(7_u64) }
      again = Array.new(50) { dice.roll Roguelike::Rng.new(7_u64) }

      expect(first).to eq again
    end

    it "reaches both ends of the range" do
      dice = described_class.new 1, 4
      rng = Roguelike::Rng.new 20260911_u64
      thrown = Array.new(500) { dice.roll rng }

      expect(thrown.min).to eq 1
      expect(thrown.max).to eq 4
    end

    it "throws nothing at all for no dice" do
      expect(Roguelike::Dice::NONE.roll(Roguelike::Rng.new(1_u64))).to eq 0
      expect(Roguelike::Dice::NONE.none?).to be_true
    end
  end

  describe "#with_bonus" do
    it "adds to the bonus and leaves the dice" do
      dice = described_class.new(1, 8, 1).with_bonus 2

      expect(dice.to_s).to eq "1d8+3"
    end
  end

  describe "a die with no sides" do
    it "is refused" do
      expect { described_class.new 1, 0 }.to raise_error ArgumentError
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      dice = described_class.new 2, 6, 1

      expect(described_class.from_json(dice.to_json).to_s).to eq dice.to_s
    end
  end
end
