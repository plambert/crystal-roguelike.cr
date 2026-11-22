require "../spec_helper"

Spectator.describe "food, the food bag and corpses" do
  alias Action = Roguelike::Action
  alias Buff = Roguelike::Buff
  alias Butchery = Roguelike::Butchery
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
  alias Size = Roguelike::Size
  alias Sustenance = Roguelike::Sustenance
  alias World = Roguelike::World

  SEED = 20261031_u64

  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  HERE = {1, 1}

  # How hungry the character in `#hall` is: enough to eat most foods whole,
  # and a long way from starving.
  HUNGER = 2000

  # How hungry a starving character is.
  STARVING = Sustenance::Tuning::HUNGER_SEVERE

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

    it "puts how fresh meat is in place of fresh" do
      lore = Lore.new
      keeps = Food.facts(ItemKind::FreshMeat).keeps
      expect(lore.name(food(ItemKind::FreshMeat))).to eq "a piece of fresh meat"
      expect(lore.name(food(ItemKind::FreshMeat, age: keeps))).to eq "a piece of stale meat"
      expect(lore.name(food(ItemKind::FreshMeat, age: keeps * 2))).to eq "a piece of rotten meat"
      expect(lore.name(food(ItemKind::FreshMeat, count: 2, age: keeps * 2)))
        .to eq "2 pieces of rotten meat"

      bitten = food ItemKind::FreshMeat, age: keeps
      bitten.bite 100
      expect(lore.name(bitten)).to eq "a partly eaten piece of stale meat"
      expect(Roguelike::Ui::Naming.short(lore, bitten)).to eq "partly eaten stale meat"
    end

    it "keeps a freshness word only where a name has none" do
      lore = Lore.new
      ItemKind.of_class(Roguelike::ItemClass::Food).each do |kind|
        facts = Food.facts kind
        next unless facts.spoils?

        rotten = Item.new kind, blessing_known: true, age: facts.keeps * 2,
          creature: kind.corpse? ? Kind::Rat : nil
        expect(lore.name(rotten).split(' ').count(&.in?(%w[fresh stale rotten]))).to eq 1
      end
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

    it "takes neither a putrid mass nor bones" do
      bag = FoodBag.new
      mass, bones = Game.remains_of(Kind::Zombie)
      expect(bag.add(mass)).to be_nil
      expect(bag.add(bones)).to be_nil
      expect(bag.empty?).to be_true
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

    it "moves bones from the bag of an old save into the pack" do
      game = hall [food(ItemKind::Ration)]
      pair = JSON.parse(Item.new(ItemKind::Bones, blessing_known: true).to_json).as_h
      pair["count"] = JSON::Any.new 2_i64
      game.player.food_bag.items << Item.from_json(pair.to_json)
      game.enroll

      read = Game.from_json game.to_json
      expect(read.player.food_bag.items.map(&.kind)).to eq [ItemKind::Ration]
      carried = read.player.inventory.items.map &.[1]
      expect(carried.map(&.kind)).to eq [ItemKind::Bones, ItemKind::Bones]
      expect(carried.map(&.id).uniq!.size).to eq 2
      expect(carried.none?(&.id.zero?)).to be_true
    end

    it "drops bones from the bag of an old save underfoot when the pack is full" do
      game = hall
      Roguelike::Inventory::LETTERS.each { game.player.inventory.add Item.new(ItemKind::Dagger) }
      game.player.food_bag.items << Item.new(ItemKind::Bones, blessing_known: true)
      game.enroll

      read = Game.from_json game.to_json
      expect(read.player.food_bag.empty?).to be_true
      expect(read.here.map(&.kind)).to eq [ItemKind::Bones]
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

    it "puts bones in the pack, one to a letter" do
      game = hall
      2.times { game.floor.drop *HERE, Item.new(ItemKind::Bones, blessing_known: true) }
      game.enroll
      2.times { game.perform Action::PickUp.new(game.here.first.id) }

      expect(game.player.food_bag.empty?).to be_true
      expect(game.player.inventory.entries.map { |(_, item)| {item.kind, item.count} })
        .to eq [{ItemKind::Bones, 1}, {ItemKind::Bones, 1}]
    end

    it "leaves bones when the pack is full" do
      game = hall
      Roguelike::Inventory::LETTERS.each { game.player.inventory.add Item.new(ItemKind::Dagger) }
      game.floor.drop *HERE, Item.new(ItemKind::Bones, blessing_known: true)
      game.enroll
      game.perform Action::PickUp.new

      expect(game.here.map(&.kind)).to eq [ItemKind::Bones]
      expect(game.events.any? { |event| event.is_a?(Event::Refused) && event.reason.pack_full? })
        .to be_true
    end

    it "never offers to pick up a corpse" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      expect(game.legal.any?(Action::PickUp)).to be_false
    end

    it "cuts a fresh beast corpse into meat when it is picked up" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Wolf).first
      game.enroll
      corpse = game.here.first
      game.perform Action::PickUp.new

      expect(game.events.select(Event::Butchered).map(&.as(Event::Butchered).item)).to eq [corpse.id]
      expect(game.player.food_bag.items.map(&.kind)).to eq [ItemKind::FreshMeat]
      expect(game.player.food_bag.items.first.count).to eq Food::CUTS[corpse.size]
      expect(game.here).to be_empty
      expect(game.turn).to eq 1
    end

    it "refuses to pick up a stale corpse" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Wolf).first
      game.enroll
      waits game, Food::CORPSE_KEEPS
      turn = game.turn
      corpse = game.here.first
      game.perform Action::PickUp.new(corpse.id)

      expect(game.events.any? { |event| event.is_a?(Event::Refused) && event.reason.too_old? })
        .to be_true
      expect(game.here).to eq [corpse]
      expect(game.player.food_bag.empty?).to be_true
      expect(game.turn).to eq turn
    end

    it "refuses to pick up a humanoid corpse" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      game.perform Action::PickUp.new

      expect(game.events.any? { |event| event.is_a?(Event::Refused) && event.reason.not_butchered? })
        .to be_true
      expect(game.here.size).to eq 1
      expect(game.turn).to eq 0
    end

    it "passes over a humanoid corpse when picking up everything" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::GoblinWarrior).first
      game.floor.drop *HERE, food(ItemKind::Apple)
      game.enroll

      expect(game.pick_up_all).to eq 1
      expect(game.player.food_bag.items.map(&.kind)).to eq [ItemKind::Apple]
      expect(game.here.map(&.corpse?)).to eq [true]
      expect(game.events.any?(Event::Refused)).to be_false
    end

    it "says why when a humanoid corpse is all there is to pick up" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::GoblinWarrior).first
      game.enroll

      expect(game.pick_up_all).to eq 0
      expect(game.events.any? { |event| event.is_a?(Event::Refused) && event.reason.not_butchered? })
        .to be_true
      expect(game.here.size).to eq 1
    end

    it "cuts a beast corpse when picking up everything" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Rat).first
      game.floor.drop *HERE, food(ItemKind::Apple)
      game.enroll

      expect(game.pick_up_all).to eq 2
      expect(game.player.food_bag.items.map(&.kind)).to eq [ItemKind::FreshMeat, ItemKind::Apple]
      expect(game.here).to be_empty
    end

    it "never cuts a corpse it steps on" do
      game = hall
      game.floor.drop HERE[0] + 1, HERE[1], Game.remains_of(Kind::Wolf).first
      game.enroll
      game.perform Action::Move.new(Roguelike::Direction::East)

      expect(game.here.map(&.corpse?)).to eq [true]
      expect(game.player.food_bag.empty?).to be_true
      expect(game.events.any?(Event::Butchered)).to be_false
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
      game = hall
      game.player.inventory.add Item.new(ItemKind::Bones, blessing_known: true)
      game.enroll
      id = game.player.inventory.items.first[1].id
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

    it "names the food as it was before it turned" do
      keeps = Food.facts(ItemKind::FreshMeat).keeps
      meat = food ItemKind::FreshMeat, age: keeps * 2 - 1
      meat.bite 100
      game = hall [meat]
      seen = waits game, 1

      spoiled = seen.select(Event::FoodSpoiled).first.as(Event::FoodSpoiled)
      expect(spoiled.freshness).to eq Freshness::Rotten
      expect(game.log.lines)
        .to contain "A partly eaten piece of stale meat in your food bag has gone rotten."
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

    it "knows which corpses cut into meat" do
      expect(Kind::Wolf.butchery).to eq Butchery::Beast
      expect(Kind::Ant.butchery).to eq Butchery::Beast
      expect(Kind::GoblinScout.butchery).to eq Butchery::Humanoid
      expect(Kind::OrcWarlord.butchery).to eq Butchery::Humanoid
      expect(Kind::Werewolf.butchery).to eq Butchery::Humanoid
      expect(Kind::Zombie.butchery).to eq Butchery::None
      expect(Kind::WhiteSlime.butchery).to eq Butchery::None
      expect(Game.remains_of(Kind::Orc).first.butchery).to eq Butchery::Humanoid
    end

    it "will not cut up a humanoid corpse" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::GoblinWarrior).first
      game.enroll
      corpse = game.here.first
      expect(game.cuttable).to be_empty
      expect(game.legal.any?(Action::Cut)).to be_false

      expect(game.cut(corpse)).to be_false
      expect(game.events.any? { |event| event.is_a?(Event::Refused) && event.reason.not_butchered? })
        .to be_true
      expect(game.here).to eq [corpse]
      expect(game.player.food_bag.empty?).to be_true
      expect(game.turn).to eq 0
    end

    it "takes a point of maximum hit points for each meal of a humanoid corpse" do
      game = hall hunger: STARVING
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      corpse = game.here.first
      before = game.player.max_hit_points
      expect(game.player.hit_points).to eq before
      game.perform Action::Eat.new(corpse.id)

      expect(game.player.max_hit_points).to eq before - 1
      expect(game.player.hit_points).to eq before - 1
      expect(game.events.select(Event::Weakened).map(&.as(Event::Weakened).amount)).to eq [1]
    end

    it "costs nothing to eat a beast corpse" do
      game = hall hunger: STARVING
      game.floor.drop *HERE, Game.remains_of(Kind::Rat).first
      game.enroll
      before = game.player.max_hit_points
      game.perform Action::Eat.new(game.here.first.id)

      expect(game.player.max_hit_points).to eq before
      expect(game.events.any?(Event::Weakened)).to be_false
    end

    it "keeps lost maximum hit points through a save" do
      game = hall
      game.player.waste 2
      loaded = Player.from_json game.player.to_json
      expect(loaded.max_hit_points).to eq game.player.max_hit_points
      expect(Player.from_json(hall.player.to_json).to_json).not_to contain "wasted"
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
      game = hall hunger: STARVING
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
      game.floor.drop *HERE, Game.remains_of(Kind::Wolf).first
      game.enroll
      size = game.here.first.size
      game.perform Action::Cut.new(game.here.first.id)

      meat = game.player.food_bag.items
      expect(meat.map(&.kind)).to eq [ItemKind::FreshMeat]
      expect(meat.first.count).to eq Food::CUTS[size]
      expect(game.here).to be_empty
      expect(game.turn).to eq 1
    end

    it "cuts a small or medium beast into one piece and a large one into two" do
      expect(Food::CUTS).to eq({Size::Small => 1, Size::Medium => 1, Size::Large => 2})

      {Kind::Rat => 1, Kind::Wolf => 1, Kind::Bear => 2}.each do |kind, pieces|
        game = hall
        game.floor.drop *HERE, Game.remains_of(kind).first
        game.enroll
        game.perform Action::Cut.new(game.here.first.id)

        expect(game.player.food_bag.items.sum(&.count)).to eq(pieces), kind.to_s
      end
    end

    it "makes pieces of fresh meat worth 175 each" do
      expect(Food.facts(ItemKind::FreshMeat).satiety).to eq 175
    end

    it "rots to one putrid mass on the floor" do
      game = hall
      game.floor.drop 5, 1, Game.remains_of(Kind::Wolf).first
      game.enroll
      corpse = game.floor.items(5, 1).first.id
      seen = waits game, Food::CORPSE_KEEPS * 2

      left = game.floor.items(5, 1)
      expect(left.map { |item| {item.kind, item.count, item.id} })
        .to eq [{ItemKind::PutridMass, 1, corpse}]
      rotted = seen.select(Event::CorpseRotted).map(&.as(Event::CorpseRotted))
      expect(rotted.map { |event| {event.item, event.mass, event.at} }).to eq [{corpse, corpse, {5, 1}}]
    end

    it "leaves one putrid mass of a partly eaten corpse" do
      game = hall
      corpse = Game.remains_of(Kind::Bear).first
      corpse.bite 100
      game.floor.drop 5, 1, corpse
      game.enroll
      waits game, Food::CORPSE_KEEPS * 2

      expect(game.floor.items(5, 1).map { |item| {item.kind, item.count} })
        .to eq [{ItemKind::PutridMass, 1}]
    end

    it "lets a rotting corpse join a putrid mass already on its square" do
      game = hall
      game.floor.drop 5, 1, Item.new(ItemKind::PutridMass, count: 2, blessing_known: true)
      game.floor.drop 5, 1, Game.remains_of(Kind::Wolf).first
      game.enroll
      pile = game.floor.items(5, 1).first.id
      seen = waits game, Food::CORPSE_KEEPS * 2

      expect(game.floor.items(5, 1).map { |item| {item.kind, item.count, item.id} })
        .to eq [{ItemKind::PutridMass, 3, pile}]
      expect(seen.select(Event::CorpseRotted).first.as(Event::CorpseRotted).mass).to eq pile
    end

    it "will not cut a stale corpse" do
      game = hall hunger: STARVING
      game.floor.drop *HERE, Game.remains_of(Kind::Wolf).first
      game.enroll
      waits game, Food::CORPSE_KEEPS
      expect(game.legal.any?(Action::Cut)).to be_false
      expect(game.legal.any?(Action::Eat)).to be_true
    end
  end

  describe "putrid masses" do
    def mass(count : Int32 = 1) : Item
      Item.new ItemKind::PutridMass, count: count, blessing_known: true
    end

    # The kinds that spoil, a corpse left out.
    def spoiling : Array(ItemKind)
      Food::FACTS.select { |kind, facts| facts.spoils? && !kind.corpse? }.keys
    end

    it "is an item kind of its own, in the pack, that stacks" do
      expect(ItemKind::PutridMass.item_class).to eq Roguelike::ItemClass::Refuse
      expect(ItemKind::PutridMass.stacks?).to be_true
      expect(ItemKind::PutridMass.facts.weight).to eq 1
      expect(Food::PUTRID_MASS_VALUE).to eq 0
      expect(ItemKind.values.last).to eq ItemKind::PutridMass
    end

    it "takes every spoiling food through stale and rotten to putrid" do
      expect(spoiling).to contain ItemKind::Bread, ItemKind::FreshMeat, ItemKind::WolfLiver
      spoiling.each do |kind|
        facts = Food.facts kind
        keeps = facts.keeps
        expect(facts.freshness(keeps - 1)).to eq Freshness::Fresh
        expect(facts.freshness(keeps)).to eq Freshness::Stale
        expect(facts.freshness(keeps * 2 - 1)).to eq Freshness::Stale
        expect(facts.freshness(keeps * 2)).to eq Freshness::Rotten
        expect(facts.freshness(keeps * Food::PUTRID - 1)).to eq Freshness::Rotten
        expect(facts.freshness(keeps * Food::PUTRID)).to eq Freshness::Putrid
      end
    end

    it "never takes a food that keeps to putrid" do
      ration = food ItemKind::Ration
      10_000.times { ration.ripen }
      expect(ration.putrid?).to be_false
      expect(ration.freshness).to eq Freshness::Fresh
    end

    it "turns each spoiling food in the bag into putrid masses in the pack" do
      spoiling.each do |kind|
        keeps = Food.facts(kind).keeps
        game = hall [food(kind, 2, age: keeps * Food::PUTRID - 1)]
        waits game, 1

        expect(game.player.food_bag.empty?).to be_true
        expect(game.player.inventory.entries.map { |(_, item)| {item.kind, item.count} })
          .to eq [{ItemKind::PutridMass, 2}]
      end
    end

    it "stacks the masses with one already in the pack and says so" do
      keeps = Food.facts(ItemKind::Berries).keeps
      game = hall [food(ItemKind::Berries, 3, age: keeps * Food::PUTRID - 1)]
      game.player.inventory.add mass(2)
      game.enroll
      berries = game.player.food_bag.items.first.id
      held = game.player.inventory.entries.first[1].id
      seen = waits game, 1

      expect(game.player.inventory.entries.map { |(_, item)| {item.kind, item.count, item.id} })
        .to eq [{ItemKind::PutridMass, 5, held}]
      spoiled = seen.select(Event::FoodSpoiled).map(&.as(Event::FoodSpoiled))
      expect(spoiled.map { |event| {event.item, event.freshness, event.mass, event.fell} })
        .to eq [{berries, Freshness::Putrid, held, nil}]
      expect(game.log.lines).to contain "3 rotten handfuls of berries in your food bag have gone " \
                                        "putrid. They are now 3 putrid masses in your pack."
    end

    it "drops the mass at the character's feet when the pack is full" do
      keeps = Food.facts(ItemKind::Bread).keeps
      game = hall [food(ItemKind::Bread, age: keeps * Food::PUTRID - 1)]
      Roguelike::Inventory::LETTERS.each { game.player.inventory.add Item.new(ItemKind::Dagger) }
      game.enroll
      bread = game.player.food_bag.items.first.id
      seen = waits game, 1

      expect(game.player.food_bag.empty?).to be_true
      expect(game.here.map { |item| {item.kind, item.count, item.id} })
        .to eq [{ItemKind::PutridMass, 1, bread}]
      spoiled = seen.select(Event::FoodSpoiled).first.as(Event::FoodSpoiled)
      expect({spoiled.mass, spoiled.fell}).to eq({bread, true})
      expect(game.log.lines).to contain "A rotten loaf of bread in your food bag has gone putrid. " \
                                        "Your pack is full, so a putrid mass falls at your feet."
    end

    it "turns food on the floor into putrid masses on its square" do
      keeps = Food.facts(ItemKind::Mushroom).keeps
      game = hall
      game.floor.drop 5, 1, food(ItemKind::Mushroom, 2, age: keeps * Food::PUTRID - 1)
      game.enroll
      mushrooms = game.floor.items(5, 1).first.id
      seen = waits game, 1

      expect(game.floor.items(5, 1).map { |item| {item.kind, item.count, item.id} })
        .to eq [{ItemKind::PutridMass, 2, mushrooms}]
      expect(seen.any?(Event::CorpseRotted)).to be_false
    end

    it "is what an undead creature with flesh leaves" do
      expect(Game.remains_of(Kind::Zombie).map(&.kind)).to eq [ItemKind::PutridMass, ItemKind::Bones]

      game = hall
      zombie = Monster.new Kind::Zombie, 2, 1, "band-one"
      game.floor.place zombie
      game.enroll
      game.kill zombie
      expect(game.floor.items(2, 1).map(&.kind)).to eq [ItemKind::PutridMass, ItemKind::Bones]
    end

    it "turns rotten flesh in an old save into putrid masses when it loads" do
      game = hall [food(ItemKind::Ration)]
      game.player.food_bag.items << Item.new(ItemKind::RottenFlesh, count: 2, blessing_known: true)
      game.floor.drop 5, 1, Item.new(ItemKind::RottenFlesh, blessing_known: true)
      game.enroll
      flesh = game.player.food_bag.items.last.id
      lying = game.floor.items(5, 1).first.id

      read = Game.from_json game.to_json
      expect(read.player.food_bag.items.map(&.kind)).to eq [ItemKind::Ration]
      expect(read.player.inventory.entries.map { |(_, item)| {item.kind, item.count, item.id} })
        .to eq [{ItemKind::PutridMass, 2, flesh}]
      expect(read.floor.items(5, 1).map { |item| {item.kind, item.id} })
        .to eq [{ItemKind::PutridMass, lying}]
    end

    it "drops rotten flesh from an old save underfoot when the pack is full" do
      game = hall
      Roguelike::Inventory::LETTERS.each { game.player.inventory.add Item.new(ItemKind::Dagger) }
      game.player.food_bag.items << Item.new(ItemKind::RottenFlesh, blessing_known: true)
      game.enroll

      read = Game.from_json game.to_json
      expect(read.player.food_bag.empty?).to be_true
      expect(read.here.map(&.kind)).to eq [ItemKind::PutridMass]
    end

    it "is never eaten and never offered to eat" do
      game = hall hunger: STARVING
      game.player.inventory.add mass(3)
      game.enroll
      held = game.player.inventory.entries.first[1]

      expect(held.edible?).to be_false
      expect(held.food?).to be_false
      expect(game.edible).to be_empty
      expect(game.legal.any?(Action::Eat)).to be_false
      game.perform Action::Eat.new(held.id)
      expect(game.player.inventory.count('a')).to eq 3
      expect(game.turn).to eq 0
    end

    it "never spoils" do
      held = mass
      10_000.times { held.ripen }
      expect(held.freshness).to eq Freshness::Fresh
      expect(held.putrid?).to be_false
    end

    it "stacks under one letter with no cap" do
      game = hall
      100.times { game.player.inventory.add mass(100) }

      expect(game.player.inventory.size).to eq 1
      expect(game.player.inventory.count('a')).to eq 10_000
      expect(game.player.inventory.all('a').size).to eq 1
    end

    it "is named with its count and plural" do
      lore = hall.lore
      expect(lore.name(mass)).to eq "a putrid mass"
      expect(lore.name(mass(3))).to eq "3 putrid masses"
    end

    it "is picked up by hand into the pack" do
      game = hall
      game.floor.drop *HERE, mass
      game.enroll
      game.perform Action::PickUp.new

      expect(game.player.food_bag.empty?).to be_true
      expect(game.player.inventory.entries.map { |(_, item)| {item.kind, item.count} })
        .to eq [{ItemKind::PutridMass, 1}]
    end

    it "is picked up on a step only when it stacks with one carried" do
      game = hall
      game.floor.drop HERE[0] + 1, HERE[1], mass
      game.enroll
      game.perform Action::Move.new(Roguelike::Direction::East)
      expect(game.here.map(&.kind)).to eq [ItemKind::PutridMass]
      expect(game.player.inventory.empty?).to be_true

      game.player.inventory.add mass
      game.floor.drop HERE[0] + 2, HERE[1], mass(2)
      game.enroll
      game.perform Action::Move.new(Roguelike::Direction::East)
      expect(game.here).to be_empty
      expect(game.player.inventory.count('a')).to eq 3
    end

    it "shows in the observation with its class and count" do
      game = hall
      game.player.inventory.add mass(4)
      game.floor.drop 5, 1, mass(2)
      game.enroll
      seen = Roguelike::Observation.of game
      carried = seen.inventory.find! { |item| item.kind == ItemKind::PutridMass }
      lying = seen.items.find! { |item| item.kind == ItemKind::PutridMass }

      expect({carried.item_class, carried.count}).to eq({Roguelike::ItemClass::Refuse, 4})
      expect({lying.item_class, lying.count}).to eq({Roguelike::ItemClass::Refuse, 2})
      expect(carried.to_json).to contain %("item_class":"refuse")
      expect(carried.to_json).to contain %("kind":"putrid_mass")
    end
  end

  describe "a putrid mass on the floor" do
    def mass(count : Int32 = 1) : Item
      Item.new ItemKind::PutridMass, count: count, blessing_known: true
    end

    # The kinds and counts on square *x*, *y* of *ground*.
    def lying(ground : Floor, x : Int32, y : Int32) : Array({ItemKind, Int32})
      ground.items(x, y).map { |item| {item.kind, item.count} }
    end

    # Waits *turns* turns, one tick each. The character is kept fed and
    # watered, since a hungry one is slower and a wait would take more.
    def passes(game : Game, turns : Int32) : Array(Event)
      start = game.turn
      found = [] of Event
      turns.times do
        game.player.sustenance.hunger = 0
        game.player.sustenance.thirst = 0
        game.perform Action::Wait.new
        found.concat game.events
      end
      expect(game.turn).to eq start + turns
      found
    end

    it "vanishes after it has lain on the floor for its time" do
      game = hall
      game.floor.drop 5, 1, mass
      game.enroll
      passes game, Food::PUTRID_FADES - 1
      expect(lying game.floor, 5, 1).to eq [{ItemKind::PutridMass, 1}]

      seen = passes game, 1
      expect(game.floor.items(5, 1)).to be_empty
      expect(seen.any?(Event::CorpseRotted)).to be_false
    end

    it "never fades in the pack" do
      game = hall
      game.perform Action::Configure.new(Roguelike::Explore::Settings.parse "drop_rot=off")
      game.player.inventory.add mass(3)
      game.enroll
      passes game, Food::PUTRID_FADES * 2

      expect(game.player.inventory.count('a')).to eq 3
    end

    it "gives a mass dropped from the pack the full time" do
      game = hall
      game.perform Action::Configure.new(Roguelike::Explore::Settings.parse "drop_rot=off")
      game.floor.drop *HERE, mass
      game.enroll
      passes game, Food::PUTRID_FADES - 10
      game.perform Action::PickUp.new
      held = game.player.inventory.entries.first[1].id
      passes game, 20
      game.perform Action::Drop.new(held)
      passes game, Food::PUTRID_FADES - 2
      expect(lying game.floor, *HERE).to eq [{ItemKind::PutridMass, 1}]

      passes game, 1
      expect(game.here).to be_empty
    end

    it "fades the mass a corpse leaves" do
      game = hall
      game.floor.drop 5, 1, Game.remains_of(Kind::Wolf).first
      game.enroll
      passes game, Food::CORPSE_KEEPS * 2
      expect(lying game.floor, 5, 1).to eq [{ItemKind::PutridMass, 1}]

      passes game, Food::PUTRID_FADES - 1
      expect(lying game.floor, 5, 1).to eq [{ItemKind::PutridMass, 1}]
      passes game, 1
      expect(game.floor.items(5, 1)).to be_empty
    end

    it "fades a whole stack on one square together, timed from the last mass added" do
      game = hall
      game.floor.drop 5, 1, mass(3)
      game.enroll
      passes game, 400
      game.floor.drop 5, 1, mass(2)
      passes game, Food::PUTRID_FADES - 1
      expect(lying game.floor, 5, 1).to eq [{ItemKind::PutridMass, 5}]

      passes game, 1
      expect(game.floor.items(5, 1)).to be_empty
    end

    it "stays in the character's memory of a square they cannot see" do
      floor = Floor.parse "hall", ["#########", "#<.'..#.#", "#########"]
      Playing.daylight floor
      floor.drop 5, 1, mass
      player = Player.new floor.id, 2, 1
      game = Game.new World.new(SEED, {floor.id => floor}), player,
        lore: Lore.roll(Rng.new SEED)
      game.enroll
      game.look
      expect(game.knowledge[5, 1].try(&.shown).try &.kind).to eq ItemKind::PutridMass

      game.perform Action::Close.new(Roguelike::Direction::East)
      passes game, Food::PUTRID_FADES
      game.look
      expect(game.floor.items(5, 1)).to be_empty
      expect(game.knowledge[5, 1].try(&.shown).try &.kind).to eq ItemKind::PutridMass

      game.perform Action::Open.new(Roguelike::Direction::East)
      game.look
      expect(game.knowledge[5, 1].try &.shown).to be_nil
    end

    it "waits on a floor the character is not on, and fades once they return" do
      game = hall
      other = Floor.parse "other", HALL
      game.world.floors[other.id] = other
      other.drop 5, 1, mass
      game.enroll
      passes game, Food::PUTRID_FADES * 2
      expect(lying other, 5, 1).to eq [{ItemKind::PutridMass, 1}]

      game.player.floor = other.id
      passes game, Food::PUTRID_FADES - 1
      expect(lying other, 5, 1).to eq [{ItemKind::PutridMass, 1}]
      passes game, 1
      expect(other.items(5, 1)).to be_empty
    end

    it "loads from an old save with the full time ahead of it" do
      game = hall
      game.floor.drop 5, 1, mass(2)
      game.enroll
      passes game, 300
      written = game.to_json
      old = written.gsub(/,"lain":\d+/, "")
      expect(old).not_to eq written

      read = Game.from_json old
      passes read, Food::PUTRID_FADES - 1
      expect(lying read.floor, 5, 1).to eq [{ItemKind::PutridMass, 2}]
      passes read, 1
      expect(read.floor.items(5, 1)).to be_empty
    end

    it "keeps its time through a save" do
      game = hall
      game.floor.drop 5, 1, mass
      game.enroll
      passes game, 300

      read = Game.from_json game.to_json
      passes read, Food::PUTRID_FADES - 301
      expect(lying read.floor, 5, 1).to eq [{ItemKind::PutridMass, 1}]
      passes read, 1
      expect(read.floor.items(5, 1)).to be_empty
    end
  end

  describe "eating a corpse where it lies" do
    # The legal eat actions on *corpse*.
    def eats(game : Game, corpse : Item) : Bool
      game.legal.any? { |action| action.is_a?(Action::Eat) && action.item == corpse.id }
    end

    it "is offered only to a starving character" do
      {Kind::Rat, Kind::Orc}.each do |kind|
        game = hall hunger: STARVING - 1
        game.floor.drop *HERE, Game.remains_of(kind).first
        game.enroll
        corpse = game.here.first
        expect(game.edible).to be_empty
        expect(eats game, corpse).to be_false

        game.player.sustenance.hunger = STARVING
        expect(game.edible).to eq [corpse]
        expect(eats game, corpse).to be_true
      end
    end

    it "refuses a character who is not starving, and spends no turn" do
      game = hall hunger: STARVING - 1
      game.floor.drop *HERE, Game.remains_of(Kind::Rat).first
      game.enroll
      corpse = game.here.first
      verdict = game.perform Action::Eat.new(corpse.id)

      expect(verdict.refused?).to be_false
      refused = game.events.select(Event::Refused).map(&.as(Event::Refused))
      expect(refused.map(&.reason)).to eq [Event::Refused::Reason::NotStarving]
      expect(refused.first.item).to eq corpse.id
      expect(game.log.lines.last).to eq "You are not hungry enough to eat that where it lies."
      expect(game.here).to eq [corpse]
      expect(game.turn).to eq 0
    end

    it "leaves eating from the bag alone" do
      game = hall [food(ItemKind::Apple)], hunger: HUNGER
      id = game.player.food_bag.items.first.id
      expect(game.legal.any? { |action| action.is_a?(Action::Eat) && action.item == id }).to be_true
    end
  end

  describe "cannibalism" do
    # A starving character over an orc corpse, who is an orc themselves.
    #
    # No human creature spawns, so the spec makes the character an orc to
    # stand a corpse of their own species underfoot.
    def among_orcs : Game
      game = hall hunger: STARVING
      game.player.species = "orc"
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      game
    end

    it "makes every character human" do
      expect(hall.player.species).to eq Player::HUMAN
      expect(Player::HUMAN).to eq "human"
    end

    it "marks the eat row of a corpse of the character's own species" do
      expect(among_orcs.pick_up_rows.map(&.cannibal)).to eq [true]

      human = hall hunger: STARVING
      human.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      human.enroll
      expect(human.pick_up_rows.map(&.cannibal)).to eq [false]
    end

    it "makes a character who eats one of their own kind a cannibal for good" do
      game = among_orcs
      corpse = game.here.first
      expect(game.player.cannibal?).to be_false
      game.perform Action::Eat.new(corpse.id)

      expect(game.player.cannibal?).to be_true
      found = game.events.select(Event::Cannibal).map(&.as(Event::Cannibal))
      expect(found.map(&.item)).to eq [corpse.id]
      expect(game.log.lines).to contain "You have eaten the orc corpse, one of your own kind. " \
                                        "You are a cannibal now."
    end

    it "says so only the first time" do
      game = among_orcs
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      2.times { game.perform Action::Eat.new(game.here.first.id) }

      expect(game.player.cannibal?).to be_true
      expect(game.events.any?(Event::Cannibal)).to be_false
    end

    it "does not make a human who eats an orc a cannibal" do
      game = hall hunger: STARVING
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      game.perform Action::Eat.new(game.here.first.id)
      expect(game.player.cannibal?).to be_false
    end

    it "keeps the flag through a save, and writes none for a character who never ate one" do
      game = among_orcs
      game.perform Action::Eat.new(game.here.first.id)

      expect(Player.from_json(game.player.to_json).cannibal?).to be_true
      expect(hall.player.to_json).not_to contain "cannibal"
      expect(Player.from_json(hall.player.to_json).cannibal?).to be_false
    end
  end

  describe "the pick-up rows" do
    alias Way = Roguelike::Game::PickUpRow::Way

    # Each row of *game*'s pick-up menu as its way and whether it is open.
    def rows(game : Game) : Array({Way, Bool})
      game.pick_up_rows.map { |row| {row.way, row.open} }
    end

    it "cuts a fresh beast corpse and adds an eat row only while starving" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Wolf).first
      game.enroll
      expect(rows game).to eq [{Way::Cut, true}]

      game.player.sustenance.hunger = STARVING
      expect(rows game).to eq [{Way::Cut, true}, {Way::Eat, true}]
    end

    it "dims the eat row of a humanoid corpse until the character is starving" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      expect(rows game).to eq [{Way::Eat, false}]

      game.player.sustenance.hunger = STARVING
      expect(rows game).to eq [{Way::Eat, true}]
    end

    it "has only an eat row for a stale beast corpse" do
      game = hall
      game.floor.drop *HERE, Game.remains_of(Kind::Wolf).first
      game.enroll
      waits game, Food::CORPSE_KEEPS
      expect(rows game).to eq [{Way::Eat, false}]
    end

    it "takes anything that is not a corpse" do
      game = hall
      game.floor.drop *HERE, food(ItemKind::Apple)
      game.floor.drop *HERE, Game.remains_of(Kind::Orc).first
      game.enroll
      expect(rows game).to eq [{Way::Take, true}, {Way::Eat, false}]
    end
  end

  describe "meat and thirst" do
    # Eats one piece of meat *age* turns old in `#hall`, with *thirst* turns
    # of thirst debt. Answers how far the meal moved the debt, less the
    # turns it took.
    def meat_meal(age : Int32, thirst : Int32 = 1000, hunger : Int32 = HUNGER) : Int32
      game = hall [food(ItemKind::FreshMeat, age: age)], hunger: hunger
      game.player.sustenance.thirst = thirst
      game.perform Action::Eat.new(game.player.food_bag.items.first.id)
      raise "not eaten" unless game.events.any?(Event::Ate)

      game.player.sustenance.thirst - thirst - game.turn
    end

    def keeps : Int32
      Food.facts(ItemKind::FreshMeat).keeps
    end

    it "pays the fresh meat water off thirst" do
      expect(Sustenance::Tuning::MEAT_FRESH_WATER).to eq 90
      expect(meat_meal(0)).to eq(-90)
    end

    it "pays nothing for stale meat" do
      expect(Sustenance::Tuning::MEAT_STALE_WATER).to eq 0
      expect(meat_meal(keeps)).to eq 0
    end

    it "adds thirst for rotten meat" do
      expect(Sustenance::Tuning::MEAT_ROTTEN_WATER).to eq(-180)
      expect(meat_meal(keeps * 2)).to eq 180
    end

    it "pays a share for a piece only partly eaten" do
      satiety = Food.facts(ItemKind::FreshMeat).satiety
      expect(meat_meal(0, hunger: 100)).to eq(-(90 * 100 // satiety))
    end

    it "pays no further than no thirst" do
      expect(meat_meal(0, thirst: 0)).to eq 0
    end
  end

  describe "the pantry" do
    it "uses the rates the design gives, per 100,000 squares" do
      expect(Sustenance::Tuning::PANTRY).to eq({1..3 => 105, 4..7 => 10, 8..10 => 40})
    end

    it "stocks each band at its rate, in whole items rounded down" do
      expect(Food.stocked(10_000, 1)).to eq 10
      expect(Food.stocked(20_000, 3)).to eq 21
      expect(Food.stocked(30_000, 4)).to eq 3
      expect(Food.stocked(19_999, 7)).to eq 1
      expect(Food.stocked(10_000, 8)).to eq 4
      expect(Food.stocked(25_000, 10)).to eq 10
    end

    it "stocks one at least" do
      expect(Food.stocked(100, 1)).to eq 1
      expect(Food.stocked(5_000, 6)).to eq 1
    end

    it "puts the stocked count of food on dug floors of each band" do
      game = Game.dug Rng.new(SEED)
      {1, 5, 9}.each do |depth|
        ground = depth == 1 ? game.floor : game.dig(depth)
        open = 0
        ground.each { |_column, _row, tile| open += 1 if tile.terrain.floor? }
        found = 0
        ground.each_pile { |_column, _row, pile| found += pile.count(&.food?) }

        expect(found).to eq(Food.stocked(open, depth)), "floor #{depth}"
      end
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
