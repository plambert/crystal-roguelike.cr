require "../../spec_helper"

Spectator.describe TermBuf::Widgets::RecurringTimer do
  alias Widgets = TermBuf::Widgets

  # An application with the hand-driven clock used in these specs.
  def clocked : Headless::Session
    session = Headless.open Widgets::Panel.new, 4, 2
    session.clock
    session
  end

  it "runs one pending callback and releases it before the next step" do
    session = clocked
    timer = described_class.new
    calls = 0

    timer.after(session.app, 1.second) do
      calls += 1
      timer.after(session.app, 1.second) do
        calls += 1
        nil
      end
      nil
    end
    timer.after(session.app, 1.second) do
      calls += 10
      nil
    end

    expect(session.armed.size).to eq 1
    expect(timer.pending?).to be_true

    session.tick

    expect(calls).to eq 1
    expect(session.armed.size).to eq 1
    expect(timer.pending?).to be_true

    session.tick

    expect(calls).to eq 2
    expect(timer.pending?).to be_false
    expect(session.armed).to be_empty
  end

  it "returns to synchronous work when the application has no clock" do
    session = Headless.open Widgets::Panel.new, 4, 2
    timer = described_class.new
    called = false

    armed = timer.after(session.app, 1.second) do
      called = true
      nil
    end

    expect(armed).to be_false
    expect(timer.pending?).to be_false
    expect(called).to be_false
  end

  it "ignores a canceled callback without losing its replacement" do
    session = clocked
    timer = described_class.new
    calls = 0

    timer.after(session.app, 1.second) do
      calls += 1
      nil
    end
    stale = session.armed.first
    timer.cancel
    timer.after(session.app, 1.second) do
      calls += 1
      nil
    end
    current = session.armed.first

    session.send TermBuf::Input::Events::Timer.new(stale)

    expect(calls).to eq 0
    expect(timer.pending?).to be_true
    expect(session.armed).to eq [current]

    session.tick

    expect(calls).to eq 1
    expect(timer.pending?).to be_false
  end

  it "cancels a timer on its old app when the owner changes apps" do
    first = clocked
    second = clocked
    timer = described_class.new
    calls = 0

    timer.after(first.app, 1.second) do
      calls += 1
      nil
    end
    stale = first.armed.first

    timer.after(second.app, 1.second) do
      calls += 1
      nil
    end

    expect(first.armed).to be_empty
    expect(second.armed.size).to eq 1

    first.send TermBuf::Input::Events::Timer.new(stale)
    expect(calls).to eq 0
    expect(timer.pending?).to be_true

    second.tick

    expect(calls).to eq 1
    expect(timer.pending?).to be_false
  end
end
