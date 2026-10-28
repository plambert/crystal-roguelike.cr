require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Menu do
  alias Widgets = TermBuf::Widgets
  alias Entry = TermBuf::Widgets::Menu::Entry
  alias Navigation = TermBuf::Widgets::Navigation

  record Run,
    menu : Widgets::Menu,
    session : Headless::Session,
    chosen_indices : Array(Int32?),
    chosen_keys : Array(Char?)

  def opened(entries : Array(Entry), max_rows : Int32 = Int32::MAX) : Run
    menu = Widgets::Menu.new
    menu.max_rows = max_rows
    menu.navigation = Navigation.selectable
    chosen_indices = [] of Int32?
    chosen_keys = [] of Char?
    menu.on_choose_index = ->(index : Int32?) { chosen_indices << index; nil }
    menu.on_choose = ->(key : Char?) { chosen_keys << key; nil }

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add menu
    session = Headless.open root, 60, 16
    menu.show session.app, "Items", entries
    session.render

    Run.new menu, session, chosen_indices, chosen_keys
  end

  def entries(count : Int32) : Array(Entry)
    (0...count).map do |index|
      Entry.new Widgets::Menu.letter(index), "item #{index} with a long name"
    end
  end

  it "moves with modern row keys without displaying or answering row shortcuts" do
    run = opened [Entry.new('a', "first"), Entry.new('b', "second")]

    run.session.press "a"
    expect(run.chosen_indices).to be_empty
    expect(run.menu.selected_index).to eq 0
    expect(run.session.rows.join).not_to contain "a - first"

    run.session.press "s"
    expect(run.menu.selected_index).to eq 1
    expect(run.chosen_indices).to be_empty

    run.session.press "f"
    expect(run.chosen_indices).to eq [1]
    expect(run.chosen_keys).to eq ['b']
  end

  it "keeps row marks and slot tails without the shortcut gutter" do
    run = opened [Entry.new('a', "a blessed ring", true, '+', nil, 'R')]
    row = run.session.rows.find(&.includes?("blessed ring")) || ""

    expect(row).to contain "+"
    expect(row).to contain "R"
    expect(row).not_to contain "a -"
  end

  it "uses a and d for pages while retaining arrow navigation" do
    menu = Widgets::Menu.new
    menu.navigation = Navigation.selectable
    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add menu
    session = Headless.open root, 60, 16
    rows = [Entry.new('a', "one")]
    menu.show session.app, "Items", [{"First", rows}, {"Second", rows}], 0

    session.press "a"
    expect(menu.page_name).to eq "Second"
    session.press "d"
    expect(menu.page_name).to eq "First"
    session.press "Right"
    expect(menu.page_name).to eq "Second"
  end

  it "keeps disabled and empty rows unselectable" do
    run = opened [Entry.new('a', "disabled", false), Entry.new('b', "enabled")]

    run.session.press "f"
    expect(run.chosen_indices).to be_empty
    expect(run.menu.showing?).to be_true

    run.session.press "s"
    run.session.press "f"
    expect(run.chosen_indices).to eq [1]

    empty = opened [] of Entry
    empty.session.press "f"
    expect(empty.chosen_indices).to be_empty
    expect(empty.menu.showing?).to be_true
  end

  it "preserves mouse selection with value navigation" do
    run = opened entries(3)
    list = run.menu.list.rect
    run.session.send TermBuf::Events::Mouse.new(
      TermBuf::Input::Mouse::Button::Left, list.x + 1, list.y + 2,
      TermBuf::Modifiers::None,
      TermBuf::Input::Mouse::Action::Press)

    expect(run.chosen_indices).to eq [2]
    expect(run.chosen_keys).to eq ['c']
  end

  it "does not activate a child callback installed by the parent's answer" do
    run = opened [Entry.new('a', "parent")]
    child_indices = [] of Int32?
    run.menu.on_choose_index = nil
    run.menu.on_choose = ->(key : Char?) do
      if key
        run.menu.on_choose = nil
        run.menu.on_choose_index = ->(index : Int32?) { child_indices << index; nil }
        run.menu.show run.session.app, "Child", [Entry.new('b', "child")]
      end
      nil
    end

    run.session.press "f"

    expect(run.menu.showing?).to be_true
    expect(run.menu.title).to eq "Child"
    expect(child_indices).to be_empty
    run.session.press "f"
    expect(child_indices).to eq [0]
  end

  it "rebinds a showing menu without losing page, row, or scroll" do
    menu = Widgets::Menu.new
    menu.max_rows = 2
    menu.navigation = Navigation.selectable
    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add menu
    session = Headless.open root, 60, 16
    rows = entries(12)
    pages = [{"First", rows}, {"Second", rows}]
    menu.show session.app, "Items", pages, 1
    menu.select_index 7
    menu.scroll_by 2

    selected = menu.selected_index
    vertical_scroll = menu.list.scroll_y
    horizontal_scroll = menu.offset
    page_name = menu.page_name
    menu.navigation = Navigation.new(
      previous_row: TermBuf::Key.parse("k"),
      next_row: TermBuf::Key.parse("j"),
      previous_tab: TermBuf::Key.parse("Left"),
      next_tab: TermBuf::Key.parse("Right"),
      row_shortcuts: false,
      display_shortcuts: false)

    expect(menu.selected_index).to eq selected
    expect(menu.list.scroll_y).to eq vertical_scroll
    expect(menu.offset).to eq horizontal_scroll
    expect(menu.page_name).to eq page_name

    session.press "s"
    expect(menu.selected_index).to eq selected
    session.press "j"
    expect(menu.selected_index).to eq 8
  end
end
