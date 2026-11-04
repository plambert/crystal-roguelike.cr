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

  describe "stages" do
    it "says thirst sets in, and starts its status" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::THIRSTY - 1

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
      sustenance(game).hunger = Sustenance::FAMISHED - 1

      events = wait game

      expect(game.log.lines).to contain "You are famished."
      expect(events.compact_map(&.as?(Event::StatusEnd)).map(&.status))
        .to eq [Event::Status::Hungry]
      expect(events.compact_map(&.as?(Event::StatusStart)).map(&.status))
        .to eq [Event::Status::Famished]
    end

    it "says the skin ran dry" do
      game = bare
      sustenance(game).water = 0

      wait game

      expect(game.log.lines).to contain "Your waterskin is empty."
    end

    it "writes nothing for a stage a loaded run is already in" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::PARCHED + 5
      again = Game.from_json game.to_json

      wait again

      expect(again.log.lines).not_to contain "You are parched."
    end
  end

  describe "debuffs" do
    it "takes one off to hit while parched, and says the stat moved" do
      game = bare
      before = game.player.to_hit
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::PARCHED - 1

      events = wait game

      expect(game.player.to_hit).to eq before - 1
      changed = events.compact_map(&.as?(Event::StatChanged)).find(&.stat.==("to_hit"))
      expect(changed.try &.to).to eq before - 1
    end

    it "takes one off to hit and one off damage while famished" do
      game = bare
      before = game.player.damage.to_s
      sustenance(game).hunger = Sustenance::FAMISHED

      expect(game.player.to_hit).to eq(-1)
      expect(game.player.damage.to_s).not_to eq before
    end

    it "takes ten off pace while dehydrated, and ten more while starving" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::DEHYDRATED

      expect(game.player.speed).to eq 90

      sustenance(game).hunger = Sustenance::STARVING
      expect(game.player.speed).to eq 80
    end

    it "replaces the earlier debuff with the later one" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::DEHYDRATED

      expect(game.player.to_hit).to eq 0
      expect(game.player.regeneration).to eq Roguelike::Advancement::REGENERATION
    end

    it "doubles the turns a hit point takes while thirsty" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::THIRSTY

      expect(game.player.regeneration).to eq Roguelike::Advancement::REGENERATION * 2
    end

    it "stops regeneration and wastes a hit point every fifty turns when dying of thirst" do
      game = bare
      game.player.hurt 10
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::DYING
      before = game.player.hit_points

      wait game, Sustenance::DYING_EVERY

      expect(game.player.hit_points).to eq before - 1
    end

    it "wastes a hit point every hundred turns when starving" do
      game = bare
      sustenance(game).hunger = Sustenance::STARVING
      before = game.player.hit_points

      wait game, Sustenance::STARVING_EVERY

      expect(game.player.hit_points).to eq before - 1
    end
  end

  describe "death" do
    it "ends the run when thirst reaches its end" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::DRIED - 1

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
      sustenance(game).hunger = Sustenance::STARVED - 1

      wait game

      expect(game.perished).to eq Sustenance::Death::Hunger
      expect(Roguelike::Ui::Placards.ending(game).first).to eq "You starved to death."
    end

    it "ends the run when wasting takes the last hit point" do
      game = bare
      game.player.hurt game.player.hit_points - 1
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::DYING

      wait game, Sustenance::DYING_EVERY

      expect(game.over?).to be_true
      expect(game.perished).to eq Sustenance::Death::Thirst
    end
  end

  describe "drinking from the skin" do
    it "quenches, uses one unit and takes a turn" do
      game = bare
      sustenance(game).water = 4
      sustenance(game).thirst = Sustenance::THIRSTY + 3
      game.perform Action::Wait.new
      turn = game.turn

      verdict = game.perform Action::Drink.new

      expect(verdict.refused?).to be_false
      expect(game.turn).to eq turn + 1
      expect(sustenance(game).water).to eq 3
      expect(game.log.last?).to eq "You drink from your waterskin."
      drank = game.events.compact_map(&.as?(Event::Drank)).first
      expect({drank.source, drank.units}).to eq({"skin", 1})
      expect(game.events.compact_map(&.as?(Event::StatusEnd)).map(&.status))
        .to eq [Event::Status::Thirsty]
    end

    it "is refused when not thirsty and uses nothing" do
      game = bare
      turn = game.turn

      verdict = game.perform Action::Drink.new

      expect(verdict.refused?).to be_true
      expect(game.turn).to eq turn
      expect(sustenance(game).water).to eq Sustenance::WATER_MAX
      expect(game.log.last?).to eq "You are not thirsty."
    end

    it "is refused from an empty skin" do
      game = bare
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::THIRSTY

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
    it "drinks when thirst sets in and walks on" do
      game = bare MEETING
      sustenance(game).water = 2
      sustenance(game).thirst = Sustenance::THIRSTY - 1

      went = game.explore

      expect(game.log.lines).to contain "You are thirsty."
      expect(game.log.lines).to contain "You drink from your waterskin."
      expect(went.halt).not_to eq Halt::Thirsty
      expect(went.halt).not_to eq Halt::Told
      expect(sustenance(game).water).to eq 1
    end

    it "stops for thirst with drinking off" do
      game = bare MEETING
      game.perform Action::Configure.new(Settings.parse "drink=off")
      sustenance(game).water = 2
      sustenance(game).thirst = Sustenance::THIRSTY - 1

      went = game.explore

      expect(went.halt).to eq Halt::Thirsty
      expect(game.log.last?).to eq "You are thirsty."
      expect(sustenance(game).water).to eq 2
    end

    it "walks on when the skin runs dry" do
      game = bare MEETING
      sustenance(game).water = 0

      went = game.explore

      expect(game.log.lines).to contain "Your waterskin is empty."
      expect(went.halt).not_to eq Halt::Told
    end

    it "stops for thirst with an empty skin" do
      game = bare MEETING
      sustenance(game).water = 0
      sustenance(game).thirst = Sustenance::THIRSTY - 1

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

    it "eats when hunger sets in and walks on" do
      game = fed Sustenance::HUNGRY - 1, [food(ItemKind::Bread)]

      went = game.explore

      expect(game.log.lines).to contain "You are getting hungry."
      expect(game.log.lines.any? &.starts_with?("You eat")).to be_true
      expect(went.halt).not_to eq Halt::Hungry
      expect(went.halt).not_to eq Halt::Told
      expect(game.player.food_bag.empty?).to be_true
      expect(sustenance(game).hunger_stage).to be < Sustenance::HungerStage::Hungry
    end

    it "stops for hunger with eating off" do
      game = fed Sustenance::HUNGRY - 1, [food(ItemKind::Bread)]
      game.perform Action::Configure.new(Settings.parse "eat=off")

      went = game.explore

      expect(went.halt).to eq Halt::Hungry
      expect(game.log.last?).to eq "You are getting hungry."
      expect(game.player.food_bag.size).to eq 1
    end

    it "eats nothing with eating off" do
      game = fed Sustenance::FAMISHED, [food(ItemKind::Bread)]
      game.perform Action::Configure.new(Settings.parse "eat=off")

      expect(eaten(game, 3)).to be_empty
    end

    it "eats stale food first, the soonest to turn first, and rations last" do
      ration = food ItemKind::Ration
      bread = food ItemKind::Bread
      berries = food ItemKind::Berries
      stale_apple = food ItemKind::Apple, keeps(ItemKind::Apple)
      stale_berries = food ItemKind::Berries, keeps(ItemKind::Berries) + 100
      order = [stale_berries, stale_apple, berries, bread, ration]
      game = fed Sustenance::STARVING - 1, [ration, bread, berries, stale_apple, stale_berries]

      expect(order.map(&.id).reject(&.zero?).uniq!.size).to eq 5
      expect(eaten(game, 5)).to eq order.map(&.id)
    end

    it "leaves rotten food alone short of starving" do
      game = fed Sustenance::FAMISHED, [food(ItemKind::Apple, keeps(ItemKind::Apple) * 2)]

      expect(eaten(game, 3)).to be_empty
      expect(game.player.food_bag.size).to eq 1
    end

    it "eats rotten food while starving, once nothing else is left" do
      rotten = food ItemKind::Apple, keeps(ItemKind::Apple) * 2
      ration = food ItemKind::Ration
      game = fed Sustenance::STARVING + 1500, [rotten, ration]
      expect(rotten.id).not_to eq ration.id

      expect(eaten(game, 2)).to eq [ration.id, rotten.id]
    end

    it "walks on with an empty bag and says nothing new" do
      game = fed Sustenance::HUNGRY - 1

      went = game.explore

      expect(went.halt).not_to eq Halt::Hungry
      expect(went.halt).not_to eq Halt::Told
      expect(game.log.lines.count &.==("You are getting hungry.")).to eq 1
      expect(game.log.lines.any? &.starts_with?("You eat")).to be_false
    end

    it "never eats a corpse underfoot" do
      game = fed Sustenance::FAMISHED
      corpse = Game.remains_of(Roguelike::Kind::Rat).first
      game.floor.drop game.player.x, game.player.y, corpse
      game.enroll

      expect(eaten(game, 1)).to be_empty
    end
  end

  describe "a save" do
    it "keeps hunger, thirst and the skin" do
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
