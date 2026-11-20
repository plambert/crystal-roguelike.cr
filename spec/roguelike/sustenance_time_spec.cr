require "../spec_helper"

Spectator.describe "time shown for food and water" do
  alias Sustenance = Roguelike::Sustenance
  alias FoodBag = Roguelike::FoodBag
  alias Freshness = Roguelike::Freshness
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Tuning = Roguelike::Sustenance::Tuning

  describe "Sustenance.approximate" do
    it "counts ten seconds to a turn" do
      expect(Sustenance::SECONDS_PER_TURN).to eq 10
    end

    it "shows anything under ten minutes as under ten minutes" do
      expect(Sustenance.approximate 0).to eq "<10m"
      expect(Sustenance.approximate 1).to eq "<10m"
      expect(Sustenance.approximate 59).to eq "<10m"
      expect(Sustenance.approximate -5).to eq "<10m"
    end

    it "rounds down to ten minutes" do
      expect(Sustenance.approximate 60).to eq "10m"
      expect(Sustenance.approximate 119).to eq "10m"
      expect(Sustenance.approximate 120).to eq "20m"
      expect(Sustenance.approximate 300).to eq "50m"
      expect(Sustenance.approximate 359).to eq "50m"
    end

    it "writes whole hours with no minutes" do
      expect(Sustenance.approximate 360).to eq "1h"
      expect(Sustenance.approximate 419).to eq "1h"
      expect(Sustenance.approximate 9_000).to eq "25h"
    end

    it "writes hours and minutes together" do
      expect(Sustenance.approximate 420).to eq "1h10m"
      expect(Sustenance.approximate 1_500).to eq "4h10m"
      expect(Sustenance.approximate 3_564).to eq "9h50m"
      expect(Sustenance.approximate 3_599).to eq "9h50m"
      expect(Sustenance.approximate 3_600).to eq "10h"
    end
  end

  describe "Sustenance.rough" do
    it "writes whole hours from ten hours up" do
      expect(Sustenance.rough 3_599).to eq "9h50m"
      expect(Sustenance.rough 3_600).to eq "10h"
      expect(Sustenance.rough 7_304).to eq "20h"
    end
  end

  describe "#food_left" do
    it "counts a character with no debt to hunger's first effect" do
      expect(Sustenance.new.food_left).to eq Tuning::HUNGER_FIRST
      expect(Sustenance.new(hunger: 800).food_left).to eq Tuning::HUNGER_FIRST - 800
    end

    it "counts each stage to the next one" do
      expect(Sustenance.new(hunger: 3_000).food_left).to eq Tuning::HUNGER_HUNGRY - 3_000
      expect(Sustenance.new(hunger: 5_000).food_left).to eq Tuning::HUNGER_SERIOUS - 5_000
      expect(Sustenance.new(hunger: 10_000).food_left).to eq Tuning::HUNGER_SEVERE - 10_000
    end

    it "counts a starving character to death" do
      expect(Sustenance.new(hunger: 30_000).food_left).to eq Tuning::HUNGER_DEATH - 30_000
    end

    it "matches the turns the debt takes to change stage" do
      sustenance = Sustenance.new hunger: 3_234
      left = sustenance.food_left
      (left - 1).times { sustenance.tick }
      expect(sustenance.hunger_stage).to eq Roguelike::HungerStage::Fed

      sustenance.tick
      expect(sustenance.hunger_stage).to eq Roguelike::HungerStage::Hungry
    end
  end

  describe "#water_left" do
    it "counts a character with no debt to thirsty, whatever the skin holds" do
      expect(Sustenance.new(water: 7).water_left).to eq Tuning::THIRST_FIRST
      expect(Sustenance.new(water: 0).water_left).to eq Tuning::THIRST_FIRST
      expect(Sustenance.new(thirst: 600).water_left).to eq Tuning::THIRST_FIRST - 600
    end

    it "counts each stage to the next one" do
      expect(Sustenance.new(thirst: 3_000).water_left).to eq Tuning::THIRST_SERIOUS - 3_000
      expect(Sustenance.new(thirst: 9_000).water_left).to eq Tuning::THIRST_SEVERE - 9_000
      expect(Sustenance.new(thirst: 18_000).water_left).to eq Sustenance::THIRST_DYING - 18_000
    end

    it "counts a dying character to death" do
      debt = Sustenance::THIRST_DYING + 10
      expect(Sustenance.new(thirst: debt).water_left).to eq Tuning::THIRST_DEATH - debt
    end

    it "matches the turns a character takes to grow thirsty" do
      sustenance = Sustenance.new thirst: 17
      left = sustenance.water_left
      (left - 1).times { sustenance.tick }
      expect(sustenance.thirst_stage).to eq Roguelike::ThirstStage::Fine

      sustenance.tick
      expect(sustenance.thirst_stage).to eq Roguelike::ThirstStage::Thirsty
    end
  end

  describe "the times at the new thresholds" do
    it "shows each stage's distance as the player reads it" do
      expect(Sustenance.approximate Sustenance.new.food_left).to eq "6h"
      expect(Sustenance.approximate Sustenance.new(hunger: Tuning::HUNGER_FIRST).food_left).to eq "6h"
      expect(Sustenance.approximate Sustenance.new(hunger: Tuning::HUNGER_HUNGRY).food_left).to eq "12h"
      expect(Sustenance.approximate Sustenance.new(hunger: Tuning::HUNGER_SERIOUS).food_left).to eq "36h"
      expect(Sustenance.approximate Sustenance.new.water_left).to eq "7h"
      expect(Sustenance.approximate Sustenance.new(thirst: Tuning::THIRST_FIRST).water_left).to eq "17h"
      expect(Sustenance.approximate Sustenance.new(thirst: Tuning::THIRST_SERIOUS).water_left).to eq "24h"
    end
  end

  describe "FoodBag.feeds" do
    it "adds up every piece of a stack" do
      meat = Item.new Kind::FreshMeat, count: 2
      expect(FoodBag.feeds meat).to eq 2 * meat.full_satiety
    end

    it "counts a stale stack at its worth" do
      bread = Item.new Kind::Bread, count: 3, age: 1_500
      expect(bread.freshness).to eq Freshness::Stale
      expect(FoodBag.feeds bread).to eq 3 * bread.full_satiety // 2
    end
  end

  describe "FoodBag.turning" do
    it "says when fresh food turns stale" do
      meat = Item.new Kind::FreshMeat, age: 100
      expect(FoodBag.turning meat).to eq({Freshness::Stale, 200})
    end

    it "says when stale food turns rotten" do
      meat = Item.new Kind::FreshMeat, age: 400
      expect(FoodBag.turning meat).to eq({Freshness::Rotten, 200})
    end

    it "says when rotten food turns putrid" do
      meat = Item.new Kind::FreshMeat, age: 700
      expect(FoodBag.turning meat).to eq({Freshness::Putrid, 200})
    end

    it "has nothing for food that keeps" do
      expect(FoodBag.turning Item.new(Kind::Ration)).to be_nil
    end
  end
end
