require "../../spec_helper"

Spectator.describe TermBuf::Widgets::ListEditor do
  alias Widgets = TermBuf::Widgets

  # A list editor in a panel, over a buffer, with what it reported.
  record Shown,
    editor : Widgets::ListEditor(String),
    session : Headless::Session,
    changes : Array(Array(String)),
    edits : Array({Int32, String}),
    overruns : Array(Int32)

  def shown(items : Array(String), columns : Int32 = 30, rows : Int32 = 8) : Shown
    editor = Widgets::ListEditor(String).new items
    changes = [] of Array(String)
    edits = [] of {Int32, String}
    overruns = [] of Int32
    made = 0
    editor.on_new = -> { made += 1; "new #{made}".as(String?) }
    editor.on_change = ->(now : Array(String)) { changes << now; nil }
    editor.on_edit = ->(index : Int32, item : String) { edits << {index, item}; nil }
    editor.on_overrun = ->(step : Int32) { overruns << step; nil }

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add editor

    session = Headless.open root, columns, rows
    editor.focus session.app
    session.render

    Shown.new editor, session, changes, edits, overruns
  end

  def rows(run : Shown) : Array(String)
    run.session.render
    run.session.rows.map(&.rstrip).reject(&.empty?)
  end

  # Whether the cell at *x*, *y* of the screen is drawn reversed.
  def reversed?(run : Shown, x : Int32, y : Int32) : Bool
    run.session.render
    found = run.session.buffer.hit x, y
    return false unless found

    style = run.session.buffer.styles[found.cell.style]
    style.attributes.includes? TermBuf::Attributes::Reverse
  end

  it "numbers its rows in order" do
    run = shown ["bread", "cheese", "wine"]

    expect(rows run).to eq ["1. bread", "2. cheese", "3. wine"]
  end

  it "draws what the tail gives against the right edge" do
    run = shown ["bread", "cheese"], columns: 20
    run.editor.tail = ->(item : String) { item.size.to_s }

    expect(rows(run).first).to eq "1. bread           5"
  end

  it "cuts a row that does not fit and keeps the tail" do
    run = shown ["a very long row of words"], columns: 16
    run.editor.tail = ->(_item : String) { "take" }

    expect(rows(run).first).to eq "1. a very … take"
  end

  it "highlights the row with the keyboard, and moves the highlight" do
    run = shown ["bread", "cheese", "wine"]

    expect(reversed? run, 0, 0).to be_true
    run.session.press "Down"
    expect(reversed? run, 0, 0).to be_false
    expect(reversed? run, 0, 1).to be_true
    expect(run.editor.current).to eq "cheese"
  end

  it "reports going past either end, and stays where it was" do
    run = shown ["bread", "cheese"]
    run.session.press "Up"
    run.session.press "Down"
    run.session.press "Down"

    expect(run.overruns).to eq [-1, 1]
    expect(run.editor.selected).to eq 1
  end

  it "adds a row after the highlight, highlights it and hands it over to edit" do
    run = shown ["bread", "cheese"]
    run.session.press "+"

    expect(run.editor.items).to eq ["bread", "new 1", "cheese"]
    expect(run.editor.selected).to eq 1
    expect(run.changes.last).to eq ["bread", "new 1", "cheese"]
    expect(run.edits).to eq [{1, "new 1"}]
  end

  it "adds the first row of an empty list" do
    run = shown [] of String

    expect(rows run).to eq [Widgets::ListEditor::EMPTY]
    run.session.press "Insert"
    expect(rows run).to eq ["1. new 1"]
  end

  it "adds nothing past its limit" do
    run = shown ["bread"]
    run.editor.limit = 1
    run.session.press "+"

    expect(run.editor.items).to eq ["bread"]
    expect(run.changes).to be_empty
  end

  it "removes the highlighted row" do
    run = shown ["bread", "cheese", "wine"]
    run.session.press "End"
    run.session.press "-"

    expect(run.editor.items).to eq ["bread", "cheese"]
    expect(run.editor.selected).to eq 1
    run.session.press "Delete"
    run.session.press "Backspace"
    run.session.press "Backspace"
    expect(run.editor.items).to be_empty
    expect(run.changes.size).to eq 3
  end

  it "moves the highlighted row up and down, and the highlight with it" do
    run = shown ["bread", "cheese", "wine"]
    run.session.press "]"

    expect(run.editor.items).to eq ["cheese", "bread", "wine"]
    expect(run.editor.selected).to eq 1
    run.session.press "]"
    run.session.press "]"
    expect(run.editor.items).to eq ["cheese", "wine", "bread"]
    run.session.press "["
    expect(run.editor.items).to eq ["cheese", "bread", "wine"]
    expect(run.changes.size).to eq 3
  end

  it "hands the highlighted row over on Enter and Space" do
    run = shown ["bread", "cheese"]
    run.session.press "Down"
    run.session.press "Enter"
    run.session.press "Space"

    expect(run.edits).to eq [{1, "cheese"}, {1, "cheese"}]
  end

  it "puts an edited row back and reports it" do
    run = shown ["bread", "cheese"]
    run.editor.replace 1, "butter"
    run.editor.replace 1, "butter"

    expect(rows run).to eq ["1. bread", "2. butter"]
    expect(run.changes).to eq [["bread", "butter"]]
  end

  it "takes new rows whole without reporting them" do
    run = shown ["bread", "cheese", "wine"]
    run.session.press "End"
    run.editor.items = ["milk"]

    expect(rows run).to eq ["1. milk"]
    expect(run.editor.selected).to eq 0
    expect(run.changes).to be_empty
  end

  it "scrolls to keep the highlight in view" do
    run = shown (1..12).map { |number| "row #{number}" }, rows: 4
    run.session.press "End"

    expect(rows(run).last).to eq "12. row 12"
  end
end
