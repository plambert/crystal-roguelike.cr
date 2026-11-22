require "../spec_helper"

Spectator.describe "the food eaten next" do
  alias Floor = Roguelike::Floor
  alias Food = Roguelike::Food
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Player = Roguelike::Player
  alias World = Roguelike::World

  HALL = [
    "######",
    "#<...#",
    "######",
  ]

  def hall(bag : Array(Item)) : Game
    floor = Playing.daylight Floor.parse("hall", HALL)
    player = Player.new floor.id, 1, 1
    player.sustenance.hunger = 2000
    bag.each { |item| player.food_bag.add item }
    game = Game.new World.new(Playing::SEED, {floor.id => floor}), player
    game.enroll
    game
  end

  def food(kind : ItemKind, age : Int32 = 0) : Item
    Item.new kind, blessing_known: true, age: age
  end

  def keeps(kind : ItemKind) : Int32
    Food.facts(kind).keeps
  end

  it "picks the food that changes freshness soonest" do
    bread = food ItemKind::Bread
    berries = food ItemKind::Berries, keeps(ItemKind::Berries) - 50
    stale_apple = food ItemKind::Apple, keeps(ItemKind::Apple) + 10
    game = hall [bread, stale_apple, berries]

    expect(game.meal).to be berries
  end

  it "puts fresh food that turns soon before stale food that turns later" do
    stale_apple = food ItemKind::Apple, keeps(ItemKind::Apple)
    berries = food ItemKind::Berries
    game = hall [stale_apple, berries]

    expect(game.meal).to be berries
  end

  it "breaks a tie with the food that is further along" do
    fresh = food ItemKind::Berries, keeps(ItemKind::Berries) - 100
    stale = food ItemKind::Berries, keeps(ItemKind::Berries) * 2 - 100
    game = hall [fresh, stale]

    expect(game.meal).to be stale
  end

  it "breaks a tie of stage with more of the stage gone" do
    apple = food ItemKind::Apple, keeps(ItemKind::Apple) - 100
    berries = food ItemKind::Berries, keeps(ItemKind::Berries) - 100
    game = hall [berries, apple]

    expect(game.meal).to be apple
  end

  it "puts food that never spoils after food that does" do
    ration = food ItemKind::Ration
    nuts = food ItemKind::Nuts
    game = hall [ration, nuts]

    expect(game.meal).to be nuts
  end

  it "skips rotten food" do
    rotten = food ItemKind::Berries, keeps(ItemKind::Berries) * 2
    ration = food ItemKind::Ration
    game = hall [rotten, ration]

    expect(game.meal).to be ration
    expect(game.meal(rotten: true)).to be ration
  end

  it "answers rotten food only when asked and nothing else is left" do
    rotten = food ItemKind::Berries, keeps(ItemKind::Berries) * 2
    game = hall [rotten]

    expect(game.meal).to be_nil
    expect(game.meal(rotten: true)).to be rotten
  end

  it "answers nothing for an empty bag" do
    expect(hall([] of Item).meal(rotten: true)).to be_nil
  end
end
