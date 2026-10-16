require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Section do
  alias Widgets = TermBuf::Widgets

  # A section of *count* one-row labels, ten columns wide, drawn on a screen
  # six rows tall. Answers the section and the session it is drawn in.
  def drawn(count : Int32 = 3) : {Widgets::Section, Headless::Session}
    section = Widgets::Section.new "Pack"
    count.times { |index| section.body.add Widgets::Label.new("row #{index}") }

    column = Widgets::Panel.new width: Widgets::Layout::Sizing.fixed(10),
      height: Widgets::Layout::Sizing.grow
    column.add section

    session = Headless.open column, 10, 6
    session.render
    {section, session}
  end

  # A press of the left button at *x*, *y*.
  def press(x : Int32, y : Int32) : TermBuf::Events::Mouse
    TermBuf::Events::Mouse.new(
      TermBuf::Input::Mouse::Button::Left, x, y,
      TermBuf::Modifiers::None,
      TermBuf::Input::Mouse::Action::Press)
  end

  it "draws the header over its rows" do
    _, session = drawn

    expect(session.row(0).rstrip).to eq " ▼ Pack"
    expect(session.row(1).rstrip).to eq "row 0"
    expect(session.row(3).rstrip).to eq "row 2"
  end

  it "paints the header across the whole width" do
    section, session = drawn

    10.times do |column|
      found = session.buffer.hit(column, 0) || raise "nothing drawn at #{column},0"
      expect(session.buffer.styles[found.cell.style].attributes.reverse?).to be_true
    end
    expect(section.header.rect.width).to eq 10
  end

  it "hides its rows and shows its summary when collapsed" do
    section, session = drawn
    section.summary = "3"
    section.expanded = false
    session.render

    expect(session.row(0)).to eq " ▶ Pack 3"
    expect(session.row(1).strip).to be_empty
    expect(section.rows).to be_empty
    expect(section.header.text).to eq "▶ Pack 3"
  end

  it "cuts a summary too long for the row and keeps the title" do
    section, session = drawn
    section.summary = "a great many"
    section.expanded = false
    session.render

    expect(session.row(0)).to eq " ▶ Pack …"
  end

  it "asks the summary hook each time the header is drawn" do
    section, session = drawn
    count = 0
    section.summarize = -> { count += 1; count.to_s }
    section.expanded = false
    session.render

    expect(section.summary).to eq "2"
  end

  it "leaves the summary off while expanded" do
    section, session = drawn
    section.summary = "3"
    session.render

    expect(session.row(0).rstrip).to eq " ▼ Pack"
    expect(section.header.text).to eq "▼ Pack"
  end

  it "toggles on a press of its header and says so" do
    section, session = drawn
    heard = [] of Bool
    section.on_toggle = ->(found : Widgets::Section) { heard << found.expanded?; nil }

    session.send press(3, 0)
    session.send press(3, 0)

    expect(heard).to eq [false, true]
  end

  it "does not toggle on a press of a row" do
    section, session = drawn

    session.send press(3, 1)

    expect(section.expanded?).to be_true
  end

  it "tells the pointer hook when the pointer crosses the header" do
    section, session = drawn
    count = 0
    section.on_point = -> { count += 1; nil }

    session.send TermBuf::Events::Mouse.new(
      TermBuf::Input::Mouse::Button::None, 3, 0,
      TermBuf::Modifiers::None,
      TermBuf::Input::Mouse::Action::Motion)

    expect(count).to eq 1
  end

  it "answers the rows a selection would move among" do
    section, _ = drawn
    section.body.children[1].hidden = true

    expect(section.rows.size).to eq 2
  end

  it "never takes the keyboard" do
    section, _ = drawn

    expect(section.focusable?).to be_false
    expect(section.header.focusable?).to be_false
  end
end
