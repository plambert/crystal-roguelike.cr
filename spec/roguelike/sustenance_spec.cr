require "../spec_helper"

Spectator.describe Roguelike::Sustenance do
  subject(sustenance) { described_class.new }

  it "starts fed, quenched and with a full skin" do
    expect(sustenance.hunger).to eq 0
    expect(sustenance.thirst).to eq 0
    expect(sustenance.water).to eq Roguelike::Sustenance::WATER_MAX
    expect(sustenance.full?).to be_true
    expect(sustenance.quenched?).to be_true
    expect(sustenance.hunger_stage).to eq Roguelike::HungerStage::Satiated
    expect(sustenance.thirst_stage).to eq Roguelike::ThirstStage::Quenched
  end

  describe "#tick" do
    it "climbs hunger every turn" do
      3.times { sustenance.tick }

      expect(sustenance.hunger).to eq 3
    end

    it "sips one unit from the skin every SIP turns" do
      (Roguelike::Sustenance::SIP - 1).times { sustenance.tick }
      expect(sustenance.water).to eq 10

      sustenance.tick
      expect(sustenance.water).to eq 9
      expect(sustenance.thirst).to eq 0
    end

    it "climbs thirst once the skin is dry" do
      dry = described_class.new water: 0

      5.times { dry.tick }

      expect(dry.thirst).to eq 5
      expect(dry.thirst_stage).to eq Roguelike::ThirstStage::Fine
    end

    it "goes on climbing thirst after a refill until the character drinks" do
      dry = described_class.new water: 0, thirst: 10
      dry.refill 3

      dry.tick

      expect(dry.thirst).to eq 11
      expect(dry.water).to eq 3
    end

    it "holds thirst still on a turn it is told to" do
      dry = described_class.new water: 0

      dry.tick thirst: false

      expect(dry.thirst).to eq 0
      expect(dry.hunger).to eq 1
    end
  end

  describe "#hunger_stage" do
    it "names each stage at its threshold" do
      {                              0 => Roguelike::HungerStage::Satiated,
       Roguelike::Sustenance::FED      => Roguelike::HungerStage::Fed,
       Roguelike::Sustenance::HUNGRY   => Roguelike::HungerStage::Hungry,
       Roguelike::Sustenance::FAMISHED => Roguelike::HungerStage::Famished,
       Roguelike::Sustenance::STARVING => Roguelike::HungerStage::Starving}.each do |turns, stage|
        expect(described_class.new(hunger: turns).hunger_stage).to eq stage
      end
    end
  end

  describe "#thirst_stage" do
    it "names each stage at its threshold" do
      {                                0 => Roguelike::ThirstStage::Quenched,
                                       1 => Roguelike::ThirstStage::Fine,
       Roguelike::Sustenance::THIRSTY    => Roguelike::ThirstStage::Thirsty,
       Roguelike::Sustenance::PARCHED    => Roguelike::ThirstStage::Parched,
       Roguelike::Sustenance::DEHYDRATED => Roguelike::ThirstStage::Dehydrated,
       Roguelike::Sustenance::DYING      => Roguelike::ThirstStage::Dying}.each do |turns, stage|
        expect(described_class.new(thirst: turns).thirst_stage).to eq stage
      end
    end
  end

  describe "#eat" do
    it "takes what it needs and answers how much" do
      hungry = described_class.new hunger: 100

      expect(hungry.eat(30)).to eq 30
      expect(hungry.hunger).to eq 70
    end

    it "stops at full and answers what was taken" do
      hungry = described_class.new hunger: 100

      expect(hungry.eat(1500)).to eq 100
      expect(hungry.full?).to be_true
    end
  end

  describe "#drink" do
    it "takes one unit and quenches" do
      thirsty = described_class.new thirst: 800, water: 4

      expect(thirsty.drink).to eq 1
      expect(thirsty.water).to eq 3
      expect(thirsty.quenched?).to be_true
    end

    it "drinks nothing when quenched" do
      expect(sustenance.drink).to eq 0
      expect(sustenance.water).to eq 10
    end

    it "drinks no more than one unit when asked for more" do
      thirsty = described_class.new thirst: 800, water: 4

      expect(thirsty.drink(3)).to eq 1
      expect(thirsty.water).to eq 3
    end

    it "drinks nothing from an empty skin" do
      thirsty = described_class.new thirst: 800, water: 0

      expect(thirsty.drink).to eq 0
      expect(thirsty.quenched?).to be_false
    end
  end

  describe "#quench" do
    it "quenches without touching the skin" do
      thirsty = described_class.new thirst: 800, water: 0

      expect(thirsty.quench(1)).to eq 1
      expect(thirsty.quenched?).to be_true
      expect(thirsty.water).to eq 0
    end

    it "uses nothing when quenched" do
      expect(sustenance.quench(1)).to eq 0
    end
  end

  describe "#refill" do
    it "answers how many units fit" do
      low = described_class.new water: 7

      expect(low.refill(5)).to eq 3
      expect(low.water).to eq 10
    end
  end

  describe "#death" do
    it "is nil while both counters are short of the end" do
      expect(sustenance.death).to be_nil
    end

    it "names thirst and hunger at their ends" do
      expect(described_class.new(thirst: Roguelike::Sustenance::DRIED).death)
        .to eq Roguelike::Sustenance::Death::Thirst
      expect(described_class.new(hunger: Roguelike::Sustenance::STARVED).death)
        .to eq Roguelike::Sustenance::Death::Hunger
    end
  end

  describe "a save" do
    it "round trips" do
      held = described_class.new hunger: 12, thirst: 34, water: 5, sipped: 6

      again = described_class.from_json held.to_json

      expect({again.hunger, again.thirst, again.water, again.sipped}).to eq({12, 34, 5, 6})
    end

    it "starts fresh for a player saved without it" do
      player = Roguelike::Player.new "proving-ground", 6, 5
      json = JSON.parse(player.to_json).as_h
      json.delete "sustenance"

      again = Roguelike::Player.from_json json.to_json

      expect(again.sustenance.water).to eq Roguelike::Sustenance::WATER_MAX
      expect(again.sustenance.hunger).to eq 0
    end
  end
end
