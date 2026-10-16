require "../../spec_helper"

Spectator.describe TermBuf::Widgets::EasedScroll do
  alias Widgets = TermBuf::Widgets

  # A scroll over a plain offset, in an application with a clock the spec
  # fires by hand.
  class Slate
    property at : {Int32, Int32} = {0, 0}
    getter writes = [] of {Int32, Int32}
    property limit : {Int32, Int32} = {20, 40}

    def scroll : Widgets::EasedScroll
      Widgets::EasedScroll.new(
        -> { @at },
        ->(x : Int32, y : Int32) { @at = {x, y}; @writes << @at; nil },
        -> { @limit })
    end
  end

  def clocked : Headless::Session
    session = Headless.open Widgets::Panel.new, 4, 2
    session.clock
    session
  end

  it "writes the goal once without animation" do
    slate = Slate.new
    session = clocked
    glide = slate.scroll

    glide.to 0, 8, session.app, animate: false

    expect(slate.writes).to eq [{0, 8}]
    expect(session.armed).to be_empty
    expect(glide.running?).to be_false
  end

  it "writes the goal once on an application with no clock" do
    slate = Slate.new
    session = Headless.open Widgets::Panel.new, 4, 2
    glide = slate.scroll

    glide.to 0, 8, session.app, animate: true

    expect(slate.writes).to eq [{0, 8}]
    expect(glide.running?).to be_false
  end

  it "steps to the goal on timers, slowing as it arrives" do
    slate = Slate.new
    session = clocked
    glide = slate.scroll

    glide.to 0, 20, session.app, animate: true
    expect(slate.writes.size).to eq 1
    expect(glide.running?).to be_true

    fired = session.run_timers

    expect(fired).to eq 4
    expect(slate.writes.map(&.[1])).to eq [10, 16, 19, 20, 20]
    expect(slate.at).to eq({0, 20})
    expect(glide.running?).to be_false
  end

  it "moves both axes along one line" do
    slate = Slate.new
    session = clocked
    glide = slate.scroll

    glide.to 10, 20, session.app, animate: true
    session.run_timers

    expect(slate.writes.map(&.[0])).to eq [5, 8, 9, 10, 10]
    expect(slate.at).to eq({10, 20})
  end

  it "holds the goal inside the limits" do
    slate = Slate.new
    glide = slate.scroll

    glide.to 99, -4, clocked.app, animate: false
    expect(slate.at).to eq({20, 0})

    expect(glide.clamp(-1, 99)).to eq({0, 40})
  end

  it "adds to the goal of a scroll that runs" do
    slate = Slate.new
    session = clocked
    glide = slate.scroll

    glide.by 0, 10, session.app, animate: true
    session.tick
    glide.by 0, 10, session.app, animate: true

    expect(glide.goal).to eq({0, 20})
    session.run_timers
    expect(slate.at).to eq({0, 20})
  end

  it "begins a new scroll from where the offset is" do
    slate = Slate.new
    session = clocked
    glide = slate.scroll

    glide.to 0, 20, session.app, animate: true
    session.tick
    here = slate.at[1]
    glide.to 0, 0, session.app, animate: true

    expect(slate.at[1]).to be < here
    expect(session.armed.size).to eq 1
  end

  it "stops when someone else moves the offset" do
    slate = Slate.new
    session = clocked
    glide = slate.scroll

    glide.to 0, 20, session.app, animate: true
    slate.at = {0, 3}
    session.tick

    expect(slate.at).to eq({0, 3})
    expect(glide.running?).to be_false
    expect(session.armed).to be_empty
  end

  it "puts the offset on the goal at once when finished" do
    slate = Slate.new
    session = clocked
    glide = slate.scroll

    glide.to 0, 20, session.app, animate: true
    glide.finish

    expect(slate.at).to eq({0, 20})
    expect(session.armed).to be_empty
  end

  it "leaves the offset where it is when cancelled" do
    slate = Slate.new
    session = clocked
    glide = slate.scroll

    glide.to 0, 20, session.app, animate: true
    glide.cancel

    expect(slate.at).to eq({0, 10})
    expect(session.armed).to be_empty
  end

  it "does nothing when the offset is on the goal" do
    slate = Slate.new
    session = clocked

    slate.scroll.to 0, 0, session.app, animate: true

    expect(slate.writes).to be_empty
    expect(session.armed).to be_empty
  end

  it "scrolls a widget that scrolls by Scrolls" do
    pager = Widgets::Pager.new
    pager.resize 20, 4
    pager.show (1..30).map { |number| "line #{number}" }
    pager.catch_up
    session = clocked
    glide = described_class.over pager
    newest = pager.scroll_y

    glide.to 0, newest - 12, session.app, animate: true
    session.run_timers

    expect(pager.scroll_y).to eq newest - 12
  end

  it "lands on the end of the curve exactly" do
    steps = (0..5).map { |frame| described_class.at({0, 0}, {0, 100}, frame, 5)[1] }

    expect(steps).to eq [0, 49, 78, 94, 99, 100]
  end
end
