require "../../spec_helper"

record ItemValue, index : Int32

Spectator.describe TermBuf::Widgets::ValueMenu do
  alias Widgets = TermBuf::Widgets
  alias ItemEntry = TermBuf::Widgets::ValueMenu::Entry(ItemValue)

  it "chooses typed values past the legacy letter range" do
    menu = Widgets::ValueMenu(ItemValue).new
    chosen = [] of ItemValue
    highlighted = [] of ItemValue?
    menu.on_choose = ->(value : ItemValue) { chosen << value; nil }
    menu.on_highlight = ->(value : ItemValue?) { highlighted << value; nil }

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add menu.menu
    session = Headless.open root, 70, 20
    entries = (0...70).map do |index|
      ItemEntry.new ItemValue.new(index), "floor item #{index}"
    end
    menu.show session.app, "Floor", entries
    menu.select_index 69
    expect(highlighted).to eq [ItemValue.new(0), ItemValue.new(69)]

    session.press "a"
    expect(menu.selected_index).to eq 69
    expect(chosen).to be_empty

    session.press "f"
    expect(chosen).to eq [ItemValue.new(69)]
  end

  it "returns the chosen value from the active page" do
    menu = Widgets::ValueMenu(ItemValue).new
    chosen = [] of ItemValue
    menu.on_choose = ->(value : ItemValue) { chosen << value; nil }

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add menu.menu
    session = Headless.open root, 70, 20
    first = [ItemEntry.new(ItemValue.new(1), "first")]
    second = [ItemEntry.new(ItemValue.new(2), "second")]
    menu.show session.app, "Floor", [{"One", first}, {"Two", second}], 0

    session.press "d"
    session.press "f"

    expect(chosen).to eq [ItemValue.new(2)]
  end

  it "supports optional shortcuts, disabled reasons, and a separate back result" do
    menu = Widgets::ValueMenu(ItemValue).new
    menu.navigation = Widgets::Navigation.new(
      row_shortcuts: true, display_shortcuts: true)
    chosen = [] of ItemValue
    backs = 0
    menu.on_choose = ->(value : ItemValue) { chosen << value; nil }
    menu.on_back = -> { backs += 1; nil }

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add menu.menu
    session = Headless.open root, 70, 20
    entries = [
      ItemEntry.new(ItemValue.new(1), "blocked", false, disabled_reason: "not available"),
      ItemEntry.new(ItemValue.new(2), "usable", shortcut: 'x'),
    ]
    menu.show session.app, "Choices", entries

    expect(menu.menu.entries[0].disabled_reason).to eq "not available"
    session.press "x"
    expect(chosen).to eq [ItemValue.new(2)]
    expect(backs).to eq 0

    menu.show session.app, "Choices", entries
    session.press "Escape"
    expect(backs).to eq 1
  end
end
