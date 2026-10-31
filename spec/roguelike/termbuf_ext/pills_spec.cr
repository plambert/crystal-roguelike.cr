require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Pills do
  alias Widgets = TermBuf::Widgets
  alias Pill = TermBuf::Widgets::Pills::Pill

  GREEN = TermBuf::Style::DEFAULT.bg(TermBuf::Color.rgb(0x66CC88))
  RED   = TermBuf::Style::DEFAULT.bg(TermBuf::Color.rgb(0xFF8A80))

  # Pills that say *words*, the first green and the rest red.
  def pills(*words : String) : Widgets::Pills
    made = Widgets::Pills.new
    made.pills = words.to_a.map_with_index { |word, index| Pill.new word, index.zero? ? GREEN : RED }
    made
  end

  # *pills* drawn *columns* wide, one string per row.
  def drawn(pills : Widgets::Pills, columns : Int32, rows : Int32 = 4) : Array(String)
    session = Headless.open pills, columns, rows
    session.render
    (0...rows).map { |row| session.row(row).rstrip }
  end

  it "sets pills side by side, each with a cell of its own ground on either side" do
    expect(drawn(pills("hungry", "sick"), 20).first).to eq " hungry   sick"
  end

  it "wraps a pill that does not fit to the next row" do
    rows = drawn pills("hungry", "well fed", "steady aim"), 20

    expect(rows[0]).to eq " hungry   well fed"
    expect(rows[1]).to eq " steady aim"
  end

  it "is as tall as its rows" do
    made = pills "hungry", "well fed", "steady aim"
    policy = TermBuf::Unicode::WidthPolicy::DEFAULT

    expect(made.height_for_width(20, policy)).to eq 2
    expect(made.height_for_width(40, policy)).to eq 1
    expect(Widgets::Pills.new.height_for_width(20, policy)).to eq 0
  end

  it "asks for its widest pill at the least and one row of all of them by preference" do
    intrinsic = pills("hungry", "sick").intrinsic_width TermBuf::Unicode::WidthPolicy::DEFAULT

    expect(intrinsic.min).to eq 8
    expect(intrinsic.preferred).to eq 15
  end

  it "cuts a pill wider than the row" do
    expect(drawn(pills("dying of thirst"), 10).first).to eq " dying o…"
  end

  it "draws each pill in its own style, padding included, and leaves the gap" do
    session = Headless.open pills("hungry", "sick"), 20, 1
    session.render

    ground = ->(column : Int32) do
      found = session.buffer.hit column, 0
      found ? session.buffer.styles[found.cell.style].background : nil
    end
    expect(ground.call 0).to eq GREEN.background
    expect(ground.call 7).to eq GREEN.background
    expect(ground.call 8).not_to eq GREEN.background
    expect(ground.call 8).not_to eq RED.background
    expect(ground.call 9).to eq RED.background
    expect(ground.call 14).to eq RED.background
  end
end
