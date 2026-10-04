require "../../spec_helper"

Spectator.describe Roguelike::Ui::Help do
  # An application over a buffer with the game's keys and the help on it.
  def wired(seed : UInt64) : {Headless::Session, TermBuf::Widgets::HelpOverlay}
    screen = Roguelike::Ui::Screen.new
    screen.fit 100, 40

    session = Headless.open screen.root, 100, 40
    help = Roguelike::Ui::Keys.install(session.app, seed) { }
    session.render
    {session, help}
  end

  it "puts the seed and the movement diagram above the keys" do
    session, help = wired 4272_u64

    session.press "?"
    rows = help.rows

    expect(help.open?).to be_true
    expect(rows.first.keys).to eq("run")
    expect(rows.first.header).to be_true
    expect(rows[1].keys).to eq("seed")
    expect(rows[1].description).to eq("4272")
    expect(rows[2].keys).to eq("moving")
    expect(rows[3..7].map(&.keys)).to eq(Roguelike::Ui::Help::DIAGRAM)
    expect(rows[5].description).to eq("move, or attack what is there")
    expect(rows.size).to be > 8
  end

  it "draws the seed on the screen" do
    session, _help = wired 99_u64

    session.press "?"
    session.render

    expect(session.text).to contain("seed")
    expect(session.text).to contain("99")
    expect(session.text).to contain("h←@→l")
  end
end
