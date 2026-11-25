require "../spec_helper"
require "../support/drawn_rng"

Spectator.describe Roguelike::Span do
  alias Fixed = Roguelike::Fixed
  alias Spread = Roguelike::Spread

  def span(low : Int32, high : Int32, spread : Spread = Spread::Steady) : Roguelike::Span
    described_class.new Fixed.new(low), Fixed.new(high), spread
  end

  describe ".new" do
    it "refuses a high below the low" do
      expect { span 300, 200 }.to raise_error ArgumentError
    end

    it "refuses a low below zero" do
      expect { span -1, 200 }.to raise_error ArgumentError
    end

    it "takes a span of one value" do
      expect(span(300, 300).roll(DrawnRng.new [9, 9]).value).to eq 300
    end
  end

  describe "#roll" do
    it "rolls the low end on the least draw and the high end on the largest" do
      expect(span(300, 700, Spread::Even).roll(DrawnRng.new [0]).value).to eq 300
      expect(span(300, 700, Spread::Even).roll(DrawnRng.new [65_535]).value).to eq 700
    end

    it "rounds the step half up" do
      expect(span(0, 2, Spread::Even).roll(DrawnRng.new [16_384]).value).to eq 1
      expect(span(0, 2, Spread::Even).roll(DrawnRng.new [16_383]).value).to eq 0
    end

    it "takes the largest span without overflow" do
      wide = span 0, Int32::MAX, Spread::Centered

      expect(wide.roll(DrawnRng.new [65_535, 65_535]).value).to eq Int32::MAX
    end

    it "draws the same values on every platform" do
      rng = Roguelike::Rng.new(20261124_u64).derive "combat", 7
      rolled = Spread.values.map { |spread| span(250, 650, spread).roll(rng).value }

      expect(rolled).to eq [435, 504, 274]
    end
  end

  describe "#mean" do
    it "is the midpoint, rounded half up" do
      expect(span(250, 650).mean.value).to eq 450
      expect(span(250, 651).mean.value).to eq 451
    end
  end

  describe "#to_s" do
    it "shows both ends with one decimal place" do
      expect(span(300, 700).to_s).to eq "3.0–7.0"
    end
  end
end

Spectator.describe Roguelike::Spread do
  alias Spread = Roguelike::Spread

  describe "#draw" do
    it "takes one draw for even" do
      rng = DrawnRng.new [1_234, 9]

      expect(Spread::Even.draw(rng)).to eq 1_234
      expect(rng.left).to eq 1
    end

    it "weights the first of two draws three to one for steady" do
      expect(Spread::Steady.draw(DrawnRng.new [65_535, 0])).to eq 49_151
      expect(Spread::Steady.draw(DrawnRng.new [0, 65_535])).to eq 16_384
    end

    it "averages two draws for centered" do
      expect(Spread::Centered.draw(DrawnRng.new [65_535, 0])).to eq 32_768
      expect(Spread::Centered.draw(DrawnRng.new [100, 300])).to eq 200
    end

    it "reaches both ends for every spread" do
      described_class.values.each do |spread|
        expect(spread.draw(DrawnRng.new [0, 0])).to eq 0
        expect(spread.draw(DrawnRng.new [65_535, 65_535])).to eq 65_535
      end
    end
  end
end
