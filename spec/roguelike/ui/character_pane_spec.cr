require "../../spec_helper"

Spectator.describe Roguelike::Ui::CharacterPane do
  alias Blessing = Roguelike::Blessing
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Naming = Roguelike::Ui::Naming
  alias Pane = Roguelike::Ui::CharacterPane
  alias Slot = Roguelike::Slot

  # A run on one open room, drawn in a window of *rows*.
  def playing(rows : Int32 = 40, carrying : Array(Item) = [] of Item,
              name : String = "") : Playing::Run
    game = Playing.field 30, 16
    game.player.name = name
    carrying.each { |item| game.player.inventory.add item }

    Playing.open game, 80, rows
  end

  # Row *y* of the screen, cut at the right edge of the info panel.
  def info_row(run : Playing::Run, y : Int32) : String
    box = run.screen.info.rect
    run.row(y).ljust(box.right)[box.x, box.width]
  end

  # What a row draws at *column*, or `nil` for a blank cell.
  def span_at(row : Roguelike::Ui::Line, column : Int32) : Roguelike::Ui::Line::Span?
    row.spans.find &.column.==(column)
  end

  # What a row draws at *column*, where something must be drawn.
  def span_at!(row : Roguelike::Ui::Line, column : Int32) : Roguelike::Ui::Line::Span
    row.spans.find! &.column.==(column)
  end

  # Which row of the pane holds *slot*.
  def slot_row(run : Playing::Run, slot : Slot) : Roguelike::Ui::Line
    run.play.character.slot_row slot
  end

  describe "what it writes" do
    it "heads it with the name and the level" do
      run = playing name: "Sparky"

      expect(run.play.character.who.text).to eq "SparkyD1 Lv 1"
    end

    # A run holds no name until the title screen has been answered, and a
    # spec builds a character that never goes near one.
    it "heads a character nobody has named with a dash" do
      run = playing

      expect(run.play.character.who.text).to eq "#{Pane::NOBODY}D1 Lv 1"
    end

    it "draws the level against the right edge" do
      run = playing name: "Sparky"
      row = info_row run, run.play.character.who.rect.y

      expect(row.rstrip).to end_with "Lv 1"
      expect(row).to contain "Sparky"
    end

    # The level is what a person reads every turn. A long name gives way to
    # it rather than pushing it off the row.
    it "cuts a name too long for the row" do
      run = playing name: "Bartholomew the Unreasonably Long"
      row = info_row run, run.play.character.who.rect.y

      expect(row.rstrip).to end_with "Lv 1"
      expect(row).to contain Roguelike::Ui::Line::ELLIPSIS
    end

    it "writes the armor class, the gold and the turn under their names" do
      run = playing
      run.game.player.take_gold 40
      run.play.refresh

      expect(run.play.character.number_names.text).to eq "ACGoldTurn"
      expect(run.play.character.numbers.text).to eq ["0", "40", "0"].join
    end

    it "writes the five scores under their names" do
      run = playing

      expect(run.play.character.score_names.text).to eq "StDxCnInSl"
      expect(run.play.character.scores.text).to eq "10" * 5
    end

    it "fills the hit point bar from the character" do
      run = playing
      player = run.game.player

      expect(run.play.character.health.value).to eq player.hit_points
      expect(run.play.character.health.most).to eq player.max_hit_points
    end

    # The bar is the part of this level that is done, so a full bar always
    # means the next level. The reading is the whole count either way.
    it "fills the experience bar with the part of the level that is done" do
      run = playing
      run.game.player.gain 30
      run.play.refresh

      learning = run.play.character.learning
      expect(learning.value).to eq 30 - Roguelike::Advancement.threshold(2)
      expect(learning.reading).to eq "30/40"
    end

    it "shows no magic bar until there is magic" do
      expect(playing.play.character.magic.hidden?).to be_true
    end
  end

  describe "the equipment rows" do
    it "writes a row for every slot, in the order it lists them" do
      run = playing

      Slot.listed.each_with_index do |slot, index|
        expect(run.play.character.slots[index].text).to start_with slot.short
      end
    end

    # A person learns which row the weapon is on. A row that came and went
    # would make them read the labels every time.
    it "writes an empty slot rather than leaving the row out" do
      run = playing

      expect(slot_row(run, Slot::Melee).text).to eq "wpn#{Pane::NOTHING}"
    end

    it "writes what is in a slot in the color the map draws it in" do
      run = playing carrying: [Item.new(Kind::LongSword)]
      run.game.wield 'a'
      run.play.refresh

      expect(slot_row(run, Slot::Melee).text).to eq "wpnlong swd"
    end

    it "marks a known blessing beside the slot word, as the menus do" do
      sword = Item.new Kind::LongSword, blessing: Blessing::Cursed, blessing_known: true
      run = playing carrying: [sword]
      run.game.wield 'a'
      run.play.refresh
      row = slot_row run, Slot::Melee
      mark = span_at!(row, Pane::MARK)

      expect(mark.text).to eq Roguelike::Ui::Palette::CURSED.to_s
      expect(mark.style).to eq Roguelike::Ui::Palette.cursed_mark
      expect(row.text).not_to contain "crs"
    end
  end

  describe "the pack" do
    it "is shut to begin with" do
      expect(playing.play.character.showing_pack?).to be_false
    end

    it "opens and shuts on the triangle" do
      pane = playing.play.character

      pane.toggle_pack
      expect(pane.showing_pack?).to be_true
      expect(pane.pack_heading.text).to start_with Pane::OPEN.to_s

      pane.toggle_pack
      expect(pane.showing_pack?).to be_false
      expect(pane.pack_heading.text).to start_with Pane::SHUT.to_s
    end

    it "writes a row per entry, by its letter" do
      run = playing carrying: [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 14)]

      expect(run.play.character.pack[0].text).to eq "a)bow"
      expect(run.play.character.pack[1].text).to eq "b)14 arrow"
    end

    it "marks a known blessing beside the letter and leaves the word out" do
      run = playing carrying: [
        Item.new(Kind::Dagger, blessing: Blessing::Blessed, blessing_known: true),
      ]
      row = run.play.character.pack[0]
      mark = span_at!(row, Pane::PACK_MARK)

      expect(mark.text).to eq Roguelike::Ui::Palette::BLESSED.to_s
      expect(mark.style).to eq Roguelike::Ui::Palette.blessed_mark
      expect(row.text).to eq "a#{Roguelike::Ui::Palette::BLESSED})dagger"
      expect(row.text).not_to contain "bls"
    end

    # A menu draws the mark for uncursed too. Only an unknown blessing is blank.
    it "marks a known uncursed item" do
      run = playing carrying: [
        Item.new(Kind::Dagger, blessing: Blessing::Uncursed, blessing_known: true),
      ]
      mark = span_at!(run.play.character.pack[0], Pane::PACK_MARK)

      expect(mark.text).to eq Roguelike::Ui::Palette::UNCURSED.to_s
      expect(mark.style).to eq Roguelike::Ui::Palette.uncursed_mark
    end

    it "leaves the mark cell blank for a blessing not worked out" do
      run = playing carrying: [Item.new(Kind::Dagger, blessing: Blessing::Blessed)]
      row = run.play.character.pack[0]

      expect(span_at row, Pane::PACK_MARK).to be_nil
      expect(row.text).to eq "a)dagger"
    end

    it "starts the names in the same column as the slot rows do" do
      expect(Pane::PACK_NAME).to eq Pane::NAME
    end

    it "writes every entry, however many there are" do
      many = (0...13).map { |plus| Item.new Kind::Dagger, enchantment: plus }
      run = playing carrying: many

      expect(run.play.character.pack.count { |row| !row.hidden? }).to eq 13
    end

    it "counts its entries on a shut header" do
      run = playing carrying: [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 14)]

      expect(run.play.character.pack_heading.text).to eq "#{Pane::SHUT} #{Pane::PACK} 2"
    end
  end

  describe "an empty quiver that remembers its kind" do
    it "says what it is out of" do
      run = playing
      run.game.player.quiver_memory = Roguelike::Equipment::Remembered.new(Kind::Stone)
      run.play.refresh

      expect(slot_row(run, Slot::Quiver).text).to eq "qvrno stones"
    end

    it "is dimmed the way an empty slot is" do
      run = playing
      run.game.player.quiver_memory = Roguelike::Equipment::Remembered.new(Kind::Arrow)
      run.play.refresh
      named = slot_row(run, Slot::Quiver).spans.find! &.text.==("no arrows")

      expect(named.style).to eq Roguelike::Ui::Palette.vacant
    end

    it "says nothing when the pointer is over it" do
      run = playing
      run.game.player.quiver_memory = Roguelike::Equipment::Remembered.new(Kind::Arrow)

      expect(Roguelike::Ui::Detail.about run.game, Slot::Quiver).to be_nil
    end
  end

  describe "the sections" do
    it "pins the vitals above the scrolling sections" do
      run = playing rows: 24, carrying: [Item.new(Kind::Bow)]
      run.render
      run.screen.info.scroll_y = run.screen.info.max_scroll[1]
      run.render

      expect(run.play.character.who.rect.y).to eq 0
      expect(info_row run, 0).to contain "Lv 1"
    end

    it "counts the armor class on a shut scores header" do
      run = playing
      run.play.character.scoring.toggle

      expect(run.play.character.scoring.header.text).to eq "#{Pane::SHUT} #{Pane::SCORES} AC 0"
    end

    it "counts the filled slots on a shut equipment header" do
      run = playing carrying: [Item.new(Kind::LongSword)]
      run.game.wield 'a'
      run.play.refresh

      expect(run.play.character.worn_heading.text).to eq "#{Pane::SHUT} #{Pane::WORN} 1"
    end

    it "scrolls under the wheel and keeps every section's rows" do
      run = playing rows: 24, carrying: [Item.new(Kind::Bow)]
      run.play.character.worn.toggle
      run.play.character.packed.toggle
      run.render
      heading = run.play.character.worn_heading.rect

      run.wheel heading.x, heading.y, up: false
      expect(run.screen.info.scroll_y).to be > 0
      expect(run.play.character.vitals.rect.y).to eq 0
    end

    it "pulls the scroll back when a section shuts under it" do
      run = playing rows: 24, carrying: [Item.new(Kind::Bow)]
      run.play.character.worn.toggle
      run.play.character.packed.toggle
      run.render
      run.screen.info.scroll_y = run.screen.info.max_scroll[1]
      run.render

      run.play.character.worn.toggle
      run.play.character.packed.toggle
      run.render

      expect(run.screen.info.scroll_y).to be <= run.screen.info.max_scroll[1]
    end
  end

  describe "on the screen" do
    it "scrolls to the three readouts at the shortest terminal there is" do
      run = playing rows: Roguelike::Ui::Screen::MINIMUM_ROWS
      run.render
      run.screen.info.scroll_to_end
      drawn = run.text

      expect(drawn).to contain "Lv 1"
      expect(drawn).to contain "Seen"
      expect(drawn).to contain "Look"
    end

    it "shows every section at a tall terminal" do
      drawn = playing(rows: 50).text

      expect(drawn).to contain "Lv 1"
      expect(drawn).to contain "Equipment"
      expect(drawn).to contain "Pack"
      expect(drawn).to contain "Here"
      expect(drawn).to contain "Look"
    end
  end
end
