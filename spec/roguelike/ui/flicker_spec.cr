require "../../spec_helper"

Spectator.describe Roguelike::Ui::Flicker do
  alias Flicker = Roguelike::Ui::Flicker

  # Two flames standing apart.
  ONE = {3, 4}
  TWO = {17, 9}

  subject(flicker) { Flicker.new 20260911_u64 }

  it "starts on the first tick and burning" do
    expect(flicker.tick).to eq 0
    expect(flicker.burning?).to be_true
  end

  describe "what moves" do
    it "moves nothing on a square no flame reaches" do
      (0...200).each do |tick|
        flicker.tick = tick
        expect(flicker.shift [] of {Int32, Int32}).to eq 0
      end
    end

    it "moves by one step either way and no further" do
      seen = Set(Int32).new

      (0...600).each do |tick|
        flicker.tick = tick
        seen << flicker.step_at ONE[0], ONE[1]
      end

      expect(seen).to eq Set{-1, 0, 1}
    end
  end

  # Two torches in one room are not the same flame.
  describe "two flames" do
    it "do not move in step with one another" do
      apart = (0...600).count do |tick|
        flicker.tick = tick
        flicker.step_at(ONE[0], ONE[1]) != flicker.step_at(TWO[0], TWO[1])
      end

      expect(apart).to be > 100
    end

    it "move together on some ticks all the same" do
      together = (0...600).count do |tick|
        flicker.tick = tick
        flicker.step_at(ONE[0], ONE[1]) == flicker.step_at(TWO[0], TWO[1])
      end

      expect(together).to be > 100
    end
  end

  # Where two pools overlap the squares they share take both shifts.
  describe "where two pools overlap" do
    it "adds what both flames are doing" do
      (0...200).each do |tick|
        flicker.tick = tick
        both = flicker.step_at(ONE[0], ONE[1]) + flicker.step_at(TWO[0], TWO[1])

        expect(flicker.shift [ONE, TWO]).to eq both
      end
    end

    it "drops the ground twice as far when both gutter at once" do
      found = (0...600).find do |tick|
        flicker.tick = tick
        flicker.step_at(ONE[0], ONE[1]) == -1 && flicker.step_at(TWO[0], TWO[1]) == -1
      end
      raise "the two flames never guttered at once" unless found

      flicker.tick = found
      expect(flicker.shift [ONE, TWO]).to eq -2
    end

    it "leaves it where it was when one gutters and the other flares" do
      found = (0...600).find do |tick|
        flicker.tick = tick
        flicker.step_at(ONE[0], ONE[1]) + flicker.step_at(TWO[0], TWO[1]) == 0 &&
          flicker.step_at(ONE[0], ONE[1]) != 0
      end
      raise "the two flames never pulled against each other" unless found

      flicker.tick = found
      expect(flicker.shift [ONE, TWO]).to eq 0
    end
  end

  describe "how often one flame moves" do
    # A value that changed on every tick would read as a strobe.
    it "holds each step for more than one tick" do
      steps = (0...40).map { |tick| flicker.tick = tick; flicker.step_at ONE[0], ONE[1] }

      steps.each_slice(Flicker::HOLD) do |held|
        expect(held.uniq.size).to eq 1
      end
    end

    it "leaves the light where it is on about half the ticks" do
      still = (0...4000).count do |tick|
        flicker.tick = tick
        flicker.step_at(ONE[0], ONE[1]).zero?
      end

      expect(still).to be > 1600
      expect(still).to be < 2400
    end

    # A flame drops more often than it jumps.
    it "gutters more often than it flares" do
      steps = (0...4000).map { |tick| flicker.tick = tick; flicker.step_at ONE[0], ONE[1] }

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
        expect(one.shift [ONE, TWO]).to eq two.shift([ONE, TWO])
      end
    end

    it "flickers differently from another seed" do
      one = Flicker.new 7_u64
      two = Flicker.new 8_u64

      steps = (0...200).map do |tick|
        one.tick = tick
        two.tick = tick
        {one.shift([ONE]), two.shift([ONE])}
      end

      expect(steps.any? { |pair| pair[0] != pair[1] }).to be_true
    end

    it "holds one tick still while it holds still" do
      expect((0...20).map { flicker.shift [ONE] }.uniq!.size).to eq 1
    end
  end

  describe "turned off" do
    it "moves nothing at all" do
      still = Flicker.new 7_u64, burning: false

      (0...200).each do |tick|
        still.tick = tick
        expect(still.step_at ONE[0], ONE[1]).to eq 0
        expect(still.shift [ONE, TWO]).to eq 0
      end
    end
  end
end
