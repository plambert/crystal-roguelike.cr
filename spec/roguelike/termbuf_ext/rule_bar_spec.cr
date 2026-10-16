require "../../spec_helper"

Spectator.describe TermBuf::Widgets::RuleBar do
  alias Widgets = TermBuf::Widgets

  # A window two columns wide with *count* one-row labels in it, and the bar
  # beside it. Answers the bar's column, top to bottom, on a screen of
  # *rows*.
  def drawn(count : Int32, rows : Int32 = 4, scroll : Int32 = 0) : String
    window = Widgets::Scrollable.new width: Widgets::Layout::Sizing.fixed(2)
    count.times { |index| window.add Widgets::Label.new(index.to_s) }

    row = Widgets::Panel.new direction: Widgets::Layout::Direction::Row,
      width: Widgets::Layout::Sizing.grow, height: Widgets::Layout::Sizing.grow
    row.add window, Widgets::RuleBar.new(window)

    session = Headless.open row, 3, rows
    session.render
    window.scroll_by dy: scroll
    session.rows.map { |line| line[2]? || ' ' }.join
  end

  it "draws a plain rule while everything fits" do
    expect(drawn 3).to eq "││││"
  end

  it "draws a plain rule when the content just fills the window" do
    expect(drawn 4).to eq "││││"
  end

  it "puts a thumb on the rule once the content outgrows the window" do
    expect(drawn 8).to eq "██││"
  end

  it "moves the thumb with the scroll" do
    expect(drawn 8, scroll: 4).to eq "││██"
  end

  it "draws a rule with nothing attached" do
    bar = Widgets::RuleBar.new
    expect(bar.fits?).to be_true
  end
end
