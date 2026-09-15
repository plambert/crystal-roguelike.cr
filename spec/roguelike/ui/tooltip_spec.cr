require "../../spec_helper"

Spectator.describe Roguelike::Ui::Tooltip do
  alias Condition = Roguelike::Condition
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Slot = Roguelike::Slot

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
        "weapon", "a masterwork +1 long sword", "damage 1d8+2",
        "thrown 8 squares", "weight 40",
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
        "a masterwork +1 long sword", "damage 1d8+2", "thrown 8 squares",
        "weight 40",
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
end
