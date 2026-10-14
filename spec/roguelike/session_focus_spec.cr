require "../spec_helper"

Spectator.describe "a session and the window's focus" do
  # A session on a terminal over a pipe. What it writes goes nowhere.
  def opened(flicker : Bool = false, & : Roguelike::Session ->) : Nil
    reader, writer = IO.pipe
    tty = TermBuf::Tty.new reader, IO::Memory.new, managed: false
    terminal = TermBuf::Terminal.new tty,
      capabilities: TermBuf::Capabilities::MODERN,
      size: TermBuf::ScreenSize.new(80, 24)
    terminal.start

    begin
      session = Roguelike::Session.new terminal, Roguelike::Rng.for(Playing::SEED),
        flicker: flicker, character: "Focus"
      session.app.pump
      yield session
    ensure
      terminal.close
      writer.close
    end
  end

  # Sends a focus report the way the terminal would.
  def report(session : Roguelike::Session, focused : Bool) : Nil
    session.terminal.input.inject TermBuf::Events::Focus.new(focused)
    session.app.pump
  end

  it "asks the terminal for focus reports" do
    opened do |session|
      names = session.terminal.tty.modes.map &.name
      expect(names).to contain TermBuf::Tty::FOCUS_EVENTS.name
    end
  end

  it "starts with the focus" do
    opened do |session|
      expect(session.focused?).to be_true
      expect(session.play.map.idle?).to be_false
    end
  end

  it "loses the focus on a report and gets it back on the next" do
    opened do |session|
      report session, false
      expect(session.focused?).to be_false
      expect(session.play.map.idle?).to be_true

      report session, true
      expect(session.focused?).to be_true
      expect(session.play.map.idle?).to be_false
    end
  end

  it "keeps the map's drawing across a tick of the flames" do
    opened(flicker: true) do |session|
      report session, false
      session.app.frame
      expect(session.play.map.kept).to eq 1

      before = session.play.map.worked
      session.app.wait
      session.app.frame

      expect(session.play.flicker.tick).to eq 1
      expect(session.play.map.worked).to eq before
    end
  end

  it "drops the map's drawings on any other event" do
    opened(flicker: true) do |session|
      report session, false
      session.app.frame

      session.terminal.input.inject TermBuf::Input::Events::Timer.new(0xdead_u64)
      session.app.pump

      expect(session.play.map.kept).to eq 0
    end
  end

  it "works the map out again when the focus comes back" do
    opened(flicker: true) do |session|
      report session, false
      session.app.frame

      report session, true
      expect(session.play.map.kept).to eq 0

      before = session.play.map.worked
      session.app.frame
      expect(session.play.map.worked).to be > before
    end
  end
end
