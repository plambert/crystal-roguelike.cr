require "../../spec_helper"

Spectator.describe "the food bag screen" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Options = Roguelike::Options
  alias Play = Roguelike::Ui::Play

  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  after_each { Options.current = nil }

  def food(kind : Kind, count : Int32 = 1, age : Int32 = 0) : Item
    Item.new kind, count: count, blessing_known: true, age: age
  end

  # A game in a lit hall with *bag* in the food bag and *pack* in the pack.
  def stocked(bag : Array(Item), pack : Array(Item) = [] of Item) : Roguelike::Game
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)
    player = Roguelike::Player.new floor.id, 1, 1
    player.sustenance.hunger = 2000
    bag.each { |item| player.food_bag.add item }
    pack.each { |item| player.inventory.add item }
    Roguelike::Game.new Roguelike::World.new(Playing::SEED, {floor.id => floor}), player
  end

  def traditional(game : Roguelike::Game) : Playing::Run
    Options.current = Options.new
    Playing.open game
  end

  def modern(game : Roguelike::Game) : Playing::Run
    options = Options.new
    options.control_scheme = Options::ControlScheme::Modern
    Options.current = options
    Playing.open game
  end

  it "opens on E with a page for each sort" do
    run = traditional stocked([food(Kind::Ration, 2), food(Kind::Apple)])
    run.press "E"

    expect(run.menu.title.to_s).to start_with Play::FOOD_BAG
    expect(run.menu.pages.map &.[0]).to eq %w[weight type value name freshness]
    expect(run.text).to contain "2 rations"
    expect(run.text).to contain "an apple"
  end

  it "keeps a row's letter on every page as the sort changes" do
    run = traditional stocked([food(Kind::Ration), food(Kind::Apple)])
    run.press "E"
    first = run.menu.entries.map &.key

    run.press "Right", "Right", "Right"
    expect(run.menu.page_name).to eq "name"
    expect(run.menu.entries.map &.key).to eq ['b', 'a']
    expect(first).to eq ['a', 'b']
  end

  it "eats one of a stack from the menu on its letter" do
    run = traditional stocked([food(Kind::Ration, 2)])
    run.press "E", "a", "e"

    expect(run.game.player.food_bag.items.first.count).to eq 1
    expect(run.turn).to eq 1
  end

  it "drops food from the menu on its letter" do
    run = traditional stocked([food(Kind::Apple)])
    run.press "E", "a", "d"

    expect(run.game.player.food_bag.empty?).to be_true
    expect(run.game.here.map &.kind).to eq [Kind::Apple]
  end

  it "says so when there is nothing to eat" do
    run = traditional stocked([] of Item)
    run.press "E"

    expect(run.menu.showing?).to be_false
    expect(run.game.log.lines.last).to contain "food bag is empty"
  end

  it "opens from the inventory and goes back to it" do
    run = traditional stocked([food(Kind::Nuts)], [Item.new(Kind::Dagger)])
    run.press "i"
    expect(run.menu.entries.map &.key).to contain Play::FOOD_BAG_KEY

    run.press Play::FOOD_BAG_KEY.to_s
    expect(run.menu.title.to_s).to start_with Play::FOOD_BAG

    run.press "Escape"
    expect(run.menu.title).to eq "Inventory"
  end

  it "lists a corpse underfoot and leaves cutting it to the pick-up key" do
    game = stocked([] of Item)
    game.floor.drop 1, 1, Roguelike::Game.remains_of(Roguelike::Kind::Wolf).first
    game.enroll
    run = traditional game
    run.press "E"
    expect(run.text).to contain "wolf corpse"

    run.press "a"
    expect(run.text).not_to contain "cut up"

    run.press "Escape", "Escape"
    expect(run.menu.showing?).to be_false
    run.press ","
    expect(run.game.player.food_bag.items.map &.kind).to eq [Kind::FreshMeat]
  end

  it "eats from the bag in the modern scheme, through the inventory" do
    run = modern stocked([food(Kind::Ration, 2)])
    run.press "i"
    expect(run.text).to contain "food bag"

    run.press "s", "f"
    expect(run.menu.title.to_s).to start_with Play::FOOD_BAG

    run.press "f", "f"
    expect(run.game.player.food_bag.items.first.count).to eq 1
  end

  it "goes back to the inventory from the bag in the modern scheme" do
    run = modern stocked([food(Kind::Ration)])
    run.press "i", "s", "f"
    run.press "Escape"

    expect(run.menu.showing?).to be_true
    expect(run.menu.title).to eq "Inventory"
  end

  describe "the eat key" do
    def keeps(kind : Kind) : Int32
      Roguelike::Food.facts(kind).keeps
    end

    it "eats the food that turns soonest on e, with no menu" do
      berries = food Kind::Berries, age: keeps(Kind::Berries) - 10
      run = traditional stocked([food(Kind::Ration), berries])
      run.press "e"

      expect(run.menu.showing?).to be_false
      expect(run.game.player.food_bag.items.map &.kind).to eq [Kind::Ration]
      expect(run.turn).to eq 1
    end

    it "eats the food that turns soonest on Ctrl+E in the modern scheme" do
      berries = food Kind::Berries, age: keeps(Kind::Berries) - 10
      run = modern stocked([food(Kind::Ration), berries])
      run.press "Ctrl+E"

      expect(run.menu.showing?).to be_false
      expect(run.game.player.food_bag.items.map &.kind).to eq [Kind::Ration]
      expect(run.turn).to eq 1
    end

    it "passes over rotten food while anything else is left" do
      rotten = food Kind::Berries, age: keeps(Kind::Berries) * 2
      run = traditional stocked([rotten, food(Kind::Ration)])
      run.press "e"

      expect(run.game.player.food_bag.items.map &.kind).to eq [Kind::Berries]
      expect(run.game.player.buffs.none? &.status.sick?).to be_true
    end

    it "asks before eating rotten food when nothing else is left" do
      rotten = food Kind::Berries, age: keeps(Kind::Berries) * 2
      run = traditional stocked([rotten])
      run.press "e"

      expect(run.text).to contain "Rotten food makes you sick."
      expect(run.turn).to eq 0

      run.press "n"
      expect(run.game.player.food_bag.size).to eq 1
      expect(run.turn).to eq 0

      run.press "e", "y"
      expect(run.game.player.food_bag.empty?).to be_true
      expect(run.turn).to eq 1
    end

    it "asks before eating rotten food in the modern scheme" do
      rotten = food Kind::Berries, age: keeps(Kind::Berries) * 2
      run = modern stocked([rotten])
      run.press "Ctrl+E"

      expect(run.text).to contain "Rotten food makes you sick."
      expect(run.turn).to eq 0
    end

    it "is refused when full, as before" do
      game = stocked([food(Kind::Apple)])
      game.player.sustenance.hunger = 0
      run = traditional game
      run.press "e"

      expect(run.said).to eq "You are too full to eat."
      expect(run.turn).to eq 0
      expect(run.game.player.food_bag.size).to eq 1
    end

    it "says so when the bag is empty" do
      run = traditional stocked([] of Item)
      run.press "e"

      expect(run.menu.showing?).to be_false
      expect(run.said).to contain "food bag is empty"
    end
  end
end
