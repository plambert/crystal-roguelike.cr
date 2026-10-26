require "../spec_helper"

private class DisplayProbe
  property? mousing : Bool = true
  property? flickering : Bool = true
end

Spectator.describe "replay display preferences" do
  alias Options = Roguelike::Options
  alias Meter = Roguelike::Ui::Meter
  alias Palette = Roguelike::Ui::Palette
  alias Session = Roguelike::Session
  alias Theme = Roguelike::Ui::Theme
  alias Watching = Roguelike::Cli::Watching

  let(root) do
    Path[File.tempname "roguelike-replay-display", nil].tap do |made|
      Dir.mkdir_p made
      at_exit { FileUtils.rm_rf made.to_s }
    end
  end

  after_each do
    Options.current = nil
    Roguelike::Ui::Motion.on = true
    Theme.current = Theme::DEFAULT
    Palette.rebuild
  end

  it "loads saved theme and display settings before drawing" do
    options_file = %({"motion":false,"flicker":false,"mouse":false,"bar_color":"bands"})
    theme_file = %({"granite":"#010203"})
    File.write Options.path(root), options_file
    File.write Theme.path(root), theme_file
    options = Watching.parse(%w[recording.jsonl]).display_options(root)

    found = Session.display_preferences(root)

    expect(found).to be options
    expect(Roguelike::Ui::Motion.on?).to be_false
    expect(Theme.current.granite).to eq TermBuf::Color.rgb(0x01, 0x02, 0x03)
    expect(Palette.table.theme.granite).to eq TermBuf::Color.rgb(0x01, 0x02, 0x03)
    expect(options.flicker?).to be_false
    expect(options.mouse?).to be_false
    expect(options.bar_color).to eq Options::BarColor::Bands

    display = DisplayProbe.new
    options.apply_to display
    expect(display.mousing?).to be_false
    expect(display.flickering?).to be_false
    meter = Meter.new("HP", 90, 100, Palette.health)
    expect(meter.fill).to eq Palette.meter(Palette.health, 90, banded: true)
    expect(Dir.children(root).sort).to eq %w[options.json theme.json]
    expect(File.read(Options.path(root))).to eq options_file
    expect(File.read(Theme.path(root))).to eq theme_file
  end

  it "honors explicitly enabled flags without changing the saved values" do
    contents = %({"motion":false,"flicker":false})
    File.write Options.path(root), contents

    options = Watching.parse(%w[--motion --flicker recording.jsonl]).display_options(root)
    Session.display_preferences(root)

    expect(options.motion?).to be_true
    expect(options.flicker?).to be_true
    expect(options.overridden?("motion")).to be_true
    expect(options.overridden?("flicker")).to be_true
    expect(Roguelike::Ui::Motion.on?).to be_true
    expect(File.read(Options.path(root))).to eq contents
  end

  it "honors explicitly disabled flags without changing the saved values" do
    contents = %({"motion":true,"flicker":true})
    File.write Options.path(root), contents

    options = Watching.parse(%w[--no-motion --no-flicker recording.jsonl]).display_options(root)
    Session.display_preferences(root)

    expect(options.motion?).to be_false
    expect(options.flicker?).to be_false
    expect(options.overridden?("motion")).to be_true
    expect(options.overridden?("flicker")).to be_true
    expect(Roguelike::Ui::Motion.on?).to be_false
    expect(File.read(Options.path(root))).to eq contents
  end

  it "uses the usual defaults for missing and corrupt preference files" do
    options = Watching.parse(%w[recording.jsonl]).display_options(root)
    Session.display_preferences(root)

    expect(options.motion?).to be_true
    expect(options.flicker?).to be_true
    expect(options.mouse?).to be_true
    expect(options.bar_color).to eq Options::BarColor::Gradient
    expect(Theme.current).to eq Theme::DEFAULT
    expect(Dir.children(root)).to be_empty

    File.write Options.path(root), "{ not json"
    File.write Theme.path(root), %({"granite":"not-a-color"})
    options = Watching.parse(%w[recording.jsonl]).display_options(root)
    Session.display_preferences(root)

    expect(options.motion?).to be_true
    expect(options.flicker?).to be_true
    expect(options.mouse?).to be_true
    expect(options.bar_color).to eq Options::BarColor::Gradient
    expect(Theme.current).to eq Theme::DEFAULT
    expect(File.read(Options.path(root))).to eq "{ not json"
    expect(File.read(Theme.path(root))).to eq %({"granite":"not-a-color"})
  end
end
