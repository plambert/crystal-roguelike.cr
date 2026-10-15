require "../../spec_helper"

Spectator.describe Roguelike::Ui::NewsPage do
  alias Placards = Roguelike::Ui::Placards
  alias WhatsNew = Roguelike::WhatsNew

  def notes(count : Int32 = 1) : Array(WhatsNew::Section)
    lines = (1..count).map { |index| "* Bullet number #{index} of the notes." }
    WhatsNew.sections <<-NEWS
      ## [0.3.0] - 2026-10-10

      The lead sentence.

      #{lines.join "\n"}
      NEWS
  end

  def title(news : Array(WhatsNew::Section)) : Playing::Run
    Playing.open title: true, news: news
  end

  it "adds a row before quit when there are notes" do
    run = title notes

    keys = run.menu.entries.map &.key
    expect(keys).to eq [Placards::NEW_KEY, Placards::WHATS_NEW_KEY, Placards::QUIT_KEY]
    expect(run.menu.entries[1].text).to eq Placards::WHATS_NEW_ROW
  end

  it "has no row when there are no notes" do
    run = title [] of WhatsNew::Section

    expect(run.menu.entries.map &.key).to eq [Placards::NEW_KEY, Placards::QUIT_KEY]
  end

  it "shows the notes, and Escape puts the title menu back" do
    run = title notes

    run.press Placards::WHATS_NEW_KEY.to_s
    expect(run.news_page_open?).to be_true
    expect(run.text).to contain "0.3.0 - 2026-10-10"
    expect(run.text).to contain "* Bullet number 1 of the notes."

    run.press "Escape"
    expect(run.news_page_open?).to be_false
    expect(run.menu.showing?).to be_true
  end

  it "scrolls when the notes are longer than the window" do
    run = title notes(60)

    run.press Placards::WHATS_NEW_KEY.to_s
    expect(run.text).not_to contain "Bullet number 60 "
    run.press "End"
    expect(run.text).to contain "Bullet number 60 "
  end
end
