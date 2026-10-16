require "../spec_helper"

Spectator.describe "a session with its size capped" do
  alias Rect = TermBuf::Rect
  alias SizeCap = Roguelike::SizeCap

  # A session on an 80 by 24 terminal over a pipe, with the debug console.
  def opened(cap : SizeCap = SizeCap.new, flicker : Bool = false,
             & : Roguelike::Session ->) : Nil
    reader, writer = IO.pipe
    tty = TermBuf::Tty.new reader, IO::Memory.new, managed: false
    terminal = TermBuf::Terminal.new tty,
      capabilities: TermBuf::Capabilities::MODERN,
      size: TermBuf::ScreenSize.new(80, 24)
    terminal.start

    begin
      session = Roguelike::Session.new terminal, Roguelike::Rng.for(Playing::SEED),
        flicker: flicker, console: true, character: "Capped", size_cap: cap
      session.app.pump
      yield session
    ensure
      terminal.close
      writer.close
    end
  end

  # Where the game draws.
  def area(session : Roguelike::Session) : Rect
    session.app.tree.screen
  end

  # Runs *line* in the debug console.
  def typed(session : Roguelike::Session, line : String) : String
    pane = session.play.console
    raise "no console" unless pane

    pane.run line
    pane.console.lines.last
  end

  # Sends a resize the way the terminal would.
  def resize(session : Roguelike::Session, columns : Int32, rows : Int32) : Nil
    size = TermBuf::ScreenSize.new columns, rows
    session.terminal.input.inject TermBuf::Events::Resize.new(size, session.terminal.size)
    session.app.pump
  end

  # The first row of what the terminal's buffer holds.
  def top_row(session : Roguelike::Session) : String
    text = ""
    session.terminal.sync { |buffer| text = buffer.to_text.lines.first }
    text
  end

  it "draws in the whole terminal when nothing is capped" do
    opened do |session|
      expect(area session).to eq Rect.full(80, 24)
    end
  end

  it "fits the game to the capped size" do
    opened(SizeCap.new(59, 20)) do |session|
      expect(area session).to eq Rect.full(59, 20)
      expect(session.help.screen_rows).to eq 20
      expect(session.play.screen.playing?).to be_true
      expect(session.play.screen.sidebar?).to be_false
    end
  end

  it "shows the too-small notice for a cap below the minimum" do
    opened(SizeCap.new(39)) do |session|
      expect(session.play.screen.playing?).to be_false
      expect(session.play.screen.notice_text.text).to contain "This one is 39 by 24."
    end
  end

  it "fits to the smaller of the terminal and the cap on a resize" do
    opened(SizeCap.new(60)) do |session|
      resize session, 100, 30
      expect(area session).to eq Rect.full(60, 30)

      resize session, 50, 30
      expect(area session).to eq Rect.full(50, 30)
    end
  end

  it "refits when the console sets a cap, and again when it clears one" do
    opened do |session|
      expect(typed session, "max-columns 60").to eq "max-columns is 60."
      expect(area session).to eq Rect.full(60, 24)

      expect(typed session, "max-rows 20").to eq "max-rows is 20."
      expect(area session).to eq Rect.full(60, 20)

      expect(typed session, "max-columns off").to eq "max-columns is none."
      expect(area session).to eq Rect.full(80, 20)

      expect(typed session, "max-rows 0").to eq "max-rows is none."
      expect(area session).to eq Rect.full(80, 24)
    end
  end

  it "says what the cap is when given no number" do
    opened(SizeCap.new(70)) do |session|
      expect(typed session, "max-columns").to eq "max-columns is 70."
      expect(typed session, "max-rows").to eq "max-rows is none."
    end
  end

  it "clears the cells it no longer draws in when a cap shrinks" do
    opened do |session|
      session.terminal.write 70, 0, "Z"
      expect(top_row(session)[70]).to eq 'Z'

      typed session, "max-columns 60"
      expect(top_row(session)[70]?).not_to eq 'Z'
    end
  end

  it "leaves the cells alone when a cap grows" do
    opened(SizeCap.new(60)) do |session|
      session.terminal.write 70, 0, "Z"

      typed session, "max-columns 70"
      expect(top_row(session)[70]).to eq 'Z'
    end
  end

  # Sends a mouse report at (*x*, *y*).
  def mouse(session : Roguelike::Session, x : Int32, y : Int32,
            action = TermBuf::Input::Mouse::Action::Motion,
            button = TermBuf::Input::Mouse::Button::None) : Nil
    session.terminal.input.inject TermBuf::Events::Mouse.new(
      button, x, y, TermBuf::Modifiers::None, action)
    session.app.pump
  end

  # Sends the pointer moving over (*x*, *y*).
  def point(session : Roguelike::Session, x : Int32, y : Int32) : Nil
    mouse session, x, y
  end

  # An idle map keeps its drawing until an event reaches the tree, so what
  # it keeps says whether the pointer got there.
  it "ignores the mouse outside the area" do
    opened(SizeCap.new(60), flicker: true) do |session|
      session.focused = false
      session.app.frame
      expect(session.play.map.kept).to eq 1

      point session, 70, 5
      expect(session.play.map.kept).to eq 1

      point session, 30, 5
      expect(session.play.map.kept).to eq 0
    end
  end

  it "follows a drag that started inside past the edge until the button comes up" do
    opened(SizeCap.new(60), flicker: true) do |session|
      session.focused = false
      right = TermBuf::Input::Mouse::Button::Right
      mouse session, 30, 5, TermBuf::Input::Mouse::Action::Press, right

      session.app.frame
      mouse session, 70, 5, TermBuf::Input::Mouse::Action::Motion, right
      expect(session.play.map.kept).to eq 0

      session.app.frame
      mouse session, 70, 5, TermBuf::Input::Mouse::Action::Release
      expect(session.play.map.kept).to eq 0

      session.app.frame
      point session, 70, 5
      expect(session.play.map.kept).to eq 1
    end
  end
end
