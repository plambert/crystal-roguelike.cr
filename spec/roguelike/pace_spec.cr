require "../spec_helper"

Spectator.describe Roguelike::Pace do
  alias Pace = Roguelike::Pace

  # How many actions a pace of *speed* takes over *ticks* ticks.
  #
  # The loop is `Game#tick`: an actor spends what it came in with, and banks
  # what the tick paid it at the end.
  #
  # The count can be one under the ratio, because an actor holding less than
  # a tick's worth at the end of a run has earned an action it has not taken.
  # That one is a phase rather than a drift: it is the same one over ten
  # thousand ticks as over a hundred.
  def actions(speed : Int32, ticks : Int32) : Int32
    pace = Pace.new speed
    taken = 0

    ticks.times do
      while pace.ready?
        pace.spend Pace::TICK
        taken += 1
      end

      pace.gain
    end

    taken
  end

  describe "actions over a stretch of ticks" do
    it "gives a normal actor one action a tick" do
      expect(actions Pace::NORMAL, 100).to eq 100
    end

    it "gives one at ninety-five ninety-five of them" do
      expect(actions 95, 100).to be_within(1).of(95)
    end

    it "gives one at eighty four for the normal five" do
      expect(actions 80, 100).to eq 80
    end

    # The leftover carries, so the ratio does not drift the way a rounded
    # division would. A hundred times as long is a hundred times as many
    # actions and the same one action of phase.
    it "holds the ratio over a long run" do
      expect(actions 80, 10_000).to eq 8_000
      expect(actions 95, 10_000).to be_within(1).of(9_500)
      expect(actions Pace::NORMAL, 10_000).to eq 10_000
    end
  end

  describe "#ready?" do
    it "starts with one action paid for" do
      expect(Pace.new.ready?).to be_true
    end

    it "is not ready with the action spent" do
      pace = Pace.new
      pace.spend Pace::TICK

      expect(pace.ready?).to be_false
    end

    it "is ready again after a tick" do
      pace = Pace.new
      pace.spend Pace::TICK
      pace.gain

      expect(pace.ready?).to be_true
    end

    # An action of three ticks leaves the actor two ticks in debt.
    it "takes three ticks to pay off an action of three" do
      pace = Pace.new
      pace.spend 3 * Pace::TICK

      expect(pace.ready?).to be_false
      pace.gain
      expect(pace.ready?).to be_false
      pace.gain
      expect(pace.ready?).to be_false
      pace.gain
      expect(pace.ready?).to be_true
    end
  end

  describe "#rest" do
    it "holds an actor at one action's worth" do
      pace = Pace.new
      50.times { pace.gain }
      pace.rest

      expect(pace.energy).to eq Pace::TICK
      expect(pace.ready?).to be_true
    end
  end

  describe "a haste" do
    it "raises the speed while it lasts" do
      pace = Pace.new
      pace.hurry 10

      expect(pace.speed).to eq Pace::NORMAL + Pace::HASTE
      expect(pace.hurried?).to be_true
    end

    it "runs out" do
      pace = Pace.new
      pace.hurry 2
      pace.pass
      pace.pass

      expect(pace.hurried?).to be_false
      expect(pace.speed).to eq Pace::NORMAL
    end

    # Five potions are five times the time, not five times the speed.
    it "lasts longer rather than going faster" do
      pace = Pace.new
      pace.hurry 10
      pace.hurry 10

      expect(pace.speed).to eq Pace::NORMAL + Pace::HASTE
      expect(pace.hasted).to eq 20
    end

    it "takes half again as many actions" do
      pace = Pace.new
      pace.hurry 1000
      pace.spend Pace::TICK
      taken = 0

      100.times do
        pace.gain

        while pace.ready?
          pace.spend Pace::TICK
          taken += 1
        end
      end

      expect(taken).to eq 150
    end
  end

  describe "a slow" do
    it "lowers the speed while it lasts" do
      pace = Pace.new
      pace.drag 10

      expect(pace.speed).to eq Pace::NORMAL - Pace::SLOW
      expect(pace.dragging?).to be_true
    end

    it "cancels against a haste" do
      pace = Pace.new
      pace.hurry 10
      pace.drag 10

      expect(pace.speed).to eq Pace::NORMAL + Pace::HASTE - Pace::SLOW
    end

    # An actor at no speed at all would never act again, and the tick loop
    # would not end.
    it "never takes anything to a standstill" do
      pace = Pace.new Pace::LEAST
      pace.drag 10

      expect(pace.speed).to eq Pace::LEAST
      expect(pace.speed).to be > 0
    end
  end

  describe "#settle" do
    it "takes both off at once" do
      pace = Pace.new
      pace.hurry 10
      pace.drag 10
      pace.settle

      expect(pace.altered?).to be_false
      expect(pace.speed).to eq Pace::NORMAL
    end
  end

  describe "written out" do
    it "round-trips through JSON" do
      pace = Pace.new 80
      pace.spend 30
      pace.hurry 5

      read = Pace.from_json pace.to_json

      expect(read.base).to eq 80
      expect(read.energy).to eq pace.energy
      expect(read.hasted).to eq 5
      expect(read.speed).to eq pace.speed
    end

    # A save written before actors had a pace has no field for one.
    it "loads a pace from nothing at normal speed" do
      read = Pace.from_json "{}"

      expect(read.base).to eq Pace::NORMAL
      expect(read.ready?).to be_true
    end
  end
end
