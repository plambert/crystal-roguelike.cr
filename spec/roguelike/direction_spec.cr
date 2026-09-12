require "../spec_helper"

Spectator.describe Roguelike::Direction do
  alias Direction = Roguelike::Direction

  describe "the steps" do
    it "moves one square and no more" do
      described_class.each do |direction|
        expect(direction.dx.abs).to be <= 1
        expect(direction.dy.abs).to be <= 1
      end
    end

    it "never stands still" do
      described_class.each do |direction|
        expect({direction.dx, direction.dy}).not_to eq({0, 0})
      end
    end

    it "reaches all eight squares around one" do
      steps = described_class.values.map &.step

      expect(steps.uniq.size).to eq 8
    end

    # South is positive. A screen counts rows downward. A floor stores rows in
    # the order it draws them.
    it "counts rows downward" do
      expect(Direction::South.dy).to eq 1
      expect(Direction::North.dy).to eq -1
      expect(Direction::East.dx).to eq 1
      expect(Direction::West.dx).to eq -1
    end
  end

  describe "#opposite" do
    it "turns right round" do
      described_class.each do |direction|
        expect(direction.opposite.step).to eq({-direction.dx, -direction.dy})
      end
    end

    it "comes back on itself" do
      described_class.each do |direction|
        expect(direction.opposite.opposite).to eq direction
      end
    end
  end

  describe "#diagonal?" do
    it "knows a corner from a cardinal" do
      expect(Direction::NorthEast.diagonal?).to be_true
      expect(Direction::North.diagonal?).to be_false
      expect(described_class.values.count(&.diagonal?)).to eq 4
    end
  end

  describe "#from" do
    it "answers where a step lands" do
      expect(Direction::SouthEast.from(3, 4)).to eq({4, 5})
      expect(Direction::NorthWest.from(3, 4)).to eq({2, 3})
    end
  end

  describe "#label" do
    it "names every direction differently" do
      labels = described_class.values.map &.label

      expect(labels.uniq.size).to eq 8
      expect(Direction::NorthWest.label).to eq "north-west"
    end
  end
end
