require "../../spec_helper"

Spectator.describe "reading a scroll of blessing" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Blessing = Roguelike::Blessing

  # A lit one room floor with the character in the middle, carrying *items*.
  def holding(items : Array(Item)) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room",
      "#####\n#...#\n#.<.#\n#...#\n#####")
    floor.clear_items 2, 2

    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}),
      Roguelike::Player.new("room", 2, 2)
    items.each { |item| game.player.inventory.add item }

    Playing.open game
  end

  it "makes the marks before it asks" do
    cursed = Item.new Kind::Dagger, blessing: Blessing::Cursed
    run = holding [Item.new(Kind::BlessingScroll), cursed]

    run.press "r"
    run.press "a"

    expect(cursed.blessing_known?).to be_true
    expect(run.menu.showing?).to be_true
  end

  it "blesses what was picked" do
    sword = Item.new Kind::LongSword
    run = holding [Item.new(Kind::BlessingScroll), sword]

    run.press "r"
    run.press "a"
    run.press "b"

    expect(sword.blessed?).to be_true
    expect(run.menu.showing?).to be_false
  end

  it "spends the scroll before it asks" do
    run = holding [Item.new(Kind::BlessingScroll), Item.new(Kind::LongSword)]

    run.press "r"
    run.press "a"

    expect(run.game.player.inventory.has? 'a').to be_false
    expect(run.game.turn).to eq 1
  end

  it "asks again before it lets the choice go" do
    run = holding [Item.new(Kind::BlessingScroll), Item.new(Kind::LongSword)]

    run.press "r"
    run.press "a"
    run.press "escape"

    expect(run.prompt.asking?).to be_true
    expect(run.text).to contain "Give up"
  end

  it "puts the question back on no" do
    sword = Item.new Kind::LongSword
    run = holding [Item.new(Kind::BlessingScroll), sword]

    run.press "r"
    run.press "a"
    run.press "escape"
    run.press "n"

    expect(run.menu.showing?).to be_true

    run.press "b"

    expect(sword.blessed?).to be_true
  end

  it "gives the choice up on yes" do
    sword = Item.new Kind::LongSword
    run = holding [Item.new(Kind::BlessingScroll), sword]

    run.press "r"
    run.press "a"
    run.press "escape"
    run.press "y"

    expect(run.menu.showing?).to be_false
    expect(run.prompt.asking?).to be_false
    expect(sword.blessed?).to be_false
  end

  # A blessed scroll reaches everything and has nothing to ask.
  it "asks nothing when the scroll is blessed" do
    sword = Item.new Kind::LongSword
    run = holding [Item.new(Kind::BlessingScroll, blessing: Blessing::Blessed),
                   sword]

    run.press "r"
    run.press "a"

    expect(run.menu.showing?).to be_false
    expect(sword.blessed?).to be_true
  end

  it "asks nothing when the scroll is cursed" do
    run = holding [Item.new(Kind::BlessingScroll, blessing: Blessing::Cursed),
                   Item.new(Kind::LongSword)]

    run.press "r"
    run.press "a"

    expect(run.menu.showing?).to be_false
    expect(run.game.log.lines.any? &.includes?("picks out")).to be_true
  end

  # A letter holding twelve arrows and three more reads as fifteen.
  it "counts a whole letter in the list" do
    run = holding [Item.new(Kind::Arrow, count: 12),
                   Item.new(Kind::Arrow, count: 3, blessing: Blessing::Cursed)]

    run.press "i"

    expect(run.menu.entries.size).to eq 1
    expect(run.menu.entries.first.text).to contain "15"
  end
end
