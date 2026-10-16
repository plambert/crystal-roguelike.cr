require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Tint do
  alias Widgets = TermBuf::Widgets
  alias Color = TermBuf::Color

  FROM = Color.rgb 0x00, 0x00, 0x80
  TO   = Color.rgb 0x20, 0x20, 0x20

  # A panel in an application with a clock the spec fires by hand.
  def clocked : {Widgets::Panel, Headless::Session}
    panel = Widgets::Panel.new width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow
    session = Headless.open panel, 4, 2
    session.clock
    {panel, session}
  end

  it "takes the end color at once without animation" do
    panel, session = clocked
    tint = described_class.new FROM, TO

    tint.apply panel, session.app, animate: false

    expect(panel.style.try &.background).to eq TO
    expect(session.armed).to be_empty
  end

  it "steps from the start color to the end color on timers" do
    panel, session = clocked
    tint = described_class.new FROM, TO, steps: 5

    tint.apply panel, session.app, animate: true
    expect(panel.style.try &.background).to eq FROM

    seen = [] of Color?
    while session.tick
      seen << panel.style.try &.background
    end

    expect(seen.size).to eq 4
    expect(seen.last).to eq TO
    expect(tint.settled?).to be_true
  end

  it "settles at once on an application with no clock" do
    panel = Widgets::Panel.new
    session = Headless.open panel, 4, 2
    tint = described_class.new FROM, TO

    tint.apply panel, session.app, animate: true

    expect(panel.style.try &.background).to eq TO
  end

  it "puts back the style a widget had when it moves to another" do
    first, session = clocked
    second = Widgets::Panel.new
    first.style = TermBuf::Style::DEFAULT.fg(Color.rgb 0xFF, 0xFF, 0xFF)
    tint = described_class.new FROM, TO

    tint.apply first, session.app, animate: true
    tint.apply second, session.app, animate: false

    expect(first.style).to eq TermBuf::Style::DEFAULT.fg(Color.rgb 0xFF, 0xFF, 0xFF)
    expect(second.style.try &.background).to eq TO
    expect(session.armed).to be_empty
  end

  it "keeps a foreground the widget had under the tint" do
    panel, session = clocked
    panel.style = TermBuf::Style::DEFAULT.fg(Color.rgb 0xFF, 0xFF, 0xFF)
    tint = described_class.new FROM, TO

    tint.apply panel, session.app, animate: false

    expect(panel.style.try &.foreground).to eq Color.rgb(0xFF, 0xFF, 0xFF)
    expect(panel.style.try &.background).to eq TO
  end

  it "takes the tint off on clear" do
    panel, session = clocked
    tint = described_class.new FROM, TO

    tint.apply panel, session.app, animate: true
    tint.clear

    expect(panel.style).to be_nil
    expect(tint.target).to be_nil
    expect(session.armed).to be_empty
  end
end
