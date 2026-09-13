require "../../spec_helper"

Spectator.describe Roguelike::Ui::Flicker do
  alias Kind = Roguelike::LightKind

  subject(flicker) { Roguelike::Ui::Flicker.new 20260911_u64 }

  it "starts on the first tick and burning" do
    expect(flicker.tick).to eq 0
    expect(flicker.burning?).to be_true
  end

  describe "what moves" do
    it "moves nothing on a square with no light" do
      expect(flicker.shift 3, 3, 0, Kind::Flame).to eq 0
    end

    it "moves nothing lit by anything but a flame" do
      expect(flicker.shift 3, 3, 1, Kind::Glimmer).to eq 0
      expect(flicker.shift 3, 3, 1, nil).to eq 0
    end

    # The square the flame stands on does not waver. One step either way
    # there would not show, and a light that jumps at its own source reads as
    # a fault rather than as a flame.
    it "moves nothing deep inside a pool" do
      (Roguelike::Ui::Flicker::EDGE..12).each do |level|
        expect(flicker.shift 3, 3, level, Kind::Flame).to eq 0
      end
    end

    it "moves a square at the edge of a pool at least sometimes" do
      moved = (0...400).count do |tick|
        flicker.tick = tick
        flicker.shift(3, 3, 1, Kind::Flame) != 0
      end

      expect(moved).to be > 0
      expect(moved).to be < 400
    end

    it "moves by one step either way and no further" do
      seen = Set(Int32).new

      (0...2000).each do |tick|
        flicker.tick = tick
        seen << flicker.shift(tick % 17, tick % 13, 1, Kind::Flame)
      end

      expect(seen).to eq Set{-1, 0, 1}
    end
  end

  describe "how often it moves" do
    # The edge of a pool moves most. One step of brightness is the width of a
    # square out there, and further in it is not.
    it "moves the edge more often than the middle" do
      chances = (1...Roguelike::Ui::Flicker::EDGE).map { |level| flicker.chance level }

      expect(chances).to eq chances.sort.reverse!
      expect(chances.uniq.size).to eq chances.size
    end

    it "never moves a square outside the edge" do
      expect(flicker.chance 0).to eq 0
      expect(flicker.chance Roguelike::Ui::Flicker::EDGE).to eq 0
    end
  end

  # A run started from a seed plays out the same whatever the clock did while
  # it was running.
  describe "the same seed" do
    it "flickers the same way twice" do
      one = Roguelike::Ui::Flicker.new 7_u64, tick: 42
      two = Roguelike::Ui::Flicker.new 7_u64, tick: 42

      (0...30).each do |column|
        expect(one.shift column, 5, 2, Kind::Flame)
          .to eq two.shift(column, 5, 2, Kind::Flame)
      end
    end

    it "flickers differently from another seed" do
      one = Roguelike::Ui::Flicker.new 7_u64, tick: 42
      two = Roguelike::Ui::Flicker.new 8_u64, tick: 42

      shifts = (0...60).map do |column|
        {one.shift(column, 5, 2, Kind::Flame), two.shift(column, 5, 2, Kind::Flame)}
      end

      expect(shifts.any? { |pair| pair[0] != pair[1] }).to be_true
    end

    it "flickers differently on another tick" do
      one = Roguelike::Ui::Flicker.new 7_u64, tick: 1
      two = Roguelike::Ui::Flicker.new 7_u64, tick: 2

      shifts = (0...60).map do |column|
        {one.shift(column, 5, 2, Kind::Flame), two.shift(column, 5, 2, Kind::Flame)}
      end

      expect(shifts.any? { |pair| pair[0] != pair[1] }).to be_true
    end

    it "holds one square still while it holds still" do
      shifts = (0...20).map { flicker.shift 4, 4, 2, Kind::Flame }

      expect(shifts.uniq.size).to eq 1
    end
  end

  describe "turned off" do
    it "moves nothing at all" do
      still = Roguelike::Ui::Flicker.new 7_u64, burning: false

      (0...200).each do |tick|
        still.tick = tick
        expect(still.shift tick % 9, tick % 7, 1, Kind::Flame).to eq 0
      end
    end
  end
end
