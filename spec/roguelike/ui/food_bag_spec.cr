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

  it "opens on e with a page for each sort" do
    run = traditional stocked([food(Kind::Ration, 2), food(Kind::Apple)])
    run.press "e"

    expect(run.menu.title.to_s).to start_with Play::FOOD_BAG
    expect(run.menu.pages.map &.[0]).to eq %w[weight type value name freshness]
    expect(run.text).to contain "2 rations"
    expect(run.text).to contain "an apple"
  end

  it "keeps a row's letter on every page as the sort changes" do
    run = traditional stocked([food(Kind::Ration), food(Kind::Apple)])
    run.press "e"
    first = run.menu.entries.map &.key

    run.press "Right", "Right", "Right"
    expect(run.menu.page_name).to eq "name"
    expect(run.menu.entries.map &.key).to eq ['b', 'a']
    expect(first).to eq ['a', 'b']
  end

  it "eats one of a stack from the menu on its letter" do
    run = traditional stocked([food(Kind::Ration, 2)])
    run.press "e", "a", "e"

    expect(run.game.player.food_bag.items.first.count).to eq 1
    expect(run.turn).to eq 1
  end

  it "drops food from the menu on its letter" do
    run = traditional stocked([food(Kind::Apple)])
    run.press "e", "a", "d"

    expect(run.game.player.food_bag.empty?).to be_true
    expect(run.game.here.map &.kind).to eq [Kind::Apple]
  end

  it "says so when there is nothing to eat" do
    run = traditional stocked([] of Item)
    run.press "e"

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

  it "lists a corpse underfoot and cuts it up" do
    game = stocked([] of Item)
    game.floor.drop 1, 1, Roguelike::Game.remains_of(Roguelike::Kind::Orc).first
    game.enroll
    run = traditional game
    run.press "e"
    expect(run.text).to contain "orc corpse"

    run.press "a", "c"
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
end
