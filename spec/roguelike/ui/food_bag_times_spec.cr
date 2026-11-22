require "../../spec_helper"

Spectator.describe "the times on the food bag screen" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Options = Roguelike::Options

  BAG_HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  after_each { Options.current = nil }

  def food(kind : Kind, count : Int32 = 1, age : Int32 = 0) : Item
    Item.new kind, count: count, blessing_known: true, age: age
  end

  # The food bag screen open on a run *columns* wide, with *bag* in the bag
  # and *water* in the skin.
  def opened(bag : Array(Item), columns : Int32, water : Int32 = 7) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("hall", BAG_HALL)
    player = Roguelike::Player.new floor.id, 1, 1
    player.sustenance.hunger = 2000
    player.sustenance.water = water
    bag.each { |item| player.food_bag.add item }
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {floor.id => floor}), player
    Options.current = Options.new
    run = Playing.open game, columns, 30
    run.press "E"
    run
  end

  # The text of the row for the food bag entry under *key*.
  def row_for(run : Playing::Run, key : Char) : String
    run.menu.entries.find!(&.key.==(key)).text
  end

  it "shows how long each stack feeds and when it next turns" do
    run = opened [food(Kind::FreshMeat, 2, age: 250), food(Kind::Ration, 2)], 140

    expect(row_for run, 'a').to match /2 pieces of fresh meat +\d+ +50m stale in <10m$/
    expect(row_for run, 'b').to match /2 rations +8 +8h20m$/
  end

  it "says when stale food turns rotten" do
    run = opened [food(Kind::Bread, age: 1_600)], 140

    expect(row_for run, 'a').to match /stale.* bread +\d+ +1h40m rotten in 3h50m$/
  end

  it "says when rotten food turns putrid" do
    run = opened [food(Kind::Bread, age: 3_100)], 140

    expect(row_for run, 'a').to match /rotten.* bread +\d+ +.* putrid in \S+$/
  end

  it "puts the water in the skin in the title, with how long it lasts" do
    run = opened [food(Kind::Apple)], 140, water: 7

    expect(run.menu.title.to_s).to eq "Food bag 2/40, water 7/20 8h40m"
  end

  it "drops the turning time before the rows outgrow an 80 column screen" do
    run = opened [food(Kind::FreshMeat, 2), food(Kind::Ration, 2)], 80
    rows = run.menu.entries.map &.text

    expect(rows.none? &.includes?("stale in")).to be_true
    expect(run.text).to contain "2 pieces of fresh meat"
  end
end
