require "../spec_helper"

Spectator.describe "hunger and thirst" do
  alias Action = Roguelike::Action
  alias Event = Roguelike::Event
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Sustenance = Roguelike::Sustenance
  alias Settings = Roguelike::Explore::Settings

  SEED = 20261031_u64

  HALL = ["######################",
          "#....................#",
          "#..<.................#",
          "#....................#",
          "######################"]

  # A corridor that runs east out of sight, so an explore has far to go.
  MEETING = [
    "#########################",
    "#.......................#",
    "########.################",
    "########.################",
    "########<################",
    "#########################",
  ]

  def bare(lines : Array(String) = HALL) : Game
    floor = Roguelike::Floor.parse "here", lines
    floor.ambient = 1
    player = Roguelike::Player.new "here", *Game.entrance(floor), hit_points: 40

    Game.new Roguelike::World.new(SEED, {"here" => floor}), player
  end

  def sustenance(game : Game) : Sustenance
    game.player.sustenance
  end

  # Waits *turns* turns. Answers every event they recorded.
  def wait(game : Game, turns : Int32 = 1) : Array(Event)
    found = [] of Event
    turns.times do
      break if game.over?

      game.perform Action::Wait.new
      found.concat game.events
    end
    found
  end

  # Waits until *turns* turns have passed. A slow character's wait takes
  # more than one.
  def pass(game : Game, turns : Int32) : Nil
    last = game.turn + turns
    while game.turn < last && !game.over?
      game.perform Action::Wait.new
    end
  end

  describe "stages" do
    it "says thirst sets in, and starts its status" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST - 1

      events = wait game

      expect(game.log.lines).to contain "You are thirsty."
      staged = events.compact_map(&.as?(Event::Thirst)).first
      expect(staged.stage).to eq Sustenance::ThirstStage::Thirsty
      expect(staged.from).to eq Sustenance::ThirstStage::Fine
      expect(events.compact_map(&.as?(Event::StatusStart)).map(&.status))
        .to eq [Event::Status::Thirsty]
      expect(game.player.lasting.map(&.status)).to eq [Event::Status::Thirsty]
    end

    it "ends the old status as the next stage starts" do
      game = bare
      sustenance(game).hunger = Sustenance::Tuning::HUNGER_SERIOUS - 1

      events = wait game

      expect(game.log.lines).to contain "You are famished."
      expect(events.compact_map(&.as?(Event::StatusEnd)).map(&.status))
        .to eq [Event::Status::Hungry]
      expect(events.compact_map(&.as?(Event::StatusStart)).map(&.status))
        .to eq [Event::Status::Famished]
    end

    it "grows thirsty with water in the skin, because nothing drinks it unasked" do
      game = bare
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST - 1

      wait game

      expect(game.log.lines).to contain "You are thirsty."
      expect(sustenance(game).water).to eq Sustenance::Tuning::SKIN_UNITS
    end

    it "writes an event and no line as hunger reaches its first effect" do
      game = bare
      sustenance(game).hunger = Sustenance::Tuning::HUNGER_FIRST - 1

      events = wait game

      staged = events.compact_map(&.as?(Event::Hunger)).first
      expect(staged.stage).to eq Sustenance::HungerStage::Fed
      expect(game.log.lines).to be_empty
      expect(game.player.lasting).to be_empty
    end

    it "writes nothing for a stage a loaded run is already in" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::Tuning::THIRST_SERIOUS + 5
      again = Game.from_json game.to_json

      wait again

      expect(again.log.lines).not_to contain "You are parched."
    end
  end

  describe "debuffs" do
    it "takes pace off as thirst sets in, and says the stat moved" do
      game = bare
      before = game.player.speed
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST - 1

      events = wait game

      expect(game.player.speed).to eq before - 6
      changed = events.compact_map(&.as?(Event::StatChanged)).find(&.stat.==("pace"))
      expect(changed.try &.to).to eq before - 6
    end

    it "takes to hit and damage off through the penalty and the worn attributes" do
      game = bare
      before = game.player.damage.to_s
      sustenance(game).hunger = Sustenance::Tuning::HUNGER_SEVERE

      expect(sustenance(game).to_hit_penalty).to eq 2
      expect(game.player.worn_attributes.dexterity).to eq 6
      expect(game.player.to_hit).to eq(-4)
      expect(game.player.damage.to_s).not_to eq before
      expect(game.player.attributes).to eq Roguelike::Attributes.new
    end

    it "slows by severity, and by the sum of hunger and thirst up to the cap" do
      game = bare
      sustenance(game).thirst = Sustenance::Tuning::THIRST_SEVERE

      expect(game.player.speed).to eq 100 - 39

      sustenance(game).hunger = Sustenance::Tuning::HUNGER_SEVERE
      expect(game.player.speed).to eq 100 - Sustenance::Tuning::PACE_LOSS
    end

    it "stretches the turns a hit point takes by severity" do
      game = bare
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST

      expect(game.player.regeneration).to eq (Roguelike::Advancement::REGENERATION * 1.4).to_i
    end

    it "stops regeneration and wastes hit points once thirst passes the wasting point" do
      game = bare
      game.player.hurt 10
      sustenance(game).thirst = Sustenance::THIRST_DYING
      before = game.player.hit_points

      pass game, Sustenance::Tuning::WASTE_FIRST

      expect(game.player.hit_points).to eq before - 1
    end

    it "wastes hit points when hunger and thirst together pass the wasting point" do
      game = bare
      sustenance(game).hunger = Sustenance::Tuning::HUNGER_SEVERE
      sustenance(game).thirst = Sustenance::Tuning::THIRST_SERIOUS
      before = game.player.hit_points
      every = sustenance(game).waste_every || 0
      expect(every).to be < Sustenance::Tuning::WASTE_FIRST

      pass game, every + 1

      expect(game.player.hit_points).to eq before - 1
    end
  end

  describe "death" do
    it "ends the run when thirst reaches its end" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::Tuning::THIRST_DEATH - 1

      events = wait game

      expect(game.outcome).to eq Roguelike::Outcome::Died
      expect(game.perished).to eq Sustenance::Death::Thirst
      expect(game.log.last?).to eq "You die of thirst..."
      over = events.compact_map(&.as?(Event::Over)).first
      expect(over.cause).to eq Sustenance::Death::Thirst
      expect(Roguelike::Ui::Placards.ending(game).first).to eq "You died of thirst."
    end

    it "ends the run when hunger reaches its end" do
      game = bare
      sustenance(game).hunger = Sustenance::Tuning::HUNGER_DEATH - 1

      wait game

      expect(game.perished).to eq Sustenance::Death::Hunger
      expect(Roguelike::Ui::Placards.ending(game).first).to eq "You starved to death."
    end

    it "ends the run when wasting takes the last hit point" do
      game = bare
      game.player.hurt game.player.hit_points - 1
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::THIRST_DYING

      pass game, Sustenance::Tuning::WASTE_FIRST

      expect(game.over?).to be_true
      expect(game.perished).to eq Sustenance::Death::Thirst
    end
  end

  describe "drinking from the skin" do
    it "pays a unit of debt, uses one unit and takes a turn" do
      game = bare
      sustenance(game).water = 4
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST + 3
      game.perform Action::Wait.new
      turn = game.turn

      verdict = game.perform Action::Drink.new

      expect(verdict.refused?).to be_false
      expect(game.turn).to eq turn + 1
      expect(sustenance(game).water).to eq 3
      expect(game.log.last?).to eq "You drink from your waterskin."
      drank = game.events.compact_map(&.as?(Event::Drank)).first
      expect({drank.source, drank.units, drank.paid}).to eq({"skin", 1, Sustenance::Tuning::UNIT_TURNS})
      expect(game.events.compact_map(&.as?(Event::StatusEnd)).map(&.status))
        .to eq [Event::Status::Thirsty]
    end

    it "is refused when not thirsty and uses nothing" do
      game = bare
      turn = game.turn

      verdict = game.perform Action::Drink.new

      expect(verdict.refused?).to be_true
      expect(game.turn).to eq turn
      expect(sustenance(game).water).to eq Sustenance::Tuning::SKIN_UNITS
      expect(game.log.last?).to eq "You are not thirsty."
    end

    it "is refused from an empty skin" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST

      expect(game.perform(Action::Drink.new).refused?).to be_true
      expect(game.log.last?).to eq "Your waterskin is empty."
    end

    it "is legal only while thirsty with water in the skin" do
      game = bare
      expect(game.legal.map &.class).not_to contain Action::Drink

      sustenance(game).thirst = 10
      expect(game.legal.map &.class).to contain Action::Drink

      sustenance(game).water = 0
      expect(game.legal.map &.class).not_to contain Action::Drink
    end
  end

  describe "exploring" do
    it "drinks before thirst sets in and walks on" do
      game = bare MEETING
      sustenance(game).water = 2
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST - 1

      went = game.explore

      expect(game.log.lines).not_to contain "You are thirsty."
      expect(game.log.lines).to contain "You drink from your waterskin."
      expect(went.halt).not_to eq Halt::Thirsty
      expect(went.halt).not_to eq Halt::Told
      expect(sustenance(game).water).to eq 1
    end

    it "leaves the skin alone while a unit would not pay off whole" do
      game = bare MEETING
      sustenance(game).thirst = Sustenance::Tuning::UNIT_TURNS - 1

      game.perform Action::Explore.new

      expect(sustenance(game).water).to eq Sustenance::Tuning::SKIN_UNITS
    end

    it "stops for thirst with drinking off" do
      game = bare MEETING
      game.perform Action::Configure.new(Settings.parse "drink=off")
      sustenance(game).water = 2
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST - 1

      went = game.explore

      expect(went.halt).to eq Halt::Thirsty
      expect(game.log.last?).to eq "You are thirsty."
      expect(sustenance(game).water).to eq 2
    end

    it "says nothing as the skin runs dry" do
      game = bare MEETING
      sustenance(game).water = 1
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST - 1

      game.explore

      expect(sustenance(game).water).to eq 0
      expect(game.log.lines).not_to contain "Your waterskin is empty."
    end

    it "stops for thirst with an empty skin" do
      game = bare MEETING
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::Tuning::THIRST_FIRST - 1

      expect(game.explore.halt).to eq Halt::Thirsty
    end
  end

  describe "exploring with food" do
    # A game in `MEETING` with *bag* in the food bag, every item given an
    # id, and a character *hunger* turns from their last meal.
    def fed(hunger : Int32, bag : Array(Item) = [] of Item) : Game
      game = bare MEETING
      bag.each { |item| game.player.food_bag.add item }
      game.enroll
      sustenance(game).hunger = hunger
      game
    end

    def food(kind : ItemKind, age : Int32 = 0) : Item
      Item.new kind, blessing_known: true, age: age
    end

    def keeps(kind : ItemKind) : Int32
      Roguelike::Food.facts(kind).keeps
    end

    # Takes *steps* steps of an explore. Answers the ids of what they ate,
    # in order.
    def eaten(game : Game, steps : Int32) : Array(Int32)
      found = [] of Int32
      steps.times do
        game.perform Action::Explore.new
        game.events.each { |event| found << event.item if event.is_a?(Event::Ate) }
      end
      found
    end

    it "eats as hunger reaches its first effect and walks on" do
      game = fed Sustenance::Tuning::HUNGER_FIRST - 1, [food(ItemKind::Bread)]

      went = game.explore

      expect(game.log.lines).not_to contain "You are getting hungry."
      expect(game.log.lines.any? &.starts_with?("You eat")).to be_true
      expect(went.halt).not_to eq Halt::Hungry
      expect(went.halt).not_to eq Halt::Told
      expect(game.player.food_bag.empty?).to be_true
      expect(sustenance(game).hunger_stage).to eq Sustenance::HungerStage::Satiated
    end

    it "eats nothing short of hunger's first effect" do
      game = fed Sustenance::Tuning::HUNGER_FIRST - 10, [food(ItemKind::Bread)]

      expect(eaten(game, 3)).to be_empty
    end

    it "stops for hunger with eating off" do
      game = fed Sustenance::Tuning::HUNGER_HUNGRY - 1, [food(ItemKind::Bread)]
      game.perform Action::Configure.new(Settings.parse "eat=off")

      went = game.explore

      expect(went.halt).to eq Halt::Hungry
      expect(game.log.last?).to eq "You are getting hungry."
      expect(game.player.food_bag.size).to eq 1
    end

    it "eats nothing with eating off" do
      game = fed Sustenance::Tuning::HUNGER_SERIOUS, [food(ItemKind::Bread)]
      game.perform Action::Configure.new(Settings.parse "eat=off")

      expect(eaten(game, 3)).to be_empty
    end

    it "never eats a putrid mass, starving or not" do
      game = fed Sustenance::Tuning::HUNGER_SEVERE
      game.player.inventory.add Item.new(ItemKind::PutridMass, count: 3, blessing_known: true)
      game.enroll

      expect(eaten(game, 3)).to be_empty
      expect(game.legal.any?(Action::Eat)).to be_false
      expect(game.player.inventory.items.sum { |(_, item)| item.count }).to eq 3
    end

    it "eats stale food first, the soonest to turn first, and rations last" do
      ration = food ItemKind::Ration
      bread = food ItemKind::Bread
      berries = food ItemKind::Berries
      stale_apple = food ItemKind::Apple, keeps(ItemKind::Apple)
      stale_berries = food ItemKind::Berries, keeps(ItemKind::Berries) + 100
      order = [stale_berries, stale_apple, berries, bread, ration]
      game = fed Sustenance::Tuning::HUNGER_SEVERE - 1, [ration, bread, berries, stale_apple, stale_berries]

      expect(order.map(&.id).reject(&.zero?).uniq!.size).to eq 5
      expect(eaten(game, 5)).to eq order.map(&.id)
    end

    it "leaves rotten food alone short of starving" do
      game = fed Sustenance::Tuning::HUNGER_SERIOUS, [food(ItemKind::Apple, keeps(ItemKind::Apple) * 2)]

      expect(eaten(game, 3)).to be_empty
      expect(game.player.food_bag.size).to eq 1
    end

    it "eats rotten food while starving, once nothing else is left" do
      rotten = food ItemKind::Apple, keeps(ItemKind::Apple) * 2
      ration = food ItemKind::Ration
      game = fed Sustenance::Tuning::HUNGER_SEVERE + 1500, [rotten, ration]
      expect(rotten.id).not_to eq ration.id

      expect(eaten(game, 2)).to eq [ration.id, rotten.id]
    end

    it "walks on with an empty bag and says nothing new" do
      game = fed Sustenance::Tuning::HUNGER_HUNGRY - 1

      went = game.explore

      expect(went.halt).not_to eq Halt::Hungry
      expect(went.halt).not_to eq Halt::Told
      expect(game.log.lines.count &.==("You are getting hungry.")).to eq 1
      expect(game.log.lines.any? &.starts_with?("You eat")).to be_false
    end

    it "never eats a corpse underfoot" do
      game = fed Sustenance::Tuning::HUNGER_SERIOUS
      corpse = Game.remains_of(Roguelike::Kind::Rat).first
      game.floor.drop game.player.x, game.player.y, corpse
      game.enroll

      expect(eaten(game, 1)).to be_empty
    end
  end

  describe "a save" do
    it "keeps the hunger and thirst debts and the skin" do
      game = bare
      sustenance(game).hunger = 1234
      sustenance(game).thirst = 56
      sustenance(game).water = 0

      again = Game.from_json game.to_json

      expect({sustenance(again).hunger, sustenance(again).thirst, sustenance(again).water})
        .to eq({1234, 56, 0})
    end
  end
end
