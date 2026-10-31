require "../spec_helper"

Spectator.describe "food, the food bag and corpses" do
  alias Action = Roguelike::Action
  alias Buff = Roguelike::Buff
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Food = Roguelike::Food
  alias FoodBag = Roguelike::FoodBag
  alias FoodCategory = Roguelike::FoodCategory
  alias FoodSort = Roguelike::FoodSort
  alias Freshness = Roguelike::Freshness
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Kind = Roguelike::Kind
  alias Lore = Roguelike::Lore
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Remains = Roguelike::Remains
  alias Rng = Roguelike::Rng
  alias World = Roguelike::World

  SEED = 20261031_u64

  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  HERE = {1, 1}

  # How hungry the character in `#hall` is: hungry, and a long way from
  # starving.
  HUNGER = 2000

  # A game in a lit hall, with *bag* in the food bag and a character
  # *hunger* turns from their last meal.
  def hall(bag : Array(Item) = [] of Item, hunger : Int32 = HUNGER) : Game
    floor = Floor.parse "hall", HALL
    Playing.daylight floor
    player = Player.new floor.id, *HERE
    player.sustenance.hunger = hunger
    bag.each { |item| player.food_bag.add item }
    game = Game.new World.new(SEED, {floor.id => floor}), player,
      lore: Lore.roll(Rng.new SEED)
    game.enroll
    game
  end

  def food(kind : ItemKind, count : Int32 = 1, age : Int32 = 0) : Item
    Item.new kind, count: count, blessing_known: true, age: age
  end

  def waits(game : Game, turns : Int32) : Array(Event)
    found = [] of Event
    turns.times do
      game.perform Action::Wait.new
      found.concat game.events
    end
    found
  end

  describe "the tables" do
    it "has facts for every food kind" do
      ItemKind.of_class(Roguelike::ItemClass::Food).each do |kind|
        expect(Food.facts?(kind)).not_to be_nil
      end
    end

    it "gives every buffing category at least two kinds" do
      FoodCategory.each do |category|
        next if category.refuse?

        found = Food::FACTS.count { |kind, facts| facts.category == category && !kind.corpse? }
        expect(found).to be >= 2
      end
    end

    it "never spoils a ration and spoils fresh meat fastest" do
      expect(Food.facts(ItemKind::Ration).spoils?).to be_false
      fastest = Food::FACTS.select { |kind, facts| facts.spoils? && !kind.corpse? }
        .min_by { |_kind, facts| facts.keeps }[0]
      expect(fastest).to eq ItemKind::FreshMeat
    end

    it "gives grain the biggest satiety" do
      grain = Food::FACTS.select { |_kind, facts| facts.category.grain? }.max_of(&.[1].satiety)
      others = Food::FACTS.reject { |kind, facts| facts.category.grain? || kind.corpse? }
        .max_of(&.[1].satiety)
      expect(grain).to be > others
    end

    it "puts no fresh meat and no refuse on the floor" do
      expect(Food::LITTER.has_key?(ItemKind::FreshMeat)).to be_false
      Food::LITTER.each_key { |kind| expect(Food.facts(kind).category.refuse?).to be_false }
    end
  end

  describe "freshness" do
    it "goes stale at the keeping time and rotten at twice it" do
      keeps = Food.facts(ItemKind::Apple).keeps
      expect(food(ItemKind::Apple, age: keeps - 1).freshness).to eq Freshness::Fresh
      expect(food(ItemKind::Apple, age: keeps).freshness).to eq Freshness::Stale
      expect(food(ItemKind::Apple, age: keeps * 2).freshness).to eq Freshness::Rotten
    end

    it "keeps a ration fresh however old" do
      ration = food ItemKind::Ration
      10_000.times { ration.ripen }
      expect(ration.freshness).to eq Freshness::Fresh
    end

    it "halves what stale food feeds" do
      keeps = Food.facts(ItemKind::Bread).keeps
      expect(food(ItemKind::Bread, age: keeps).nourishment)
        .to eq Food.facts(ItemKind::Bread).satiety // 2
    end

    it "does not stack two foods of different ages" do
      expect(food(ItemKind::Apple, age: 0).stacks_with?(food(ItemKind::Apple, age: 5))).to be_false
      expect(food(ItemKind::Apple, age: 5).stacks_with?(food(ItemKind::Apple, age: 5))).to be_true
    end
  end

  describe "names" do
    it "says how fresh a food is and whether it is bitten" do
      lore = Lore.new
      keeps = Food.facts(ItemKind::Apple).keeps
      expect(lore.name(food(ItemKind::Apple))).to eq "an apple"
      expect(lore.name(food(ItemKind::Apple, age: keeps))).to eq "a stale apple"
      expect(lore.name(food(ItemKind::Apple, count: 2, age: keeps * 2))).to eq "2 rotten apples"

      ration = food ItemKind::Ration
      ration.bite 100
      expect(lore.name(ration)).to eq "a partly eaten ration"
    end

    it "names a corpse by the creature it was" do
      corpse = Game.remains_of(Kind::GoblinWarrior).first
      expect(Lore.new.name(corpse)).to eq "a goblin fighter corpse"
    end
  end

  describe Roguelike::FoodBag do
    it "holds up to its weight limit and no more" do
      bag = FoodBag.new
      count = FoodBag::LIMIT // ItemKind::Ration.facts.weight
      expect(bag.add(food(ItemKind::Ration, count))).not_to be_nil
      expect(bag.add(food(ItemKind::Nuts))).to be_nil
      expect(bag.weight).to eq count * ItemKind::Ration.facts.weight
    end

    it "takes no corpse and nothing that is not food" do
      bag = FoodBag.new
      expect(bag.add(Game.remains_of(Kind::Rat).first)).to be_nil
      expect(bag.add(Item.new(ItemKind::Dagger))).to be_nil
    end

    it "takes rotten flesh and bones as dead weight" do
      bag = FoodBag.new
      Game.remains_of(Kind::Zombie).each { |item| expect(bag.add(item)).not_to be_nil }
      expect(bag.items.none?(&.edible?)).to be_true
    end

    it "sorts by each key" do
      bag = FoodBag.new
      bag.add food(ItemKind::Ration)
      bag.add food(ItemKind::Nuts)
      bag.add food(ItemKind::FreshMeat, age: Food.facts(ItemKind::FreshMeat).keeps)
      bag.add food(ItemKind::Apple)

      expect(bag.sorted(FoodSort::Weight).first.kind).to eq ItemKind::FreshMeat
      expect(bag.sorted(FoodSort::Value).first.kind).to eq ItemKind::Ration
      expect(bag.sorted(FoodSort::Name).map(&.kind))
        .to eq [ItemKind::Apple, ItemKind::Nuts, ItemKind::FreshMeat, ItemKind::Ration]
      expect(bag.sorted(FoodSort::Type).first.kind).to eq ItemKind::FreshMeat
      expect(bag.sorted(FoodSort::Freshness).last.kind).to eq ItemKind::FreshMeat
    end

    it "round-trips through JSON with ages and bites" do
      bag = FoodBag.new
      bag.add food(ItemKind::Apple, age: 12)
      bitten = food ItemKind::Ration
      bitten.bite 300
      bag.add bitten

      read = FoodBag.from_json bag.to_json
      expect(read).to eq bag
      expect(read.items[0].age).to eq 12
      expect(read.items[1].eaten).to eq 300
    end
  end

  describe "the character" do
    it "starts with two rations in the bag and none in the pack" do
      game = Game.start Rng.new(SEED)
      bag = game.player.food_bag
      expect(bag.items.map(&.kind)).to eq [ItemKind::Ration]
      expect(bag.items.first.count).to eq 2
      expect(bag.items.first.id).not_to eq 0
      expect(game.player.inventory.select(&.food?)).to be_empty
    end

    it "loads an old save with an empty bag" do
      player = Player.new "hall", 1, 1
      player.food_bag.add food(ItemKind::Ration)
      json = JSON.parse(player.to_json).as_h
      json.delete "food_bag"
      json.delete "buffs"

      read = Player.from_json json.to_json
      expect(read.food_bag.empty?).to be_true
      expect(read.buffs).to be_empty
    end

    it "keeps a buff that does not stack" do
      player = Player.new "hall", 1, 1
      status = Event::Status::WellFed
      expect(player.buff(status, 2, 300)).to eq Buff::Taken::Started
      expect(player.pace.speed).to eq Roguelike::Pace::NORMAL + 2
      player.pass_buffs
      expect(player.buff(status, 2, 300)).to eq Buff::Taken::Renewed
      expect(player.buffs.first.left).to eq 300
      expect(player.buff(status, 5, 300)).to eq Buff::Taken::Stronger
      expect(player.buff(status, 2, 300)).to eq Buff::Taken::Weaker
      expect(player.buff_power(status)).to eq 5
      expect(player.pace.speed).to eq Roguelike::Pace::NORMAL + 5
    end

    it "lands a swing more often with steady hands and less often when sick" do
      player = Player.new "hall", 1, 1
      before = player.to_hit
      player.buff Event::Status::SteadyHand, 1, 300
      expect(player.to_hit).to eq before + 1
      player.buff Event::Status::Sick, 1, 300
      expect(player.to_hit).to eq before
    end

    it "lists food buffs in the character pane's reading" do
      player = Player.new "hall", 1, 1
      player.buff Event::Status::SteadyAim, 1, 300
      expect(player.lasting.map(&.status)).to eq [Event::Status::SteadyAim]
    end
  end

  describe "picking up food" do
    it "puts food in the bag rather than the pack" do
      game = hall
      game.floor.drop *HERE, food(ItemKind::Apple)
      game.enroll
      game.perform Action::PickUp.new

      expect(game.player.food_bag.items.map(&.kind)).to eq [ItemKind::Apple]
      expect(game.player.inventory.empty?).to be_true
      expect(game.here).to be_empty
    end

    it "leaves food the bag has no room for" do
      game = hall [food(ItemKind::Ration, FoodBag::LIMIT // 4)]
      game.floor.drop *HERE, food(ItemKind::Nuts)
      game.enroll
      game.perform Action::PickUp.new

      expect(game.here.map(&.kind)).to eq [ItemKind::Nuts]
      expect(game.events.any? { |event| event.is_a?(Event::Refused) && event.reason.bag_full? })
        .to be_true
    end

    it "never offers to pick up a corpse" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      expect(game.legal.any?(Action::PickUp)).to be_false
    end

    it "drops a stack from the bag" do
      game = hall [food(ItemKind::Apple, 2)]
      id = game.player.food_bag.items.first.id
      expect(game.legal.any? { |action| action.is_a?(Action::Drop) && action.item == id }).to be_true
      game.perform Action::Drop.new(id)

      expect(game.player.food_bag.empty?).to be_true
      expect(game.here.first.count).to eq 2
    end
  end

  describe "eating" do
    it "eats one of a stack and gives the buff" do
      game = hall [food(ItemKind::Nuts, 2)]
      id = game.player.food_bag.items.first.id
      game.perform Action::Eat.new(id)

      expect(game.player.food_bag.items.first.count).to eq 1
      expect(game.events.any?(Event::Ate)).to be_true
      expect(game.player.buff_power(Event::Status::SteadyAim)).to eq Food::AIM
      expect(game.turn).to eq 1
    end

    it "takes what it took off the character's hunger" do
      game = hall [food(ItemKind::Apple)]
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)

      expect(game.player.sustenance.hunger).to eq HUNGER - Food.facts(ItemKind::Apple).satiety + 1
    end

    it "keeps what is left of a food eaten by a character near full" do
      game = hall [food(ItemKind::Ration, 2)], hunger: 100
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)

      bag = game.player.food_bag.items
      expect(bag.map(&.count)).to eq [1, 1]
      expect(bag.last.eaten).to eq 100
      expect(game.player.sustenance.full?).to be_false
      expect(game.events.select(Event::Ate).first.as(Event::Ate).whole?).to be_false
    end

    it "eats nothing and spends no turn when the character is full" do
      game = hall [food(ItemKind::Ration)], hunger: 0
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)

      expect(game.player.food_bag.items.first.bitten?).to be_false
      expect(game.turn).to eq 0
      expect(game.events.any? { |event| event.is_a?(Event::Refused) && event.reason.full? })
        .to be_true
    end

    it "halves how fast thirst builds while the fruit buff runs" do
      plain = hall
      fed = hall
      [plain, fed].each do |game|
        game.player.sustenance.water = 0
        game.player.sustenance.thirst = 1
      end
      fed.player.buff Event::Status::Refreshed, 1, Food::BUFF_TURNS
      waits plain, 20
      waits fed, 20

      expect(plain.player.sustenance.thirst).to eq 21
      expect(fed.player.sustenance.thirst).to eq 11
    end

    it "makes the character sick on rotten food" do
      keeps = Food.facts(ItemKind::Apple).keeps
      game = hall [food(ItemKind::Apple, age: keeps * 2)]
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)

      expect(game.player.buff_power(Event::Status::Sick)).to eq Food::SICK_AIM
      expect(game.player.buff_power(Event::Status::Refreshed)).to eq 0
    end

    it "gives no aim buff for stale nuts" do
      keeps = Food.facts(ItemKind::Nuts).keeps
      game = hall [food(ItemKind::Nuts, age: keeps)]
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)

      expect(game.player.buffs).to be_empty
    end

    it "refuses bones" do
      game = hall [Item.new(ItemKind::Bones, blessing_known: true)]
      id = game.player.food_bag.items.first.id
      expect(game.legal.any?(Action::Eat)).to be_false
      expect(game.perform(Action::Eat.new(id)).refused?).to be_true
    end

    it "ends a buff after its turns and says so" do
      game = hall [food(ItemKind::Turnip)]
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)
      seen = waits game, Food::BUFF_TURNS

      expect(game.player.buffs).to be_empty
      expect(seen.any? { |event| event.is_a?(Event::StatusEnd) && event.status.steady_hand? })
        .to be_true
    end
  end

  describe "spoilage" do
    it "fires food_spoiled once when bag food turns" do
      keeps = Food.facts(ItemKind::Berries).keeps
      game = hall [food(ItemKind::Berries, age: keeps - 2)]
      seen = waits game, 5

      spoiled = seen.select(Event::FoodSpoiled)
      expect(spoiled.size).to eq 1
      expect(spoiled.first.as(Event::FoodSpoiled).freshness).to eq Freshness::Stale
    end

    it "keeps rotten food in the bag" do
      keeps = Food.facts(ItemKind::Berries).keeps
      game = hall [food(ItemKind::Berries, age: keeps * 2)]
      waits game, 3
      expect(game.player.food_bag.items.first.freshness).to eq Freshness::Rotten
    end
  end

  describe "corpses" do
    it "follows the species" do
      expect(Kind::Wolf.remains).to eq Remains::Corpse
      expect(Kind::GoblinScout.remains).to eq Remains::Corpse
      expect(Kind::OrcWarlord.remains).to eq Remains::Corpse
      expect(Kind::WhiteSlime.remains).to eq Remains::Nothing
      expect(Kind::StoneGolem.remains).to eq Remains::Nothing
      expect(Kind::Imp.remains).to eq Remains::Nothing
      expect(Kind::Zombie.remains).to eq Remains::FleshAndBones
      expect(Kind::Skeleton.remains).to eq Remains::Bones
    end

    it "leaves a corpse where a kill falls" do
      game = hall
      goblin = Monster.new Kind::GoblinWarrior, 2, 1, "band-one"
      game.floor.place goblin
      game.enroll
      game.kill goblin

      corpse = game.floor.items(2, 1).find(&.corpse?)
      expect(corpse).not_to be_nil
      expect(game.events.any?(Event::CorpseLeft)).to be_true
    end

    it "leaves nothing of a slime" do
      game = hall
      slime = Monster.new Kind::WhiteSlime, 2, 1, "band-one"
      game.floor.place slime
      game.enroll
      game.kill slime
      expect(game.floor.items(2, 1).any?(&.food?)).to be_false
    end

    it "eats a corpse where it lies" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Rat).first
      game.enroll
      corpse = game.here.first
      expect(game.legal.any? { |action| action.is_a?(Action::Eat) && action.item == corpse.id })
        .to be_true
      game.perform Action::Eat.new(corpse.id)

      expect(game.here).to be_empty
      expect(game.player.buff_power(Event::Status::WellFed)).to eq Food::PACE
    end

    it "cuts a corpse into meat for the bag" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      game.perform Action::Cut.new(game.here.first.id)

      meat = game.player.food_bag.items
      expect(meat.map(&.kind)).to eq [ItemKind::FreshMeat]
      expect(meat.first.count).to eq Food::CUTS[Roguelike::Size::Medium]
      expect(game.here).to be_empty
      expect(game.turn).to eq 1
    end

    it "rots away on the floor" do
      game = hall
      game.floor.drop 5, 1, Game.remains_of(Kind::Wolf).first
      game.enroll
      seen = waits game, Food::CORPSE_KEEPS * 2

      expect(game.floor.items(5, 1)).to be_empty
      expect(seen.any?(Event::CorpseRotted)).to be_true
    end

    it "will not cut a stale corpse" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Wolf).first
      game.enroll
      waits game, Food::CORPSE_KEEPS
      expect(game.legal.any?(Action::Cut)).to be_false
      expect(game.legal.any?(Action::Eat)).to be_true
    end
  end

  describe "floor food" do
    it "puts some food on a dug floor" do
      game = Game.dug Rng.new(SEED)
      found = [] of Item
      game.floor.each_pile { |_column, _row, pile| found.concat pile.select(&.food?) }

      expect(found).not_to be_empty
      found.each do |item|
        expect(Food::LITTER.has_key?(item.kind)).to be_true
        expect(item.freshness).to eq Freshness::Fresh
        expect(item.id).not_to eq 0
      end
    end
  end
end
