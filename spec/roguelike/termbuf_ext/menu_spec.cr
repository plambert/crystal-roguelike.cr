require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Menu do
  alias Widgets = TermBuf::Widgets
  alias Entry = TermBuf::Widgets::Menu::Entry

  # A menu in a panel, over a buffer, with the choices it was given.
  record Shown,
    menu : Widgets::Menu,
    session : Headless::Session,
    chosen : Array(Char?)

  # The rows of the box, without the border around them.
  def rows(run : Shown) : Array(String)
    run.session.rows
      .select(&.includes?('│'))
      .map { |line| line.split('│')[1] }
  end

  # How wide the box is drawn, border included.
  def box_width(run : Shown) : Int32
    line = run.session.rows.find(&.includes?('│')) || ""
    first = line.index('│') || 0
    last = line.rindex('│') || 0

    last - first + 1
  end

  # How many rows the box takes, border included.
  def box_height(run : Shown) : Int32
    run.session.rows.count { |line| line.includes?('│') || line.includes?('╭') || line.includes?('╰') }
  end

  def shown(texts : Array(String), columns : Int32 = 60, rows : Int32 = 20,
            title : String? = "Inventory",
            disabled : Array(Int32) = [] of Int32) : Shown
    menu = Widgets::Menu.new
    chosen = [] of Char?
    menu.on_choose = ->(key : Char?) { chosen << key; nil }

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add menu

    session = Headless.open root, columns, rows
    entries = texts.each_with_index.map do |text, index|
      Entry.new Widgets::Menu.letter(index), text, !disabled.includes?(index)
    end

    menu.show session.app, title, entries
    session.render

    Shown.new menu, session, chosen
  end

  # A menu drawn twice. The first frame goes down before the list has the
  # keyboard, and a list without it draws no highlight.
  def lit(texts : Array(String)) : Shown
    run = shown texts
    run.session.render
    run
  end

  # Whether the cell at *x*, *y* of the screen is drawn reversed.
  def reversed?(run : Shown, x : Int32, y : Int32) : Bool
    found = run.session.buffer.hit x, y
    raise "nothing is drawn at #{x},#{y}" unless found

    style = run.session.buffer.styles[found.cell.style]
    style.attributes.includes? TermBuf::Attributes::Reverse
  end

  # One row of the box with the padding cell inside the border taken off, so
  # the first character answered is the first character of the row.
  def row(run : Shown, index : Int32) : String
    rows(run)[index].lchop
  end

  # Where the first row's own first cell is on the screen, and which screen
  # row it is. Past the left border and the padding cell inside it.
  def first_row(run : Shown) : {Int32, Int32}
    run.session.rows.each_with_index do |line, row|
      found = line.index '│'
      return {found + 2, row} if found
    end

    raise "the box is not on the screen"
  end

  describe "the marks on the highlighted row" do
    it "puts the pointer at the near edge" do
      run = lit ["a torch", "a dagger"]

      expect(row(run, 0)).to start_with "\u27EA a"
    end

    it "leaves the other rows unmarked" do
      run = lit ["a torch", "a dagger"]

      expect(row(run, 1)).to start_with "  b"
    end

    it "puts the facing mark at the far edge" do
      run = lit ["a torch", "a dagger"]

      expect(row(run, 0).rstrip).to end_with "\u27EB"
    end

    it "moves both with the highlight" do
      run = lit ["a torch", "a dagger"]
      run.menu.list.select 1
      run.session.render

      expect(row(run, 0)).to start_with "  a"
      expect(row(run, 1)).to start_with "\u27EA b"
    end
  end

  # The gutter carries the key and the mark, and the mark says what it says
  # in its colour. Reversing it would invert that colour.
  describe "what the highlight covers" do
    it "covers the text" do
      run = lit ["a torch"]
      x, y = first_row run

      expect(reversed?(run, x + Widgets::Menu::GUTTER, y)).to be_true
    end

    it "leaves the key alone" do
      run = lit ["a torch"]
      x, y = first_row run

      expect(reversed?(run, x + Widgets::Menu::KEY, y)).to be_false
    end

    it "leaves the mark alone" do
      run = lit ["a torch"]
      x, y = first_row run

      expect(reversed?(run, x + Widgets::Menu::MARK, y)).to be_false
    end

    it "leaves the space between the mark and the text alone" do
      run = lit ["a torch"]
      x, y = first_row run

      expect(reversed?(run, x + Widgets::Menu::GUTTER - 1, y)).to be_false
    end
  end

  describe "the width of the box" do
    it "grows to hold its widest row" do
      run = shown ["a torch", "a blessed masterwork +3 chain mail"], columns: 80

      expect(rows(run)[0]).to contain "a - a torch"
      expect(rows(run)[1]).to contain "b - a blessed masterwork +3 chain mail"
    end

    it "is as wide as the widest row and no wider" do
      short = shown ["one"]
      long = shown ["one", "a blessed masterwork +3 chain mail"]

      expect(box_width(long)).to be > box_width(short)
    end

    # A person reading a list of one short word does not want a box across
    # the whole screen.
    it "never goes below its own minimum" do
      run = shown ["x"]

      expect(box_width(run)).to eq Widgets::Menu::MINIMUM_WIDTH
    end

    it "leaves the side margin clear" do
      run = shown ["a name far longer than this narrow terminal is wide"],
        columns: 50

      expect(box_width(run)).to eq 50 - 2 * run.menu.column_margin
    end

    it "is wide enough for its own title" do
      run = shown ["x"], title: "A title longer than any of the rows"

      expect(box_width(run)).to be >= "A title longer than any of the rows".size
    end
  end

  describe "the height of the box" do
    it "grows to hold every row" do
      run = shown (1..6).map { |number| "row #{number}" }

      expect(box_height(run)).to eq 8
    end

    it "leaves the row margin clear" do
      run = shown (1..40).map { |number| "row #{number}" }, rows: 20

      expect(box_height(run)).to eq 20 - 2 * run.menu.row_margin
    end

    it "stops at max_rows when a caller sets one" do
      menu = Widgets::Menu.new
      menu.max_rows = 3

      root = Widgets::Panel.new(
        width: Widgets::Layout::Sizing.grow,
        height: Widgets::Layout::Sizing.grow)
      root.add menu

      session = Headless.open root, 60, 30
      entries = (1..20).map { |number| Entry.new Widgets::Menu.letter(number), "row #{number}" }
      menu.show session.app, "Inventory", entries
      session.render

      expect(session.rows.count(&.includes?('│'))).to eq 3
    end
  end

  describe "scrolling sideways" do
    # Ten cells each side of a fifty column terminal leaves thirty for the
    # box, which is twenty six for the rows once the border and the padding
    # have theirs.
    WIDE = "a blessed masterwork +3 chain mail"

    def cut : Shown
      shown [WIDE], columns: 50
    end

    it "does not scroll while everything fits" do
      run = shown [WIDE], columns: 120

      expect(run.menu.hidden).to eq 0

      run.menu.scroll_by 5
      expect(run.menu.offset).to eq 0
    end

    it "knows how much is past the edge" do
      expect(cut.menu.hidden).to be > 0
    end

    it "moves the rows sideways" do
      run = cut
      run.menu.scroll_by 4
      run.session.render

      expect(rows(run)[0]).to contain "essed masterwork"
    end

    it "leaves the key where it was" do
      run = cut
      run.menu.scroll_by 4
      run.session.render

      expect(rows(run)[0].lstrip).to start_with "\u27EA a - "
    end

    it "stops at the end of the widest row" do
      run = cut
      run.menu.scroll_by 999

      expect(run.menu.offset).to eq run.menu.hidden
    end

    it "stops at the start going back" do
      run = cut
      run.menu.scroll_by(-999)

      expect(run.menu.offset).to eq 0
    end

    it "moves on the arrow keys" do
      run = cut
      run.session.press "Right"
      run.session.press "Right"

      expect(run.menu.offset).to eq 2

      run.session.press "Left"
      expect(run.menu.offset).to eq 1
    end

    it "starts each menu back at the left" do
      run = cut
      run.menu.scroll_by 6
      run.menu.show run.session.app, "Inventory", [Entry.new('a', WIDE)]

      expect(run.menu.offset).to eq 0
    end
  end

  describe "a screen that changed size" do
    it "sizes the box again" do
      run = shown ["a blessed masterwork +3 chain mail"], columns: 100
      wide = box_width run

      run.session.resize 50, 20
      run.menu.refit TermBuf::Rect.new(0, 0, 50, 20), run.session.app.tree.policy
      run.session.render

      expect(box_width(run)).to be < wide
      expect(box_width(run)).to eq 50 - 2 * run.menu.column_margin
    end

    it "brings a scrolled row back into the box" do
      run = shown ["a blessed masterwork +3 chain mail"], columns: 50
      run.menu.scroll_by 999
      far = run.menu.offset

      run.session.resize 120, 20
      run.menu.refit TermBuf::Rect.new(0, 0, 120, 20), run.session.app.tree.policy
      run.session.render

      expect(far).to be > 0
      expect(run.menu.offset).to eq 0
    end
  end

  describe "the highlight" do
    # A caller hangs a box of detail off this, and the box has to be up the
    # moment the menu is.
    it "is reported when the menu goes up" do
      seen = [] of String?
      menu = Widgets::Menu.new
      menu.on_highlight = ->(entry : Entry?) { seen << entry.try(&.text); nil }

      root = Widgets::Panel.new(
        width: Widgets::Layout::Sizing.grow,
        height: Widgets::Layout::Sizing.grow)
      root.add menu
      session = Headless.open root, 60, 20
      menu.show session.app, "Inventory",
        [Entry.new('a', "one"), Entry.new('b', "two")]

      expect(seen).to eq ["one"]
    end

    it "is reported as the arrows move it" do
      seen = [] of String?
      run = shown ["one", "two", "three"]
      run.menu.on_highlight = ->(entry : Entry?) { seen << entry.try(&.text); nil }

      run.session.press "Down"
      run.session.press "Down"
      run.session.press "Up"

      expect(seen).to eq ["two", "three", "two"]
    end

    it "is not reported when it stays where it is" do
      seen = [] of String?
      run = shown ["one", "two"]
      run.menu.on_highlight = ->(entry : Entry?) { seen << entry.try(&.text); nil }

      run.session.press "Up"

      expect(seen).to be_empty
    end

    # A row is not a widget, so the row under the pointer is worked out from
    # how far down the list the report landed.
    it "follows the pointer across the rows" do
      run = shown ["one", "two", "three"]
      list = run.menu.list.rect

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::None, list.x + 1, list.y + 2,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Motion)

      expect(run.menu.list.selected).to eq 2
    end

    # The pointer moves the highlight and the button picks what it is on, so
    # a click does what typing that row's letter does.
    it "picks the row a button goes down on" do
      run = shown ["one", "two", "three"]
      list = run.menu.list.rect

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, list.x + 1, list.y + 2,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)

      expect(run.chosen).to eq ['c']
      expect(run.menu.showing?).to be_false
    end

    it "picks nothing when the button goes down past the rows" do
      run = shown ["one", "two"]
      list = run.menu.list.rect

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, list.x + 1, list.y + 5,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)

      expect(run.chosen).to be_empty
      expect(run.menu.showing?).to be_true
    end

    it "picks nothing on a row that cannot be picked" do
      run = shown ["one", "two"], disabled: [1]
      list = run.menu.list.rect

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, list.x + 1, list.y + 1,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)

      expect(run.chosen).to be_empty
      expect(run.menu.showing?).to be_true
    end

    # A release is not a second answer to a press, and the other buttons mean
    # nothing on a row.
    it "picks nothing when the button comes back up" do
      run = shown ["one", "two"]
      list = run.menu.list.rect

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, list.x + 1, list.y + 1,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Release)

      expect(run.chosen).to be_empty
      expect(run.menu.showing?).to be_true
    end

    it "picks nothing on the right button" do
      run = shown ["one", "two"]
      list = run.menu.list.rect

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Right, list.x + 1, list.y + 1,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)

      expect(run.chosen).to be_empty
      expect(run.menu.showing?).to be_true
    end
  end

  describe "picking a row" do
    it "answers the letter pressed" do
      run = shown ["one", "two"]
      run.session.press "b"

      expect(run.chosen).to eq ['b']
    end

    it "answers nothing on Escape" do
      run = shown ["one", "two"]
      run.session.press "Escape"

      expect(run.chosen).to eq [nil]
    end
  end
end
