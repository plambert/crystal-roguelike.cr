require "../spec_helper"

Spectator.describe Roguelike::Advancement do
  describe ".max_hit_points" do
    it "starts at the base for an average character" do
      expect(described_class.max_hit_points(1, 10))
        .to eq Roguelike::Advancement::BASE_HIT_POINTS
    end

    it "rises by the same amount at every level" do
      steps = (1..6).map { |level| described_class.max_hit_points level, 10 }
      gaps = steps.each_cons(2).map { |pair| pair[1] - pair[0] }.to_a

      expect(gaps.uniq).to eq [Roguelike::Advancement::HIT_POINTS_PER_LEVEL]
    end

    # Constitution counts once per level. A tough character pulls further
    # ahead as they grow.
    it "counts constitution once per level" do
      low = described_class.max_hit_points 5, 10
      high = described_class.max_hit_points 5, 16

      expect(high - low).to eq 5 * Roguelike::Attributes.modifier(16)
    end

    it "never falls below one, however weak the character" do
      expect(described_class.max_hit_points(1, 3)).to be >= 1
    end

    it "stops rising past the last level" do
      cap = Roguelike::Advancement::MAX_LEVEL

      expect(described_class.max_hit_points(cap + 5, 10))
        .to eq described_class.max_hit_points(cap, 10)
    end
  end

  describe ".threshold" do
    it "is nothing at the first level" do
      expect(described_class.threshold(1)).to eq 0
    end

    it "doubles at every level" do
      steps = (2..8).map { |level| described_class.threshold level }

      expect(steps.each_cons(2).all? { |pair| pair[1] == pair[0] * 2 }).to be_true
    end

    it "starts where it says it does" do
      expect(described_class.threshold(2)).to eq Roguelike::Advancement::FIRST_THRESHOLD
    end
  end

  describe ".level_for" do
    # Every threshold raises the level exactly once. One point short of it
    # does not.
    it "raises the level at each threshold and not before" do
      (2..Roguelike::Advancement::MAX_LEVEL).each do |level|
        needed = described_class.threshold level

        expect(described_class.level_for(needed - 1)).to eq level - 1
        expect(described_class.level_for(needed)).to eq level
      end
    end

    it "starts at the first level with nothing" do
      expect(described_class.level_for(0)).to eq 1
    end

    it "stops at the last level" do
      expect(described_class.level_for(Int32::MAX))
        .to eq Roguelike::Advancement::MAX_LEVEL
    end
  end

  describe ".to_next" do
    it "counts down to the next threshold" do
      expect(described_class.to_next(0)).to eq described_class.threshold(2)
      expect(described_class.to_next(19)).to eq 1
      expect(described_class.to_next(20)).to eq described_class.threshold(3) - 20
    end

    it "answers nothing at the last level" do
      expect(described_class.to_next(Int32::MAX)).to be_nil
    end
  end
end
