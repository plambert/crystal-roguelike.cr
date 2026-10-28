require "../../spec_helper"

Spectator.describe Roguelike::Ui::ControlSchemePicker do
  alias Picker = Roguelike::Ui::ControlSchemePicker
  alias Options = Roguelike::Options
  alias ControlScheme = Roguelike::Options::ControlScheme
  alias Widgets = TermBuf::Widgets

  def open_picker(columns : Int32 = 80, rows : Int32 = 24,
                  current : ControlScheme? = nil) : {Headless::Session, Picker}
    root = Widgets::Panel.new width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow
    session = Headless.open root, columns: columns, rows: rows
    picker = Picker.new
    picker.show session.app, current
    {session, picker}
  end

  after_each { Options.current = nil }

  it "highlights Modern by default and follows the bootstrap keys" do
    session, picker = open_picker

    expect(picker.selected).to eq ControlScheme::Modern
    session.press "Tab"
    expect(picker.selected).to eq ControlScheme::Traditional
    session.press "Shift+Tab"
    expect(picker.selected).to eq ControlScheme::Modern
    session.press "Left d a Right"
    expect(picker.selected).to eq ControlScheme::Modern
  end

  it "starts with a supplied choice and confirms with f or Enter" do
    session, picker = open_picker current: ControlScheme::Traditional
    choices = [] of ControlScheme?
    picker.on_choose = ->(choice : ControlScheme?) { choices << choice; nil }

    expect(picker.selected).to eq ControlScheme::Traditional
    session.press "d f"
    expect(choices).to eq [ControlScheme::Modern]
    expect(picker.showing?).to be_false

    picker.show session.app, ControlScheme::Traditional
    session.press "Enter"
    expect(choices).to eq [ControlScheme::Modern, ControlScheme::Traditional]
  end

  it "reports cancellation without a choice" do
    session, picker = open_picker current: ControlScheme::Traditional
    choices = [] of ControlScheme?
    picker.on_choose = ->(choice : ControlScheme?) { choices << choice; nil }

    session.press "Escape"

    expect(choices).to eq [nil]
    expect(picker.showing?).to be_false
  end

  it "draws both cards and the comparison at the supported compact sizes" do
    { {40, 16}, {80, 24} }.each do |(columns, rows)|
      session, _picker = open_picker columns, rows
      drawn = session.text

      expect(drawn).to contain "Traditional"
      expect(drawn).to contain "Modern"
      expect(drawn).to contain "Selected"
      expect(drawn).to contain "r all"
      expect(drawn).to contain "Shift+dir walk"
      expect(drawn.lines.any? { |line| line.includes?("y k u") && line.includes?("q w e") })
        .to be_true
      expect(session.rows.all?(&.size.<= columns)).to be_true
    end
  end

  it "refits side-by-side cards after resizing during the modal" do
    session, picker = open_picker 80, 24

    session.resize 40, 16
    picker.refit session.app.tree.screen

    drawn = session.text
    expect(drawn).to contain "Traditional"
    expect(drawn).to contain "Modern"
    expect(drawn.lines.any? { |line| line.includes?("y k u") && line.includes?("q w e") })
      .to be_true
  end

  it "does not persist a choice or mutate the current options" do
    root = Path[File.tempname "roguelike-picker", nil]
    options = Options.new
    options.control_scheme = ControlScheme::Traditional
    Options.current = options
    before = options.to_json
    session, picker = open_picker
    choices = [] of ControlScheme?
    picker.on_choose = ->(choice : ControlScheme?) { choices << choice; nil }

    session.press "d Enter"

    expect(choices).to eq [ControlScheme::Modern]
    expect(options.to_json).to eq before
    expect(Options.current.same? options).to be_true
    expect(File.exists?(Options.path root)).to be_false
  end
end
