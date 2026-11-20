require "../spec_helper"

Spectator.describe Roguelike::Sustenance do
  alias Sustenance = Roguelike::Sustenance
  alias Tuning = Roguelike::Sustenance::Tuning
  alias HungerStage = Roguelike::HungerStage
  alias ThirstStage = Roguelike::ThirstStage

  subject(sustenance) { described_class.new }

  it "starts with no debt and a full skin" do
    expect(sustenance.hunger).to eq 0
    expect(sustenance.thirst).to eq 0
    expect(sustenance.water).to eq Tuning::SKIN_UNITS
    expect(sustenance.full?).to be_true
    expect(sustenance.quenched?).to be_true
    expect(sustenance.hunger_stage).to eq HungerStage::Satiated
    expect(sustenance.thirst_stage).to eq ThirstStage::Quenched
    expect(sustenance.severity).to eq 0.0
  end

  describe "#tick" do
    it "climbs both debts every turn and leaves the skin alone" do
      3.times { sustenance.tick }

      expect(sustenance.hunger).to eq 3
      expect(sustenance.thirst).to eq 3
      expect(sustenance.water).to eq Tuning::SKIN_UNITS
    end

    it "holds thirst still on a turn it is told to" do
      sustenance.tick thirst: false
      sustenance.tick

      expect(sustenance.hunger).to eq 2
      expect(sustenance.thirst).to eq 1
    end

    it "wastes no hit points short of the wasting severity" do
      held = described_class.new thirst: Tuning::THIRST_SEVERE

      200.times { held.tick }

      expect(held.wasted).to eq 0
      expect(held.waste_every).to be_nil
    end

    it "wastes hit points faster as severity climbs past the wasting point" do
      first = described_class.new thirst: Sustenance::THIRST_DYING
      last = described_class.new thirst: Tuning::THIRST_DEATH - 1

      expect(first.waste_every).to eq Tuning::WASTE_FIRST
      expect(last.waste_every.try &.<=(Tuning::WASTE_LAST + 1)).to be_true
    end
  end

  describe "#hunger_stage" do
    it "starts each stage at its threshold" do
      {
        {0, HungerStage::Satiated},
        {Tuning::HUNGER_FIRST - 1, HungerStage::Satiated},
        {Tuning::HUNGER_FIRST, HungerStage::Fed},
        {Tuning::HUNGER_HUNGRY - 1, HungerStage::Fed},
        {Tuning::HUNGER_HUNGRY, HungerStage::Hungry},
        {Tuning::HUNGER_SERIOUS - 1, HungerStage::Hungry},
        {Tuning::HUNGER_SERIOUS, HungerStage::Famished},
        {Tuning::HUNGER_SEVERE - 1, HungerStage::Famished},
        {Tuning::HUNGER_SEVERE, HungerStage::Starving},
      }.each do |turns, stage|
        expect(described_class.new(hunger: turns).hunger_stage).to eq(stage), "#{turns}"
      end
    end

    it "puts the thresholds at 6, 12, 24 and 60 hours and death at six weeks" do
      hour = 3600 // Sustenance::SECONDS_PER_TURN
      expect({Tuning::HUNGER_FIRST, Tuning::HUNGER_HUNGRY, Tuning::HUNGER_SERIOUS,
              Tuning::HUNGER_SEVERE, Tuning::HUNGER_DEATH})
        .to eq({6 * hour, 12 * hour, 24 * hour, 60 * hour, 42 * 24 * hour})
    end
  end

  describe "#thirst_stage" do
    it "starts each stage at its threshold" do
      {
        {0, ThirstStage::Quenched},
        {Tuning::UNIT_TURNS - 1, ThirstStage::Quenched},
        {Tuning::UNIT_TURNS, ThirstStage::Fine},
        {Tuning::THIRST_FIRST - 1, ThirstStage::Fine},
        {Tuning::THIRST_FIRST, ThirstStage::Thirsty},
        {Tuning::THIRST_SERIOUS - 1, ThirstStage::Thirsty},
        {Tuning::THIRST_SERIOUS, ThirstStage::Parched},
        {Tuning::THIRST_SEVERE - 1, ThirstStage::Parched},
        {Tuning::THIRST_SEVERE, ThirstStage::Dehydrated},
        {Sustenance::THIRST_DYING - 1, ThirstStage::Dehydrated},
        {Sustenance::THIRST_DYING, ThirstStage::Dying},
      }.each do |turns, stage|
        expect(described_class.new(thirst: turns).thirst_stage).to eq(stage), "#{turns}"
      end
    end

    it "puts the thresholds at 7, 24 and 48 hours and death at 72" do
      hour = 3600 // Sustenance::SECONDS_PER_TURN
      expect({Tuning::THIRST_FIRST, Tuning::THIRST_SERIOUS, Tuning::THIRST_SEVERE, Tuning::THIRST_DEATH})
        .to eq({7 * hour, 24 * hour, 48 * hour, 72 * hour})
    end

    it "starts dying of thirst where thirst alone reaches the wasting severity" do
      expect(Sustenance.thirst_severity(Sustenance::THIRST_DYING)).to be >= Tuning::WASTING
      expect(Sustenance.thirst_severity(Sustenance::THIRST_DYING - 1)).to be < Tuning::WASTING
    end
  end

  describe "severity" do
    it "is zero short of hunger's first effect and on each point after it" do
      expect(Sustenance.hunger_severity(Tuning::HUNGER_FIRST - 1)).to eq 0.0
      Tuning::HUNGER_SEVERITY.each do |debt, severity|
        expect(Sustenance.hunger_severity(debt)).to be_within(1e-9).of(severity)
      end
    end

    it "jumps to its first point at thirst's first effect" do
      expect(Sustenance.thirst_severity(Tuning::THIRST_FIRST - 1)).to eq 0.0
      expect(Sustenance.thirst_severity(Tuning::THIRST_FIRST)).to be_within(1e-9).of(0.1)
      Tuning::THIRST_SEVERITY.each do |debt, severity|
        expect(Sustenance.thirst_severity(debt)).to be_within(1e-9).of(severity)
      end
    end

    it "pins the points the design gives" do
      expect(Tuning::HUNGER_SEVERITY).to eq [{2_160, 0.0}, {4_320, 0.15}, {8_640, 0.35}, {21_600, 0.6}]
      expect(Tuning::THIRST_SEVERITY).to eq [{2_520, 0.1}, {8_640, 0.35}, {17_280, 0.65}]
    end

    it "runs in a straight line between two points" do
      middle = (Tuning::HUNGER_HUNGRY + Tuning::HUNGER_SERIOUS) // 2
      expect(Sustenance.hunger_severity(middle)).to be_within(1e-9).of(0.25)
    end

    it "climbs slowly from the last point and reaches 1 at death" do
      last, from = Tuning::THIRST_SEVERITY.last
      halfway = (last + Tuning::THIRST_DEATH) // 2

      expect(Sustenance.thirst_severity(halfway)).to be < (from + 1.0) / 2
      expect(Sustenance.thirst_severity(Tuning::THIRST_DEATH - 1)).to be < 1.0
      expect(Sustenance.thirst_severity(Tuning::THIRST_DEATH)).to eq 1.0
      expect(Sustenance.hunger_severity(Tuning::HUNGER_DEATH)).to eq 1.0
      expect(Sustenance.hunger_severity(Tuning::HUNGER_DEATH + 500)).to eq 1.0
    end

    it "adds hunger and thirst" do
      both = described_class.new hunger: Tuning::HUNGER_HUNGRY, thirst: Tuning::THIRST_SERIOUS
      expect(both.severity).to be_within(1e-9).of(0.5)
    end

    it "is capped at 1 together" do
      both = described_class.new hunger: Tuning::HUNGER_SEVERE, thirst: Tuning::THIRST_SEVERE
      expect(both.hunger_severity + both.thirst_severity).to be > 1.0
      expect(both.severity).to eq 1.0
    end
  end

  describe "effects" do
    it "leaves a character with no severity as they are" do
      expect(sustenance.slowing).to eq 0
      expect(sustenance.to_hit_penalty).to eq 0
      expect(sustenance.damage_penalty).to eq 0
      expect(sustenance.regeneration_factor).to eq 1.0
      expect(sustenance.wear(Roguelike::Attributes.new)).to eq Roguelike::Attributes.new
    end

    it "is a minor drag at severity 0.15" do
      hungry = described_class.new hunger: Tuning::HUNGER_HUNGRY

      expect(hungry.slowing).to eq 9
      expect(hungry.to_hit_penalty).to eq 0
      expect(hungry.damage_penalty).to eq 0
      expect(hungry.wear(Roguelike::Attributes.new).strength).to eq 9
      expect(hungry.regenerates?).to be_true
    end

    it "leaves the character nearly helpless at severity 1" do
      dying = described_class.new thirst: Tuning::THIRST_DEATH - 1, hunger: Tuning::HUNGER_SEVERE
      worn = dying.wear Roguelike::Attributes.new(14, 12, 16, 10, 11)

      expect(dying.slowing).to eq Tuning::PACE_LOSS
      expect(dying.to_hit_penalty).to eq Tuning::TO_HIT_LOSS
      expect(dying.damage_penalty).to eq Tuning::DAMAGE_LOSS
      expect(worn.to_a.uniq).to eq [Roguelike::Attributes::MINIMUM]
      expect(dying.regenerates?).to be_false
    end
  end

  describe "#eat" do
    it "pays hunger debt and answers how much" do
      hungry = described_class.new hunger: 100

      expect(hungry.eat 40).to eq 40
      expect(hungry.hunger).to eq 60
    end

    it "stops at no debt and answers what was taken" do
      hungry = described_class.new hunger: 100

      expect(hungry.eat 400).to eq 100
      expect(hungry.full?).to be_true
    end
  end

  describe "#drink" do
    it "takes one unit and pays a unit's turns of thirst debt" do
      thirsty = described_class.new thirst: 800, water: 4

      expect(thirsty.drink).to eq 1
      expect(thirsty.water).to eq 3
      expect(thirsty.thirst).to eq 800 - Tuning::UNIT_TURNS
    end

    it "pays no further than no debt" do
      thirsty = described_class.new thirst: 100, water: 4

      thirsty.drink
      expect(thirsty.thirst).to eq 0
    end

    it "drinks nothing with no debt" do
      expect(sustenance.drink).to eq 0
      expect(sustenance.water).to eq Tuning::SKIN_UNITS
    end

    it "drinks nothing from an empty skin" do
      thirsty = described_class.new thirst: 800, water: 0

      expect(thirsty.drink).to eq 0
      expect(thirsty.thirst).to eq 800
    end

    it "holds 25 hours of thirst in a full skin" do
      expect(Tuning::SKIN_UNITS * Tuning::UNIT_TURNS).to eq 9_000
      expect(Sustenance.approximate(Tuning::SKIN_UNITS * Tuning::UNIT_TURNS)).to eq "25h"
    end
  end

  describe "#drink_due?" do
    it "waits until a unit pays off whole and thirst is a unit away" do
      expect(described_class.new(thirst: Tuning::THIRST_FIRST - Tuning::UNIT_TURNS).drink_due?).to be_false
      expect(described_class.new(thirst: Tuning::THIRST_FIRST - Tuning::UNIT_TURNS + 1).drink_due?).to be_true
      expect(described_class.new(thirst: Tuning::THIRST_SERIOUS).drink_due?).to be_true
    end
  end

  describe "#quench and #slake" do
    it "pays debt without touching the skin" do
      thirsty = described_class.new thirst: 800, water: 0

      expect(thirsty.quench 100).to eq 100
      expect(thirsty.thirst).to eq 700
      expect(thirsty.water).to eq 0
    end

    it "pays all the debt when slaked" do
      thirsty = described_class.new thirst: 8000, water: 0

      expect(thirsty.slake).to eq 8000
      expect(thirsty.quenched?).to be_true
    end
  end

  describe "#refill" do
    it "answers how many units fit" do
      low = described_class.new water: 7

      expect(low.refill 30).to eq Tuning::SKIN_UNITS - 7
      expect(low.water).to eq Tuning::SKIN_UNITS
    end
  end

  describe "#death" do
    it "is nil while both debts are short of the end" do
      expect(sustenance.death).to be_nil
      expect(described_class.new(thirst: Tuning::THIRST_DEATH - 1, hunger: Tuning::HUNGER_DEATH - 1).death)
        .to be_nil
    end

    it "names thirst and hunger at their ends" do
      expect(described_class.new(thirst: Tuning::THIRST_DEATH).death)
        .to eq Sustenance::Death::Thirst
      expect(described_class.new(hunger: Tuning::HUNGER_DEATH).death)
        .to eq Sustenance::Death::Hunger
    end
  end

  describe "a save" do
    it "round trips the debts and the skin" do
      held = described_class.new hunger: 12_345, thirst: 6_789, water: 5

      again = described_class.from_json held.to_json

      expect({again.hunger, again.thirst, again.water}).to eq({12_345, 6_789, 5})
      expect(JSON.parse(held.to_json).as_h.keys.sort!).to eq ["hunger_debt", "skin", "thirst_debt"]
    end

    it "starts fresh for a player saved without it" do
      player = Roguelike::Player.new "proving-ground", 6, 5
      json = JSON.parse(player.to_json).as_h
      json.delete "sustenance"

      again = Roguelike::Player.from_json json.to_json

      expect(again.sustenance.water).to eq Tuning::SKIN_UNITS
      expect(again.sustenance.hunger).to eq 0
    end

    it "turns an old save with water in the skin into no thirst debt and a full skin" do
      again = described_class.from_json %({"hunger":3100,"thirst":40,"water":3,"sipped":120})

      expect({again.hunger, again.thirst, again.water}).to eq({3100, 0, Tuning::SKIN_UNITS})
    end

    it "turns an old save with a dry skin into the old thirst count as debt" do
      again = described_class.from_json %({"hunger":800,"thirst":2600,"water":0,"sipped":0})

      expect({again.hunger, again.thirst, again.water}).to eq({800, 2600, 0})
    end

    it "writes an old save back in the new form" do
      again = described_class.from_json %({"hunger":800,"thirst":2600,"water":0,"sipped":0})

      expect(JSON.parse(again.to_json)).to eq JSON.parse(%({"hunger_debt":800,"thirst_debt":2600,"skin":0}))
    end

    it "loads a whole old game without a crash" do
      floor = Roguelike::Floor.parse "here", ["#####", "#.<.#", "#####"]
      game = Roguelike::Game.new Roguelike::World.new(1_u64, {"here" => floor}),
        Roguelike::Player.new("here", 2, 1)
      json = JSON.parse(game.to_json).as_h
      player = json["player"].as_h
      player["sustenance"] = JSON.parse %({"hunger":5000,"thirst":0,"water":7,"sipped":12})

      again = Roguelike::Game.from_json json.to_json

      expect(again.player.sustenance.hunger).to eq 5000
      expect(again.player.sustenance.water).to eq Tuning::SKIN_UNITS
    end
  end
end
