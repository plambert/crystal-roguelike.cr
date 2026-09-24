require "../../spec_helper"

Spectator.describe "the marks against a row of a list" do
  alias Blessing = Roguelike::Blessing
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Line = Roguelike::Ui::Line
  alias Palette = Roguelike::Ui::Palette

  # One lit room with the character on the staircase in the middle.
  ROOM = [
    "#########",
    "#.......#",
    "#...<...#",
    "#.......#",
    "#########",
  ]

  # A run carrying *items*, with nothing else in the pack.
  def carrying(items : Array(Item)) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
    game = Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"room" => floor}),
      Roguelike::Player.new("room", 4, 2))

    items.each { |item| game.player.inventory.add item }

    run = Playing.open game, 80, 30
    run.render
    run
  end

  # The pack rows, with the menu up.
  def pack(run : Playing::Run) : Array(TermBuf::Widgets::Menu::Entry)
    run.press "i"
    run.menu.entries
  end

  # A weapon of *blessing*, worked out or not.
  def sword(blessing : Blessing, known : Bool = true) : Item
    Item.new Kind::ShortSword, blessing: blessing, blessing_known: known
  end

  describe "the blessing" do
    it "marks a blessed item" do
      run = carrying [sword Blessing::Blessed]

      expect(pack(run).first.mark).to eq Palette::BLESSED
      expect(pack(run).first.mark_style).to eq Palette::BLESSED_MARK
    end

    it "marks a cursed item" do
      run = carrying [sword Blessing::Cursed]

      expect(pack(run).first.mark).to eq Palette::CURSED
    end

    # Most things are uncursed, so that mark is the faintest of the three.
    it "marks an uncursed item" do
      run = carrying [sword Blessing::Uncursed]

      expect(pack(run).first.mark).to eq Palette::UNCURSED
      expect(pack(run).first.mark_style).to eq Palette::UNCURSED_MARK
    end

    # An item whose blessing is not worked out has no mark. Every item whose
    # blessing is settled has one of the three marks.
    it "marks an item whose blessing is not worked out with nothing" do
      run = carrying [sword Blessing::Blessed, known: false]

      expect(pack(run).first.mark).to eq ' '
    end

    # The mark replaces the word. Both together would be the same thing
    # twice.
    it "leaves the word out of the name" do
      run = carrying [sword Blessing::Cursed]

      expect(pack(run).first.text).not_to contain "cursed"
    end
  end

  describe "the field in front of the name" do
    it "holds the article" do
      run = carrying [Item.new Kind::Dagger]

      expect(pack(run).first.text).to eq " a dagger"
    end

    it "holds the count" do
      run = carrying [Item.new Kind::Arrow, count: 9]

      expect(pack(run).first.text).to eq " 9 arrows"
    end

    # The names line up down the list. Two cells hold every count up to
    # ninety-nine. A larger count widens the field rather than pushing one
    # row of names out of line.
    it "widens for a count that does not fit" do
      run = carrying [Item.new(Kind::Arrow, count: 120), Item.new(Kind::Dagger)]
      rows = pack run

      expect(rows[0].text).to eq "120 arrows"
      expect(rows[1].text).to eq "  a dagger"
    end

    it "is blank for a name that takes no article" do
      run = carrying [Item.new Kind::LeatherArmour]

      expect(pack(run).first.text).to eq "   leather armour"
    end
  end

  describe "the mark at the far edge" do
    it "is the slot an item is readied in" do
      run = carrying [Item.new Kind::ShortSword]
      run.press "w", "a"

      expect(pack(run).first.tail).to eq Palette::MELEE
    end

    it "is nothing for an item put away" do
      run = carrying [Item.new Kind::ShortSword]

      expect(pack(run).first.tail).to be_nil
    end

    it "says a light source is burning" do
      run = carrying [Item.new Kind::Torch, lit: true]

      expect(pack(run).first.tail).to eq Palette::LIT
    end

    it "says nothing about a light source that is out" do
      run = carrying [Item.new Kind::Torch]

      expect(pack(run).first.tail).to be_nil
    end
  end

  describe "a row of the sidebar under the pointer" do
    # The rows of one section, in the order they are written.
    def rows_of(section : Roguelike::Ui::Widgets::Panel) : Array(Line)
      section.children.compact_map &.as?(Line)
    end

    # Points at *row* and draws.
    def point_at(run : Playing::Run, row : Line) : Nil
      run.hover row.rect.x + 1, row.rect.y
    end

    # A run with two things underfoot, so "Here" has rows to point at.
    def littered : Playing::Run
      run = carrying [] of Item
      run.game.floor.drop 4, 2, Item.new(Kind::Dagger)
      run.game.floor.drop 4, 2, Item.new(Kind::Cap)
      run.play.refresh
      run.render
      run
    end

    it "wears the marks" do
      run = littered
      row = rows_of(run.nearby.here).last

      point_at run, row

      expect(row.marks).to eq Roguelike::Ui::NearbyPane::MARKS
    end

    it "is the only row wearing them" do
      run = littered
      rows = rows_of run.nearby.here

      point_at run, rows.last
      point_at run, rows.first

      expect(rows.first.marks).not_to be_nil
      expect(rows.last.marks).to be_nil
    end

    # The rows are built again every turn. A mark left on a row that is gone
    # would point at nothing.
    it "loses them when the pane is written again" do
      run = littered
      row = rows_of(run.nearby.here).last
      point_at run, row

      run.play.refresh

      expect(row.marks).to be_nil
    end

    # The text starts clear of the marks, so a row does not move sideways
    # under the pointer.
    it "does not move when the pointer arrives" do
      run = littered
      row = rows_of(run.nearby.here).last
      before = row.spans.map &.column

      point_at run, row

      expect(row.spans.map &.column).to eq before
      expect(before.first).to eq Line::INDENT
    end
  end

  describe "the tooltip on a row" do
    it "writes the mark and the word for it" do
      run = carrying [sword Blessing::Cursed]
      run.press "i"

      expect(run.play.tooltip.written).to contain "#{Palette::CURSED} cursed"
    end

    # An item whose blessing is not worked out has no mark. The line is the
    # word on its own.
    it "writes the word alone for an unworked-out blessing" do
      run = carrying [sword Blessing::Blessed, known: false]
      run.press "i"

      expect(run.play.tooltip.written).to contain "unknown"
    end

    it "writes the mark and the word for an uncursed item" do
      run = carrying [sword Blessing::Uncursed]
      run.press "i"

      expect(run.play.tooltip.written).to contain "#{Palette::UNCURSED} uncursed"
    end

    # The first line names the item. The blessing has a line of its own.
    it "leaves the blessing out of the name" do
      run = carrying [sword Blessing::Cursed]
      run.press "i"

      expect(run.play.tooltip.written.first).to eq "a short sword"
    end

    it "writes the slot mark and what the slot is" do
      run = carrying [Item.new Kind::ShortSword]
      run.press "w", "a"
      run.press "i"

      expect(run.play.tooltip.written).to contain "#{Palette::MELEE} weapon in hand"
    end
  end
end
