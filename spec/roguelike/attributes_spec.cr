require "../spec_helper"

Spectator.describe Roguelike::Attributes do
  alias Which = Roguelike::Attributes::Which

  describe "a default set" do
    it "is average all round" do
      expect(described_class.new.to_a)
        .to eq [Roguelike::Attributes::AVERAGE] * 5
    end

    it "has a modifier of nothing" do
      Which.values.each do |which|
        expect(described_class.new.modifier(which)).to eq 0
      end
    end
  end

  describe ".modifier" do
    it "is zero at average" do
      expect(described_class.modifier(10)).to eq 0
      expect(described_class.modifier(11)).to eq 0
    end

    it "rises one for every two points above average" do
      expect(described_class.modifier(12)).to eq 1
      expect(described_class.modifier(14)).to eq 2
      expect(described_class.modifier(18)).to eq 4
    end

    it "falls one for every two points below average" do
      expect(described_class.modifier(8)).to eq -1
      expect(described_class.modifier(6)).to eq -2
      expect(described_class.modifier(3)).to eq -4
    end
  end

  describe "#[]" do
    it "answers the score a name asks for" do
      scores = described_class.new 3, 6, 9, 12, 15

      expect(scores[Which::Strength]).to eq 3
      expect(scores[Which::Dexterity]).to eq 6
      expect(scores[Which::Constitution]).to eq 9
      expect(scores[Which::Intelligence]).to eq 12
      expect(scores[Which::Stealth]).to eq 15
    end
  end

  describe "#with" do
    it "changes one score and leaves the rest" do
      scores = described_class.new(3, 6, 9, 12, 15).with Which::Constitution, 18

      expect(scores.constitution).to eq 18
      expect(scores.strength).to eq 3
      expect(scores.stealth).to eq 15
    end
  end

  describe "Which" do
    it "names every score differently in two letters" do
      shorts = Which.values.map &.short

      expect(shorts.uniq.size).to eq 5
      expect(shorts).to eq %w[St Dx Cn In Sl]
    end

    it "names every score in a word too" do
      expect(Which::Constitution.label).to eq "constitution"
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      scores = described_class.new 3, 6, 9, 12, 15

      expect(described_class.from_json(scores.to_json).to_a).to eq scores.to_a
    end
  end
end
