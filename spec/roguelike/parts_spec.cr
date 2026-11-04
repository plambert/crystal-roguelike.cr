require "../spec_helper"

Spectator.describe "the parts of beasts" do
  alias Action = Roguelike::Action
  alias Buff = Roguelike::Buff
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Food = Roguelike::Food
  alias FoodCategory = Roguelike::FoodCategory
  alias Freshness = Roguelike::Freshness
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemClass = Roguelike::ItemClass
  alias ItemKind = Roguelike::ItemKind
  alias Kind = Roguelike::Kind
  alias Lore = Roguelike::Lore
  alias Monster = Roguelike::Monster
  alias Observation = Roguelike::Observation
  alias Parts = Roguelike::Parts
  alias Player = Roguelike::Player
  alias Rng = Roguelike::Rng
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # A seed on which the first wolf killed in `#hall` leaves its liver and a
  # fang both.
  BOTH = 7_u64

  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  HERE = {1, 1}

  # A game in the hall on *seed*, lit unless *dark*, with a character a
  # long way from full.
  def hall(seed : UInt64 = BOTH, dark : Bool = false) : Game
    floor = Floor.parse "hall", HALL
    Playing.daylight floor unless dark
    player = Player.new floor.id, *HERE
    player.sustenance.hunger = 2000
    game = Game.new World.new(seed, {floor.id => floor}), player,
      lore: Lore.roll(Rng.new seed)
    game.enroll
    game
  end

  # What a creature of *kind* left in `#hall` on *seed* when the character
  # killed it.
  def left_by(kind : Kind, seed : UInt64 = BOTH) : Array(ItemKind)
    game = hall seed
    creature = Monster.new kind, 2, 1, "band-one"
    game.floor.place creature
    game.enroll
    game.kill creature
    game.floor.items(2, 1).map &.kind
  end

  def part(kind : ItemKind, count : Int32 = 1, age : Int32 = 0) : Item
    Item.new kind, count: count, blessing_known: true, age: age
  end

  def waits(game : Game, turns : Int32) : Nil
    turns.times { game.perform Action::Wait.new }
  end

  describe "the table" do
    it "gives each beast one edible part and one inedible part at most" do
      Parts::TABLE.each do |species, parts|
        expect(species.butchery.beast?).to be_true
        expect(parts.count(&.edible?)).to be <= 1
        expect(parts.count { |one| !one.edible? }).to be <= 1
      end
    end

    it "gives every edible part food facts, a small satiety and a buff of its own" do
      Parts::TABLE.each_value do |parts|
        parts.select(&.edible?).each do |one|
          facts = Food.facts one.kind
          expect(facts.category).to eq FoodCategory::Delicacy
          expect(facts.satiety).to be_between 100, 300
          expect(facts.value).to eq one.value
          expect(one.buff).not_to be_nil
          expect(one.power).to be > 0
          expect(Food.buff(one.kind)).to eq one.buff
        end
      end
    end

    it "gives no inedible part food facts or a buff" do
      Parts::TABLE.each_value do |parts|
        parts.reject(&.edible?).each do |one|
          expect(one.kind.item_class).to eq ItemClass::Reagent
          expect(Food.facts?(one.kind)).to be_nil
          expect(one.buff).to be_nil
        end
      end
    end

    it "lists no part for a humanoid or a creature that leaves no corpse" do
      [Kind::GoblinWarrior, Kind::Orc, Kind::Werewolf, Kind::Zombie, Kind::WhiteSlime].each do |kind|
        expect(Parts.of(kind)).to be_empty
      end
      expect(Parts.of(Kind::GiantRat).map(&.kind)).to eq [ItemKind::RatTail]
    end

    it "leaves each part about as often as its chance says" do
      root = Rng.new 20261103_u64
      livers = 0
      4000.times do |id|
        livers += 1 if Parts.roll(Kind::Wolf, root.derive("parts", id)).any?(&.kind.wolf_liver?)
      end
      expect(livers).to be_between 800, 1200
    end
  end

  describe "a death" do
    it "can leave a wolf's liver and fang beside its corpse" do
      expect(left_by(Kind::Wolf)).to eq [ItemKind::Corpse, ItemKind::WolfLiver, ItemKind::WolfFang]
    end

    it "names the parts in the event that says what a death left" do
      game = hall
      wolf = Monster.new Kind::Wolf, 2, 1, "band-one"
      game.floor.place wolf
      game.enroll
      game.kill wolf

      left = game.events.compact_map(&.as?(Event::CorpseLeft)).first
      expect(left.items.size).to eq 3
    end

    it "leaves the same parts for the same seed" do
      expect(left_by(Kind::Wolf)).to eq left_by(Kind::Wolf)
    end

    it "never leaves a part of a goblin or a werewolf" do
      (1_u64..40_u64).each do |seed|
        expect(left_by(Kind::GoblinWarrior, seed)).to eq [ItemKind::Corpse]
        expect(left_by(Kind::Werewolf, seed)).to eq [ItemKind::Corpse]
      end
    end
  end

  describe "an edible part" do
    it "goes in the food bag when it is picked up" do
      game = hall
      game.floor.drop *HERE, part(ItemKind::WolfLiver)
      game.enroll
      game.perform Action::PickUp.new(game.here.first.id)

      expect(game.player.food_bag.items.map(&.kind)).to eq [ItemKind::WolfLiver]
      expect(game.player.inventory.empty?).to be_true
    end

    it "gives its buff for a long while when it is eaten" do
      game = hall
      game.player.food_bag.add part(ItemKind::BearHeart)
      game.enroll
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)

      held = game.player.buffs.find!(&.status.mighty?)
      expect(held.power).to eq 2

      # The turn the meal took counts one off.
      expect(held.left).to eq Parts::BUFF_TURNS - 1
      expect(Parts::BUFF_TURNS).to be > Food::BUFF_TURNS
      expect(game.events.any? { |event| event.is_a?(Event::StatusStart) && event.status.mighty? })
        .to be_true
    end

    it "gives half its buff stale and makes the character sick rotten" do
      keeps = Food.facts(ItemKind::SnakeEyes).keeps
      game = hall
      game.player.food_bag.add part(ItemKind::SnakeEyes, age: keeps)
      game.enroll
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)
      expect(game.player.night_sight).to eq 2

      game = hall
      game.player.food_bag.add part(ItemKind::SnakeEyes, age: keeps * 2)
      game.enroll
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)
      expect(game.player.night_sight).to eq 0
      expect(game.player.buff_power(Event::Status::Sick)).to be > 0
    end

    it "spoils on the fresh meat timer" do
      meat = Food.facts(ItemKind::FreshMeat).keeps
      expect(Food.facts(ItemKind::WolfLiver).keeps).to eq meat

      game = hall
      game.player.food_bag.add part(ItemKind::WolfLiver)
      waits game, meat
      expect(game.player.food_bag.items.first.freshness).to eq Freshness::Stale
    end

    it "shows in the food bag observation with its class and buff" do
      game = hall
      game.player.food_bag.add part(ItemKind::AntJelly)
      meal = Observation::Meal.of game.lore, game.player.food_bag.items.first

      expect(meal.item_class).to eq ItemClass::Delicacy
      expect(meal.buff).to eq Event::Status::Quickened
      expect(meal.to_json).to contain %("item_class":)
    end
  end

  describe "an inedible part" do
    it "goes in the pack and stacks with another of its kind" do
      game = hall
      2.times do
        game.floor.drop *HERE, part(ItemKind::WolfFang)
        game.enroll
        game.perform Action::PickUp.new(game.here.first.id)
      end

      expect(game.player.food_bag.empty?).to be_true
      expect(game.player.inventory.entries.map { |(_, item)| {item.kind, item.count} })
        .to eq [{ItemKind::WolfFang, 2}]
    end

    it "never spoils and is never eaten" do
      fang = part(ItemKind::WolfFang)
      1000.times { fang.ripen }
      expect(fang.freshness).to eq Freshness::Fresh
      expect(fang.edible?).to be_false
    end

    it "is named plainly" do
      expect(hall.lore.name(part(ItemKind::BoarTusk, 3))).to eq "3 boar tusks"
    end
  end

  describe "the buffs" do
    it "makes melee hit harder after a bear's heart" do
      player = Player.new "hall", 1, 1
      before = player.damage.bonus
      player.buff Event::Status::Mighty, 2, Parts::BUFF_TURNS
      expect(player.damage.bonus).to eq before + 2
    end

    it "closes wounds faster after a liver" do
      player = Player.new "hall", 1, 1
      before = player.regeneration
      player.buff Event::Status::Mending, 2, Parts::BUFF_TURNS
      expect(player.regeneration).to eq before // 3
    end

    it "makes the character quicker after ant jelly, on top of a meal of meat" do
      player = Player.new "hall", 1, 1
      player.buff Event::Status::WellFed, Food::PACE, Food::BUFF_TURNS
      player.buff Event::Status::Quickened, 10, Parts::BUFF_TURNS
      expect(player.pace.speed).to eq Roguelike::Pace::NORMAL + Food::PACE + 10
    end

    it "sees the squares nearby in the dark after a snake's eyes" do
      game = hall dark: true
      expect(game.sight.includes?(3, 1)).to be_false

      game.player.buff Event::Status::NightEyes, 4, Parts::BUFF_TURNS
      expect(game.sight.includes?(3, 1)).to be_true
      expect(game.sight.includes?(5, 2)).to be_true
      expect(game.sight.includes?(9, 1)).to be_false
    end

    it "draws each as a buff pill" do
      [Event::Status::Mending, Event::Status::Mighty, Event::Status::NightEyes,
       Event::Status::Quickened].each do |status|
        expect(Roguelike::Lasting.buff?(status)).to be_true
        expect(Roguelike::Ui::CharacterPane::PILL_NAMES[status]?).not_to be_nil
      end
    end
  end
end
