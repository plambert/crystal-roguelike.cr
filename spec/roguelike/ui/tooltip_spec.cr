require "../../spec_helper"

Spectator.describe Roguelike::Ui::Tooltip do
  alias Condition = Roguelike::Condition
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Size = Roguelike::Size
  alias Slot = Roguelike::Slot
  alias Species = Roguelike::Species

  # A run carrying a readied sword and a potion nobody has drunk.
  #
  # The looks are rolled, so the potion has a colour to be called by. A game
  # built without them names every potion by its kind, which is what a floor
  # written by hand for a spec gets.
  def playing(rows : Int32 = 44) : Playing::Run
    floor = Playing.field(30, 16).floor
    world = Roguelike::World.new Playing::SEED, {floor.id => floor}
    game = Roguelike::Game.new world,
      Roguelike::Player.new(floor.id, *Roguelike::Game.entrance(floor)),
      lore: Roguelike::Lore.roll(Roguelike::Rng.new Playing::SEED)

    game.player.inventory.add Item.new(Kind::LongSword, enchantment: 1,
      condition: Condition::Masterwork)
    game.player.inventory.add Item.new(Kind::HealingPotion)

    run = Playing.open game, 80, rows
    run.game.wield 'a'
    run.play.refresh
    run.render
    run
  end

  # Points at the row *row* and draws.
  def point_at(run : Playing::Run, row : Roguelike::Ui::Line) : Nil
    run.hover row.rect.x + 1, row.rect.y
  end

  # One lit room with the character on the staircase in the middle.
  ROOM = [
    "###########",
    "#.........#",
    "#.........#",
    "#....<....#",
    "#.........#",
    "#.........#",
    "###########",
  ]

  # A run on `ROOM`, drawn once.
  def room : Playing::Run
    on Playing.daylight(Roguelike::Floor.parse "room", ROOM), 5, 3
  end

  # A dark hall with a goblin standing against a lit square behind it.
  #
  # The character is at the west end with no light of their own. The lit
  # square at the east end is what the goblin shows against.
  BACKLIT = [
    "############",
    "#<.....g..*#",
    "############",
  ]

  # A run on `BACKLIT`, with light on the goblin when *lit*.
  def hall(lit : Bool = false) : Playing::Run
    floor = Roguelike::Floor.parse "backlit", BACKLIT
    Playing.daylight floor if lit
    floor.place Monster.new(Species::Goblin, 7, 1, "band-one")

    on floor, 1, 1
  end

  # A run on *floor*, with the character at *x*, *y*.
  def on(floor : Roguelike::Floor, x : Int32, y : Int32) : Playing::Run
    run = Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {floor.id => floor}),
      Roguelike::Player.new(floor.id, x, y)), 80, 44
    run.render
    run
  end

  # The rows of one section of the nearby pane, in the order they are written.
  def rows_of(section : Roguelike::Ui::Widgets::Panel) : Array(Roguelike::Ui::Line)
    section.children.compact_map &.as?(Roguelike::Ui::Line)
  end

  # What the "Seen" section says, row by row.
  def in_sight(run : Playing::Run) : Array(String)
    rows_of(run.nearby.seen).map &.text
  end

  describe "pointing at an equipment row" do
    it "puts the box up" do
      run = playing

      point_at run, run.play.character.slot_row(Slot::Melee)

      expect(run.play.tooltip.showing?).to be_true
    end

    it "writes the slot, the whole name and what the item does" do
      run = playing

      point_at run, run.play.character.slot_row(Slot::Melee)

      expect(run.play.tooltip.written).to eq [
        "a masterwork +1 long sword", "\u2694 weapon in hand", "unknown",
        "damage 1d8+2", "thrown 8 squares", "weight 40",
      ]
    end

    # The sidebar is where a person is pointing. Covering it would cover the
    # row they asked about.
    it "hangs to the left of the row, over the map" do
      run = playing
      row = run.play.character.slot_row Slot::Melee

      point_at run, row

      box = run.play.tooltip.rect
      expect(box.x + box.width).to be <= row.rect.x
    end

    it "draws it" do
      run = playing

      point_at run, run.play.character.slot_row(Slot::Melee)

      expect(run.text).to contain "a masterwork +1 long sword"
    end

    it "says nothing about an empty slot" do
      run = playing

      point_at run, run.play.character.slot_row(Slot::Ranged)

      expect(run.play.tooltip.showing?).to be_false
    end

    it "takes it down when the pointer goes back to the map" do
      run = playing

      point_at run, run.play.character.slot_row(Slot::Melee)
      run.hover 5, 5

      expect(run.play.tooltip.showing?).to be_false
    end
  end

  describe "pointing at a pack row" do
    it "writes what the character knows and no more" do
      run = playing
      run.play.open_pack
      run.render

      point_at run, run.play.character.pack[1]

      written = run.play.tooltip.written
      expect(written.first).to contain "potion"
      expect(written.first).not_to contain "healing"
      expect(written).to contain "nobody has found out what this is"
    end

    it "names it once it has been found out" do
      run = playing
      run.game.lore.learn Kind::HealingPotion
      run.play.open_pack
      run.render

      point_at run, run.play.character.pack[1]

      expect(run.play.tooltip.written.first).to eq "a potion of healing"
    end

    # A row with no entry is hidden, so there is nothing to point at. What is
    # there instead is the blank between two blocks, which says nothing.
    it "says nothing about a row with no entry on it" do
      run = playing
      run.play.open_pack
      run.render

      expect(run.play.character.pack[5].hidden?).to be_true

      point_at run, run.play.character.pack[1]
      last = run.play.character.pack[1].rect
      run.hover last.x + 1, last.y + 3

      expect(run.play.tooltip.showing?).to be_false
    end
  end

  describe "a menu row" do
    alias Entry = TermBuf::Widgets::Menu::Entry

    it "puts the box up on the row the menu opens with" do
      run = playing

      run.press "i"

      expect(run.play.tooltip.showing?).to be_true
      expect(run.play.tooltip.written).to eq [
        "a masterwork +1 long sword", "\u2694 weapon in hand", "unknown",
        "damage 1d8+2", "thrown 8 squares", "weight 40",
      ]
    end

    it "follows the highlight down the list" do
      run = playing

      run.press "i"
      run.press "Down"

      expect(run.play.tooltip.written.first).to contain "potion"
    end

    # The box is about one row, so it has to be level with that row and clear
    # of the list the row is in.
    it "sits level with the row and clear of the menu" do
      run = playing

      run.press "i"
      run.press "Down"

      box = run.play.tooltip.rect
      expect(box.y).to eq run.menu.list.rect.y + 1
      expect(box.x + box.width).to be <= run.menu.rect.x
    end

    # The menu is a modal overlay, which dims everything painted below it.
    # A box painted below would be dimmed and covered both.
    it "draws over the menu" do
      run = playing

      run.press "i"

      expect(run.text).to contain "damage 1d8+2"
    end

    it "moves with the pointer across the rows" do
      run = playing
      run.press "i"
      list = run.menu.list.rect

      run.hover list.x + 1, list.y + 1

      expect(run.menu.list.selected).to eq 1
      expect(run.play.tooltip.written.first).to contain "potion"
    end

    it "goes down with the menu" do
      run = playing

      run.press "i"
      run.press "Escape"

      expect(run.play.tooltip.showing?).to be_false
    end

    it "goes down when a row is picked" do
      run = playing

      run.press "d"
      run.press "b"

      expect(run.play.tooltip.showing?).to be_false
    end

    # The apply menu has one row per wall sconce, and a sconce is a fixture
    # rather than something carried. There is nothing to write about it.
    it "hangs nothing off a row about nothing carried" do
      run = playing

      run.play.choose("Apply what?", [Entry.new('a', "the sconce beside you")]) { }
      run.render

      expect(run.play.tooltip.showing?).to be_false
    end

    # The scroll menu is the same code as the inventory menu, and `r` is what
    # a person reaches for when they want to know what a scroll is.
    it "writes what is known about a scroll nobody has read" do
      run = playing
      run.game.player.inventory.add Item.new(Kind::MappingScroll)
      run.play.refresh

      run.press "r"

      written = run.play.tooltip.written
      expect(written.first).to contain "scroll"
      expect(written.first).not_to contain "magic mapping"
      expect(written).to contain "nobody has found out what this is"
    end
  end

  describe "the pack heading" do
    it "opens the pack when it is pressed" do
      run = playing
      expect(run.play.character.showing_pack?).to be_false

      heading = run.play.character.pack_heading
      run.click heading.rect.x, heading.rect.y

      expect(run.play.character.showing_pack?).to be_true
    end

    it "shuts it again on a second press" do
      run = playing
      heading = run.play.character.pack_heading

      run.click heading.rect.x, heading.rect.y
      run.click heading.rect.x, heading.rect.y

      expect(run.play.character.showing_pack?).to be_false
    end

    # A press on the sidebar is not a press on the map. The examine cursor
    # must not follow it.
    it "keeps the click off the map" do
      run = playing
      heading = run.play.character.pack_heading
      before = run.examiner.spot

      run.click heading.rect.x, heading.rect.y

      expect(run.examiner.spot).to eq before
    end
  end

  describe "pointing at a Here row" do
    it "writes what the terrain under the character is" do
      run = room

      point_at run, rows_of(run.nearby.here).first

      expect(run.play.tooltip.written).to eq [
        "staircase up", "a staircase leading up",
      ]
    end

    it "writes what is lying on the square" do
      run = room
      run.game.floor.drop 5, 3, Item.new(Kind::LongSword)
      run.play.refresh
      run.render

      point_at run, rows_of(run.nearby.here).last

      expect(run.play.tooltip.written).to eq [
        "a long sword", "unknown", "damage 1d8", "thrown 8 squares",
        "weight 40",
      ]
    end

    it "writes what a fixture on the square is" do
      run = on Playing.daylight(Roguelike::Floor.parse "sconce", [
        "#####",
        "#...#",
        "#|..#",
        "#..<#",
        "#####",
      ]), 1, 2

      point_at run, rows_of(run.nearby.here)[1]

      written = run.play.tooltip.written
      expect(written.first).to eq "sconce"
      expect(written[1]).to contain "torch"
    end
  end

  describe "pointing at a Seen row" do
    it "writes what a creature with light on it is" do
      run = room
      run.game.floor.place Monster.new(Species::Goblin, 8, 3, "band-one")
      run.play.refresh
      run.render

      point_at run, rows_of(run.nearby.seen).first

      expect(run.play.tooltip.written).to eq [
        "goblin", "a small green thing with a large knife",
        "hit points 9/9", "asleep",
      ]
    end

    it "writes what an item across the room is" do
      run = room
      run.game.floor.drop 8, 3, Item.new(Kind::Dagger)
      run.play.refresh
      run.render

      point_at run, rows_of(run.nearby.seen).first

      expect(run.play.tooltip.written.first).to eq "a dagger"
    end

    # The row saying the character can see nothing is about nothing.
    it "says nothing about the row that says nothing" do
      run = room

      point_at run, rows_of(run.nearby.seen).first

      expect(run.play.tooltip.showing?).to be_false
    end
  end

  # The map draws a creature against light behind it by its size alone. What
  # the words say has to hide what the picture hides.
  describe "a creature made out only as a shape" do
    it "reads as its size in the Seen list" do
      run = hall

      expect(in_sight run).to contain Size::Small.label
      expect(in_sight run).not_to contain "goblin"
    end

    it "reads as its size in the readout" do
      run = hall

      run.hover 7, 1

      expect(run.examine.what.text).to eq Size::Small.label
      expect(run.examine.detail.text).to eq Roguelike::Ui::ExaminePane::MOVING
    end

    it "reads as its size in its tooltip" do
      run = hall

      point_at run, rows_of(run.nearby.seen).first

      expect(run.play.tooltip.written).to eq [
        Size::Small.label, Roguelike::Ui::ExaminePane::MOVING,
      ]
    end

    it "gives away neither its species nor its hit points" do
      run = hall

      point_at run, rows_of(run.nearby.seen).first
      written = run.play.tooltip.written

      expect(written.any?(&.includes? "goblin")).to be_false
      expect(written.any?(&.includes? "hit points")).to be_false
    end

    it "is a goblin in all three once there is light on it" do
      run = hall lit: true

      point_at run, rows_of(run.nearby.seen).first

      expect(in_sight run).to contain "goblin"
      expect(run.play.tooltip.written.first).to eq "goblin"

      run.hover 7, 1

      expect(run.examine.what.text).to eq "goblin"
    end
  end
end
