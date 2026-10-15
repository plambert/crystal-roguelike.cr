require "../../spec_helper"

# A run that keeps every action that reached `#perform`.
#
# The menu on a letter has to send the same actions the key sends, so that a
# recorded run reads the same whichever way the person went.
class Handled < Roguelike::Game
  @[JSON::Field(ignore: true)]
  getter taken : Array(Roguelike::Action) = [] of Roguelike::Action

  def perform(action : Roguelike::Action) : Roguelike::Verdict
    @taken << action
    super
  end
end

Spectator.describe "the menu on an inventory letter" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Play = Roguelike::Ui::Play

  # One lit hall with the character at the west end.
  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  # A run with the character carrying *items*, on a screen *rows* tall.
  #
  # The sidebar shuts the pack on a short screen. A spec that clicks a pack
  # row needs a tall one.
  def carrying(items : Array(Item), rows : Int32 = 24) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)
    player = Roguelike::Player.new "hall", 1, 1, hit_points: 1
    items.each { |item| player.inventory.add item }

    Playing.open Handled.new(Roguelike::World.new(Playing::SEED, {"hall" => floor}), player),
      80, rows
  end

  # The actions *run* has taken, written out so two runs can be compared.
  def taken(run : Playing::Run) : Array(String)
    run.game.as(Handled).taken.map &.to_json
  end

  # The keys of the rows the menu is showing, and whether each can be picked.
  def offered(run : Playing::Run) : Array({Char, Bool})
    run.menu.entries.map { |entry| {entry.key, entry.enabled} }
  end

  # Every action key, in the order the menu lists them.
  KEYS = ['w', 'T', 'q', 'r', 'z', 'a', 't', 'd']

  describe "a letter in the inventory" do
    it "puts up every action, in a fixed order" do
      run = carrying [Item.new(Kind::Dagger)]

      run.press "i"
      run.press "a"

      expect(run.menu.showing?).to be_true
      expect(run.menu.title.to_s).to contain "a - "
      expect(run.menu.entries.map &.key).to eq KEYS
    end

    it "dims what does not apply to the item" do
      run = carrying [Item.new(Kind::Dagger)]

      run.press "i"
      run.press "a"

      expect(offered run).to eq [
        {'w', true}, {'T', false}, {'q', false}, {'r', false},
        {'z', false}, {'a', false}, {'t', true}, {'d', true},
      ]
    end

    it "keeps every key on the same row for another item" do
      run = carrying [Item.new(Kind::HealingPotion)]

      run.press "i"
      run.press "a"

      expect(run.menu.entries.map &.key).to eq KEYS
      expect(offered(run)[2]).to eq({'q', true})
      expect(offered(run)[0]).to eq({'w', false})
    end

    it "does nothing for a dimmed row" do
      run = carrying [Item.new(Kind::Dagger)]

      run.press "i"
      run.press "a"
      run.press "q"
      run.press "Down", "Enter"

      expect(run.menu.showing?).to be_true
      expect(run.turn).to eq 0
      expect(taken run).to be_empty
    end

    it "goes back to the inventory on Escape" do
      run = carrying [Item.new(Kind::Dagger)]

      run.press "i"
      run.press "a"
      run.press "Escape"

      expect(run.menu.showing?).to be_true
      expect(run.menu.title).to eq "Inventory"
    end
  end

  describe "an action from the menu" do
    it "wields as w does" do
      by_menu = carrying [Item.new(Kind::Dagger)]
      by_menu.press "i"
      by_menu.press "a"
      by_menu.press "w"

      by_key = carrying [Item.new(Kind::Dagger)]
      by_key.press "w"
      by_key.press "a"

      expect(by_menu.game.slot_of 'a').to eq Roguelike::Slot::Melee
      expect(taken by_menu).to eq taken(by_key)
      expect(taken by_menu).not_to be_empty
    end

    it "takes off as T does" do
      by_menu = carrying [Item.new(Kind::Dagger)]
      by_menu.press "w", "a"
      by_menu.press "i"
      by_menu.press "a"
      by_menu.press "T"

      by_key = carrying [Item.new(Kind::Dagger)]
      by_key.press "w", "a"
      by_key.press "T"

      expect(by_menu.game.slot_of 'a').to be_nil
      expect(taken by_menu).to eq taken(by_key)
    end

    it "drinks as q does" do
      by_menu = carrying [Item.new(Kind::HealingPotion)]
      by_menu.press "i"
      by_menu.press "a"
      by_menu.press "q"

      by_key = carrying [Item.new(Kind::HealingPotion)]
      by_key.press "q"
      by_key.press "a"

      expect(by_menu.game.player.inventory).to be_empty
      expect(taken by_menu).to eq taken(by_key)
    end

    it "drops as d does" do
      by_menu = carrying [Item.new(Kind::Dagger)]
      by_menu.press "i"
      by_menu.press "a"
      by_menu.press "d"

      by_key = carrying [Item.new(Kind::Dagger)]
      by_key.press "d"
      by_key.press "a"

      expect(by_menu.game.here.size).to eq 1
      expect(taken by_menu).to eq taken(by_key)
    end

    it "puts the cursor up to throw, as t does" do
      run = carrying [Item.new(Kind::Dagger)]

      run.press "i"
      run.press "a"
      run.press "t"

      expect(run.menu.showing?).to be_false
      expect(run.said).to contain "Aim with the movement keys"
      expect(taken run).to be_empty
    end
  end

  describe "the class of item along the top" do
    it "has a page for each class carried, after the first" do
      run = carrying [Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)]

      run.press "i"

      expect(run.menu.pages.map &.[0]).to eq ["all", "weapons", "potions"]
      expect(run.menu.page_name).to eq "all"
      expect(run.menu.tabs.hidden?).to be_false
    end

    it "turns with the right and left arrows, and keeps the letters" do
      run = carrying [Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)]

      run.press "i"
      run.press "Right"
      run.press "Right"

      expect(run.menu.page_name).to eq "potions"
      expect(run.menu.entries.map &.key).to eq ['b']

      run.press "Right"
      expect(run.menu.page_name).to eq "all"

      run.press "Left"
      expect(run.menu.page_name).to eq "potions"
    end

    it "shows the class name along the top of the box" do
      run = carrying [Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)]

      run.press "i"
      run.press "Right"

      expect(run.text).to contain "[weapons]"
    end

    it "answers only the letters on the page showing" do
      run = carrying [Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)]

      run.press "i"
      run.press "Right"
      run.press "b"

      expect(run.menu.title).to eq "Inventory"
    end

    it "comes back to the same page from the menu on a letter" do
      run = carrying [Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)]

      run.press "i"
      run.press "Right", "Right"
      run.press "b"
      run.press "Escape"

      expect(run.menu.title).to eq "Inventory"
      expect(run.menu.page_name).to eq "potions"
    end

    it "turns to a page whose name is clicked" do
      run = carrying [Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)]
      run.press "i"

      tabs = run.menu.tabs
      at = tabs.labels[2][0]
      run.click tabs.content.x + TermBuf::Widgets::Menu::Tabs::ENDS + at + 1, tabs.content.y

      expect(run.menu.page_name).to eq "potions"
    end
  end

  describe "a click on a pack row in the sidebar" do
    it "puts up the menu for that item" do
      run = carrying [Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)], rows: 40
      run.play.open_pack
      run.render

      row = run.play.character.pack[1].rect
      run.click row.x + 1, row.y

      expect(run.menu.showing?).to be_true
      expect(run.menu.title.to_s).to start_with "b - "
    end

    it "leaves the map behind it on Escape" do
      run = carrying [Item.new(Kind::Dagger)], rows: 40
      run.play.open_pack
      run.render

      row = run.play.character.pack[0].rect
      run.click row.x + 1, row.y
      run.press "Escape"

      expect(run.menu.showing?).to be_false
    end
  end

  it "is on the help screen" do
    rows = Roguelike::Ui::Keys.in_the_pack.notes

    expect(rows.map &.[0]).to contain "Left Right"
    expect(rows.last[0]).to eq KEYS.join(" ")
  end

  it "names a class for every class of item" do
    Roguelike::ItemClass.values.each do |kind|
      expect(Play::PACK_CLASSES).to contain Play.pack_class(kind)
    end
  end
end
