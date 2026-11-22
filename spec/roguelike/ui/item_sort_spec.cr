require "../../spec_helper"

Spectator.describe "the sort key in lists of items" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Options = Roguelike::Options
  alias Play = Roguelike::Ui::Play
  alias Widgets = TermBuf::Widgets

  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  after_each { Options.current = nil }

  # A dagger, a potion, chain mail and a scroll, picked up in that order.
  def mixed : Array(Item)
    [
      Item.new(Kind::Dagger, blessing_known: true),
      Item.new(Kind::HealingPotion, blessing_known: true),
      Item.new(Kind::ChainMail, blessing_known: true),
      Item.new(Kind::IdentifyScroll, blessing_known: true),
    ]
  end

  # A game in a lit hall, carrying *pack*, with *floor* underfoot and *bag*
  # in the food bag.
  def stocked(pack : Array(Item), floor : Array(Item) = [] of Item,
              bag : Array(Item) = [] of Item) : Roguelike::Game
    hall = Playing.daylight Roguelike::Floor.parse("hall", HALL)
    player = Roguelike::Player.new hall.id, 1, 1
    player.sustenance.hunger = 2000
    pack.each { |item| player.inventory.add item }
    bag.each { |item| player.food_bag.add item }
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {hall.id => hall}), player
    floor.each { |item| game.floor.drop 1, 1, item }
    game
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

  # The text of the heading rows the menu is showing.
  def headers(run : Playing::Run) : Array(String)
    run.menu.entries.select(&.header).map &.text
  end

  # The keys of the rows that are not headings.
  def keys(run : Playing::Run) : Array(Char)
    run.menu.entries.reject(&.header).map &.key
  end

  describe "in the traditional scheme" do
    it "puts up the orders on =, and Escape goes back to the list" do
      run = traditional stocked(mixed)
      run.press "i"
      run.press "="

      expect(run.menu.title).to eq Play::SORT_TITLE
      expect(run.menu.entries.map &.text).to eq %w[name weight class]

      run.press "Escape"
      expect(run.menu.title).to eq Play::INVENTORY
      expect(run.menu.page_name).to eq Play::EVERYTHING
    end

    it "sorts the inventory by weight, heaviest first, and keeps each letter" do
      run = traditional stocked(mixed)
      run.press "i", "=", "b"

      weights = keys(run).reject(&.==(Play::FOOD_BAG_KEY)).map do |key|
        run.game.player.inventory[key].try(&.weight) || 0
      end
      expect(weights).to eq weights.sort { |one, other| other <=> one }
      expect(keys(run).first).to eq 'c'
    end

    it "puts a heading before each class when sorted by class" do
      run = traditional stocked(mixed)
      run.press "i", "=", "c"

      expect(headers run).to eq %w[Weapons Armor Potions Scrolls]
      expect(keys run).to eq ['a', 'c', 'b', 'd', Play::FOOD_BAG_KEY]
    end

    it "steps the highlight over headings" do
      run = traditional stocked(mixed)
      run.press "i", "=", "c"

      expect(run.menu.list.selected).to eq 1
      run.press "Down"
      expect(run.menu.list.selected).to eq 3
      run.press "Up"
      expect(run.menu.list.selected).to eq 1
      run.press "Up"
      expect(run.menu.list.selected).to eq 1
    end

    it "keeps the class pages as they are" do
      run = traditional stocked(mixed)
      run.press "i", "=", "c", "Right"

      expect(run.menu.page_name).to eq "weapons"
      expect(headers run).to be_empty
    end

    it "remembers each list's order on its own" do
      run = traditional stocked(mixed)
      run.press "i", "=", "c", "Escape"
      run.press "i"
      expect(headers run).to_not be_empty
      run.press "Escape"

      run.press "d"
      expect(headers run).to be_empty
    end

    it "sorts the pick-up list by name or class" do
      run = traditional stocked([] of Item, floor: mixed)
      run.press ","
      run.press "="
      expect(run.menu.entries.map &.text).to eq %w[name class]

      run.press "b"
      expect(run.menu.title).to eq Play::PICK_UP
      expect(headers run).to eq %w[Weapons Armor Potions Scrolls]

      run.press "c"
      expect(run.game.player.inventory.entries.map(&.[1].kind)).to eq [Kind::ChainMail]
    end

    it "picks the food bag's page from a list" do
      run = traditional stocked([] of Item, bag: [
        Item.new(Kind::Ration, blessing_known: true),
        Item.new(Kind::Apple, blessing_known: true),
      ])
      run.press "E", "="

      expect(run.menu.entries.map &.text).to eq Roguelike::FoodSort.pages.map(&.label)
      run.press "e"
      expect(run.menu.page_name).to eq "name"
    end

    it "takes no turn and sends no action" do
      run = traditional stocked(mixed)
      run.press "i", "=", "c", "Escape"

      expect(run.turn).to eq 0
    end
  end

  describe "in the modern scheme" do
    it "puts up the orders on r and sorts by class" do
      run = modern stocked(mixed)
      run.press "i", "r"

      expect(run.menu.title).to eq Play::SORT_TITLE
      run.press "s", "s", "f"

      expect(run.menu.title).to eq Play::INVENTORY
      expect(headers run).to eq %w[Weapons Armor Potions Scrolls]
      expect(run.play.selection_menu.selected_value.try(&.item_id)).to eq mixed_ids(run)[0]
    end

    it "steps over headings with s" do
      run = modern stocked(mixed)
      run.press "i", "r", "s", "s", "f"
      run.press "s"

      expect(run.menu.entries[run.menu.list.selected].header).to be_false
      expect(run.menu.list.selected).to eq 3
    end

    it "sorts a list of targets" do
      run = modern stocked([] of Item, floor: mixed)
      run.press "g", "r", "s", "f"

      expect(headers run).to eq %w[Weapons Armor Potions Scrolls]
    end
  end

  it "lists the key in the help for both schemes" do
    expect(Roguelike::Ui::Keys.in_the_pack.notes.map &.[0]).to contain "="
    expect(Roguelike::Ui::Keys.in_the_food_bag.notes.map &.[0]).to contain "="
    expect(Roguelike::Ui::Keys.in_a_list.notes.map &.[0]).to contain "r"
  end

  # The ids of the items the run carries, in the order they were picked up.
  def mixed_ids(run : Playing::Run) : Array(Int32)
    run.game.player.inventory.entries.map &.[1].id
  end
end
