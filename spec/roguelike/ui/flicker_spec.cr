require "../../spec_helper"

Spectator.describe Roguelike::Ui::Flicker do
  alias Flicker = Roguelike::Ui::Flicker
  alias Kind = Roguelike::LightKind

  subject(flicker) { Flicker.new 20260911_u64 }

  it "starts on the first tick and burning" do
    expect(flicker.tick).to eq 0
    expect(flicker.burning?).to be_true
  end

  describe "what moves" do
    it "moves nothing on a square with no light" do
      (0...200).each do |tick|
        flicker.tick = tick
        expect(flicker.shift 0, Kind::Flame).to eq 0
      end
    end

    it "moves nothing lit by anything but a flame" do
      (0...200).each do |tick|
        flicker.tick = tick
        expect(flicker.shift 3, Kind::Glimmer).to eq 0
        expect(flicker.shift 3, nil).to eq 0
      end
    end

    # The whole pool moves as one light. A square near the flame and a square
    # at the edge of its reach move by the same step on the same tick.
    it "moves every square a flame lights by the same step" do
      (0...200).each do |tick|
        flicker.tick = tick
        wanted = flicker.step

        (1..12).each { |level| expect(flicker.shift level, Kind::Flame).to eq wanted }
      end
    end

    it "moves by one step either way and no further" do
      seen = Set(Int32).new

      (0...600).each do |tick|
        flicker.tick = tick
        seen << flicker.step
      end

      expect(seen).to eq Set{-1, 0, 1}
    end
  end

  describe "how often it moves" do
    # A value that changed on every tick would read as a strobe.
    it "holds each step for more than one tick" do
      steps = (0...40).map { |tick| flicker.tick = tick; flicker.step }

      steps.each_slice(Flicker::HOLD) do |held|
        expect(held.uniq.size).to eq 1
      end
    end

    it "leaves the light where it is on about half the ticks" do
      still = (0...4000).count { |tick| flicker.tick = tick; flicker.step.zero? }

      expect(still).to be > 1600
      expect(still).to be < 2400
    end

    # A flame drops more often than it jumps.
    it "gutters more often than it flares" do
      steps = (0...4000).map { |tick| flicker.tick = tick; flicker.step }

      expect(steps.count(-1)).to be > steps.count(1)
    end
  end

  # A run started from a seed plays out the same whatever the clock did while
  # it was running.
  describe "the same seed" do
    it "flickers the same way twice" do
      one = Flicker.new 7_u64
      two = Flicker.new 7_u64

      (0...200).each do |tick|
        one.tick = tick
        two.tick = tick
        expect(one.step).to eq two.step
      end
    end

    it "flickers differently from another seed" do
      one = Flicker.new 7_u64
      two = Flicker.new 8_u64

      steps = (0...200).map do |tick|
        one.tick = tick
        two.tick = tick
        {one.step, two.step}
      end

      expect(steps.any? { |pair| pair[0] != pair[1] }).to be_true
    end

    it "holds one tick still while it holds still" do
      expect((0...20).map { flicker.step }.uniq!.size).to eq 1
    end
  end

  describe "turned off" do
    it "moves nothing at all" do
      still = Flicker.new 7_u64, burning: false

      (0...200).each do |tick|
        still.tick = tick
        expect(still.step).to eq 0
        expect(still.shift 3, Kind::Flame).to eq 0
      end
    end
  end
end
