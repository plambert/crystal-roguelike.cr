require "../../spec_helper"

Spectator.describe Roguelike::Ui::Help do
  alias Help = Roguelike::Ui::Help
  alias Keys = Roguelike::Ui::Keys
  alias Direction = Roguelike::Direction

  # An application over a buffer with the game's keys and the help on it.
  def wired(seed : UInt64, columns : Int32 = 100, rows : Int32 = 40) : {Headless::Session, Help}
    screen = Roguelike::Ui::Screen.new
    screen.fit columns, rows

    session = Headless.open screen.root, columns, rows
    play = Roguelike::Ui::Play.new Roguelike::Game.dug(Roguelike::Rng.new 4272_u64)
    help = Keys.install(session.app, Help.new(seed), play, -> { }) { }
    help.screen_rows = rows
    session.render
    {session, help}
  end

  it "groups the keys, with the seed under the first heading" do
    session, help = wired 4272_u64

    session.press "?"
    rows = help.rows

    expect(help.open?).to be_true
    headers = rows.select(&.header).map(&.keys)
    expect(headers).to eq(["application", "moving", "time", "doors and stairs", "character", "items", "aiming", "messages", "map"])
    expect(rows[0].keys).to eq("application")
    expect(rows[1].keys).to eq("seed")
    expect(rows[1].description).to eq("4272")

    application = rows[2..].take_while { |row| !row.keys.empty? }.map(&.keys)
    expect(application).to contain("Q")
    expect(application).to contain("?")
    expect(application).to contain("x")
    expect(application).to contain("Escape")
    expect(application).not_to contain(".")
  end

  it "puts a blank row before every heading but the first" do
    _session, help = wired 1_u64
    help.rebuild
    rows = help.rows

    rows.each_with_index do |row, index|
      next unless row.header && index > 0

      expect(rows[index - 1].keys).to eq("")
    end
    expect(rows.first.header).to be_true
  end

  it "draws the movement keys as a diagram read from the bindings" do
    _session, help = wired 1_u64
    help.rebuild
    rows = help.rows

    start = rows.index! { |row| row.keys == "moving" }
    diagram = rows[(start + 1)..(start + 5)].map(&.keys)
    expect(diagram).to eq(["y k u", " ↖↑↗", "h←@→l", " ↙↓↘", "b j n"])
    expect(rows[start + 3].description).to eq(Help::MOVING)
  end

  it "widens the diagram for a longer key name" do
    moves = Keys.directions(Keys.moving { })
    moves[Direction::North] = "Up"
    lines = Help.diagram moves

    expect(lines[0]).to eq("y   Up  u")
    expect(lines[2]).to eq("h ← @ → l")
    expect(lines.max_of(&.size)).to be <= 10
  end

  it "shows a key where it is bound" do
    moves = Keys.directions(Keys.moving { })
    expect(moves[Direction::NorthWest]).to eq("y")
    expect(moves[Direction::SouthEast]).to eq("n")
    expect(moves.size).to eq(8)
  end

  it "fits the screen, leaving the margin, and shows the bar only when it scrolls" do
    session, help = wired 1_u64, rows: 70
    session.press "?"
    expect(help.list.most).to eq(70 - 2 * Help::MARGIN - Help::CHROME)
    expect(help.rows.size).to be <= help.list.most
    expect(help.bar.hidden?).to be_true
    session.press "Escape"

    small, cramped = wired 1_u64, rows: 40
    small.press "?"
    expect(cramped.list.most).to eq(40 - 2 * Help::MARGIN - Help::CHROME)
    expect(cramped.rows.size).to be > cramped.list.most
    expect(cramped.bar.hidden?).to be_false
  end

  it "draws the seed and the diagram on the screen" do
    session, _help = wired 99_u64

    session.press "?"
    session.render

    expect(session.text).to contain("seed")
    expect(session.text).to contain("99")
    expect(session.text).to contain("h←@→l")
    expect(session.text).to contain("doors and stairs")
  end
end
