require "../spec_helper"

Spectator.describe "the rules of automatic pickup" do
  alias Action = Roguelike::Action
  alias Appraisal = Roguelike::Appraisal
  alias Direction = Roguelike::Direction
  alias Facts = Roguelike::ItemFilter::Facts
  alias Floor = Roguelike::Floor
  alias Food = Roguelike::Food
  alias Game = Roguelike::Game
  alias Group = Roguelike::ItemFilter::Group
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Lore = Roguelike::Lore
  alias Outcome = Roguelike::Pickup::Outcome
  alias Pickup = Roguelike::Pickup
  alias Player = Roguelike::Player
  alias Rule = Roguelike::Pickup::Rule
  alias Rules = Roguelike::Pickup::Rules
  alias Size = Roguelike::Size
  alias Slot = Roguelike::Slot
  alias Test = Roguelike::ItemFilter::Test
  alias Trait = Roguelike::ItemFilter::Trait
  alias World = Roguelike::World

  HALL = ["######################",
          "#....................#",
          "#..<.................#",
          "#....................#",
          "######################"]

  # A run in a lit hall, carrying *pack*, with *lying* one step east.
  def game_with(lying : Array(Item), pack : Array(Item) = [] of Item) : Game
    floor = Playing.daylight Floor.parse("here", HALL.join('\n'))
    player = Player.new "here", *Game.entrance(floor)
    pack.each { |item| player.inventory.add item }
    lying.each { |item| floor.drop player.x + 1, player.y, item }
    game = Game.new World.new(Playing::SEED, {"here" => floor}), player, turn: 100
    game.enroll
    game.look
    game
  end

  def step(game : Game) : Nil
    game.perform Action::Move.new(Direction::East)
  end

  def carried(game : Game) : Array(ItemKind)
    found = [] of ItemKind
    game.player.inventory.each_item { |_letter, item| found << item.kind }
    found
  end

  def listed(made : Array(Rule) = [] of Rule, otherwise : Outcome = Outcome::Leave) : Rules
    Rules.new made, otherwise
  end

  def nothing : Rules
    listed
  end

  def wanting(trait : Trait, wanted : Bool = true) : Array(Test)
    [Test.new(trait, wanted)]
  end

  def facts(player : Player, lore : Lore = Lore.new) : Facts
    Facts.new player, lore
  end

  def bare : Player
    Player.new "here", 1, 1
  end

  # A player with *item* readied in *slot*.
  def holding(item : Item, slot : Slot) : Player
    player = bare
    letter = player.inventory.add(item).as(Char)
    player.equipment.put slot, letter
    player
  end

  describe "the default rules" do
    it "take gold" do
      game = game_with [Item.new(ItemKind::Gold, count: 12)]
      step game

      expect(game.player.gold).to eq 12
    end

    it "take food that has not rotted into the food bag" do
      game = game_with [Item.new(ItemKind::Ration)]
      step game

      expect(game.player.food_bag.size).to eq 1
      expect(game.here).to be_empty
    end

    it "leave rotten food" do
      kind = ItemKind::Berries
      game = game_with [Item.new(kind, age: Food.facts(kind).keeps * 2)]
      step game

      expect(game.here.map(&.kind)).to eq [kind]
    end

    it "take what could be more of a carried pile" do
      game = game_with [Item.new(ItemKind::Dart, count: 2)], [Item.new(ItemKind::Dart, count: 3)]
      step game

      expect(game.player.inventory.entries.first[1].count).to eq 5
    end

    it "leave what is not carried" do
      game = game_with [Item.new(ItemKind::Dart), Item.new(ItemKind::Dagger)]
      step game

      expect(carried game).to be_empty
    end

    it "leave what the character put down" do
      lying = Item.new ItemKind::Dart, count: 2
      lying.set_down
      game = game_with [lying], [Item.new(ItemKind::Dart, count: 3)]
      step game

      expect(game.here.size).to eq 1
    end

    it "are what a run has until it is configured" do
      expect(game_with([] of Item).pickup_rules).to eq Pickup.default
    end
  end

  describe "rules of the player's own" do
    it "leave gold when no rule takes it" do
      game = game_with [Item.new(ItemKind::Gold, count: 12)]
      game.perform Action::Configure.new(pickup: nothing)
      step game

      expect(game.player.gold).to eq 0
      expect(game.here.map(&.kind)).to eq [ItemKind::Gold]
    end

    it "take a whole sort of item" do
      game = game_with [Item.new(ItemKind::HealingPotion), Item.new(ItemKind::Dagger)]
      game.perform Action::Configure.new(pickup: listed([Rule.new(Outcome::Take, Group::Potion)]))
      step game

      expect(carried game).to eq [ItemKind::HealingPotion]
    end

    it "go by the first rule that matches" do
      cursed = Item.new ItemKind::HealingPotion, blessing: Roguelike::Blessing::Cursed, blessing_known: true
      game = game_with [cursed, Item.new(ItemKind::HasteScroll)]
      game.perform Action::Configure.new(pickup: listed(
        [Rule.new(Outcome::Leave, tests: wanting(Trait::KnownCursed))], Outcome::Take))
      step game
      step game

      expect(carried game).to eq [ItemKind::HasteScroll]
    end

    it "do not see a curse the character has not found out" do
      cursed = Item.new ItemKind::HealingPotion, blessing: Roguelike::Blessing::Cursed
      game = game_with [cursed]
      game.perform Action::Configure.new(pickup: listed(
        [Rule.new(Outcome::Leave, tests: wanting(Trait::KnownCursed))], Outcome::Take))
      step game

      expect(carried game).to eq [ItemKind::HealingPotion]
    end

    it "never take a corpse, whatever the rules say" do
      game = game_with [Item.new(ItemKind::Corpse, creature: Roguelike::Kind::Orc)]
      game.perform Action::Configure.new(pickup: listed(otherwise: Outcome::Take))
      step game

      expect(game.here.map(&.kind)).to eq [ItemKind::Corpse]
    end

    it "take no turn to set" do
      game = game_with [] of Item
      turn = game.turn
      game.perform Action::Configure.new(pickup: nothing)

      expect(game.turn).to eq turn
      expect(game.pickup_rules).to eq nothing
    end

    it "leave the explore settings alone" do
      game = game_with [] of Item
      settings = Roguelike::Explore::Settings.parse "reach=2"
      game.perform Action::Configure.new(settings)
      game.perform Action::Configure.new(pickup: nothing)

      expect(game.explore_settings).to eq settings
    end

    it "are refused when a rule asks one thing twice" do
      twice = Rule.new Outcome::Take, tests: [Test.new(Trait::Spoiled), Test.new(Trait::Spoiled, false)]
      game = game_with [] of Item

      expect(game.perform(Action::Configure.new(pickup: listed([twice]))).refused?).to be_true
      expect(game.pickup_rules).to eq Pickup.default
    end

    it "are refused when there are too many" do
      many = Rules.new Array.new(Roguelike::ItemFilter::LIMIT + 1) { Rule.new Outcome::Take }, Outcome::Leave
      game = game_with [] of Item

      expect(game.perform(Action::Configure.new(pickup: many)).refused?).to be_true
    end
  end

  describe "a save and a replay line" do
    it "hold the rules once they differ from the defaults" do
      game = game_with [] of Item
      game.perform Action::Configure.new(pickup: listed([Rule.new(Outcome::Take, Group::Potion)]))
      back = Game.from_json game.to_json

      expect(back.pickup_rules).to eq game.pickup_rules
      expect(back.fingerprint).to eq game.fingerprint
      expect(game.fingerprint).not_to eq game_with([] of Item).fingerprint
    end

    it "hold nothing for the defaults, so an older save loads and reads the same" do
      game = game_with [] of Item
      before = game.to_json
      game.perform Action::Configure.new(pickup: Pickup.default)

      expect(game.to_json).to eq before
      expect(JSON.parse(before).as_h.has_key? "pickup_rules").to be_false
      expect(Game.from_json(before).pickup_rules).to eq Pickup.default
    end

    it "write the action and read it back" do
      action = Action::Configure.new pickup: Pickup.default

      expect(Action.from_json(action.to_json).to_json).to eq action.to_json
      expect(Action.from_json(%({"t":"configure"})).as(Action::Configure).pickup).to be_nil
    end

    it "write a rule as its sort, its tests and its outcome" do
      rule = Rule.new Outcome::Take, Group::Food, [Test.new(Trait::Spoiled, false)]

      expect(rule.to_json).to eq %({"class":"food","when":["!spoiled"],"then":"take"})
      expect(Rule.from_json rule.to_json).to eq rule
      expect(Rule.new(Outcome::Leave).to_json).to eq %({"then":"leave"})
    end

    it "does not read a trait it does not know" do
      expect { Rule.from_json %({"when":["shiny"],"then":"take"}) }.to raise_error(JSON::ParseException)
    end
  end

  describe "a rule in words" do
    it "names the sort and each test" do
      expect(Rule.new(Outcome::Take).phrase).to eq "Anything"
      expect(Rule.new(Outcome::Take, Group::Gold).phrase).to eq "Any gold"
      expect(Rule.new(Outcome::Take, Group::Food, [Test.new(Trait::Spoiled, false)]).phrase)
        .to eq "Any food that has not spoiled"
      expect(Rule.new(Outcome::Leave, Group::Potion,
        [Test.new(Trait::KnownCursed), Test.new(Trait::Dropped, false)]).phrase)
        .to eq "Any potion you know is cursed and you did not put down"
    end
  end

  describe "what a rule can ask" do
    it "knows a kind only once the character has identified it" do
      lore = Lore.roll Roguelike::Rng.new(1_u64)
      potion = Item.new ItemKind::HealingPotion
      asked = Rule.new Outcome::Take, tests: wanting(Trait::Identified)

      expect(asked.matches? potion, facts(bare, lore)).to be_false
      lore.learn ItemKind::HealingPotion
      expect(asked.matches? potion, facts(bare, lore)).to be_true
      expect(asked.matches? Item.new(ItemKind::Dagger), facts(bare, lore)).to be_true
    end

    it "knows a blessing only when the item shows it" do
      hidden = Item.new ItemKind::Dagger, blessing: Roguelike::Blessing::Blessed
      shown = Item.new ItemKind::Dagger, blessing: Roguelike::Blessing::Blessed, blessing_known: true
      asked = Rule.new Outcome::Take, tests: wanting(Trait::KnownBlessed)

      expect(asked.matches? hidden, facts(bare)).to be_false
      expect(asked.matches? shown, facts(bare)).to be_true
    end

    it "knows the quiver's own ammunition, worn or not" do
      player = holding Item.new(ItemKind::Arrow, count: 5), Slot::Quiver
      bent = Item.new ItemKind::Arrow, condition: Roguelike::Condition::Damaged
      asked = Rule.new Outcome::Take, tests: wanting(Trait::Quiver)

      expect(asked.matches? bent, facts(player)).to be_true
      expect(asked.matches? Item.new(ItemKind::Stone), facts(player)).to be_false
    end
  end

  describe "better than what is in use" do
    let(lore) { Lore.new }

    it "is a weapon that does more in a turn than the one in the hand" do
      player = holding Item.new(ItemKind::Dagger), Slot::Melee

      expect(Appraisal.better? Item.new(ItemKind::Dagger, 2), player, lore).to be_true
      expect(Appraisal.better? Item.new(ItemKind::Dagger), player, lore).to be_false
      expect(Appraisal.better? Item.new(ItemKind::Dagger, -1), player, lore).to be_false
    end

    it "is any weapon that beats bare hands when the hand is empty" do
      expect(Appraisal.better? Item.new(ItemKind::LongSword), bare, lore).to be_true
    end

    it "is armor that takes more off an attack than the piece in its slot" do
      player = holding Item.new(ItemKind::LeatherArmor), Slot::Body

      expect(Appraisal.better? Item.new(ItemKind::ChainMail), player, lore).to be_true
      expect(Appraisal.better? Item.new(ItemKind::PaddedJacket), player, lore).to be_false
      expect(Appraisal.better? Item.new(ItemKind::Cap), player, lore).to be_true
    end

    it "is never armor that does not fit" do
      small = Item.new ItemKind::ChainMail, size: Size::Small

      expect(Appraisal.better? small, bare, lore).to be_false
    end

    it "counts what a shield of the wrong size costs" do
      player = holding Item.new(ItemKind::Shield), Slot::Shield
      fitting = Item.new ItemKind::Shield, 1
      small = Item.new ItemKind::Shield, 1, size: Size::Small

      expect(Appraisal.better? fitting, player, lore).to be_true
      expect(Appraisal.better? small, player, lore).to be_false
    end

    it "is never a thing known to be cursed" do
      cursed = Item.new ItemKind::LongSword, 3, blessing: Roguelike::Blessing::Cursed, blessing_known: true

      expect(Appraisal.better? cursed, bare, lore).to be_false
    end

    it "is not known for anything else" do
      expect(Appraisal.better? Item.new(ItemKind::Arrow), bare, lore).to be_nil
      expect(Appraisal.better? Item.new(ItemKind::Bow), bare, lore).to be_nil
    end

    it "matches no rule when it is not known, whichever way the rule asks" do
      arrow = Item.new ItemKind::Arrow

      expect(Rule.new(Outcome::Take, tests: wanting(Trait::Better)).matches? arrow, facts(bare)).to be_false
      expect(Rule.new(Outcome::Take, tests: wanting(Trait::Better, false)).matches? arrow, facts(bare)).to be_false
    end

    it "takes a better weapon off the floor under a rule that asks for one" do
      game = game_with [Item.new(ItemKind::LongSword), Item.new(ItemKind::Arrow)]
      game.perform Action::Configure.new(pickup: listed([Rule.new(Outcome::Take, tests: wanting(Trait::Better))]))
      step game

      expect(carried game).to eq [ItemKind::LongSword]
    end
  end
end
