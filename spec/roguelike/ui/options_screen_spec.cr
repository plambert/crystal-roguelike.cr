require "../../spec_helper"

Spectator.describe Roguelike::Ui::OptionsScreen do
  alias Options = Roguelike::Options
  alias Placards = Roguelike::Ui::Placards
  alias Form = TermBuf::Widgets::Form

  # A state directory of the spec's own, so nothing reaches the person's.
  def state : Path
    Path[File.tempname "roguelike-options-screen", nil].tap { |made| Dir.mkdir_p made }
  end

  # A run with its options screen writing under *root*.
  def run_under(root : Path, title : Bool = false, columns : Int32 = 80,
                rows : Int32 = 24, news = [] of Roguelike::WhatsNew::Section) : Playing::Run
    run = Playing.open title: title, columns: columns, rows: rows, news: news
    run.play.options_screen.root = root
    run
  end

  # The options file under *root*, parsed.
  def on_file(root : Path) : JSON::Any
    JSON.parse File.read(Options.path root)
  end

  def screen(run : Playing::Run) : Roguelike::Ui::OptionsScreen
    run.play.options_screen
  end

  # The key of the row with the keyboard.
  def on_row(run : Playing::Run) : String?
    screen(run).focused_row.try &.key
  end

  let(root) { state }

  before_each { Options.current = Options.read(root) }

  after_each do
    Options.current = nil
    Roguelike::Tester.current = nil
    Roguelike::Ui::Motion.on = false
    FileUtils.rm_rf root.to_s
  end

  describe "the title menu" do
    it "offers the options after the saves and before what is new" do
      news = Roguelike::WhatsNew.sections "## [0.3.0] - 2026-10-10\n\nThe lead.\n"
      run = run_under root, title: true, news: news

      keys = run.menu.entries.map &.key
      expect(keys).to eq [Placards::NEW_KEY, Placards::OPTIONS_KEY,
                          Placards::WHATS_NEW_KEY, Placards::QUIT_KEY]
      expect(run.menu.entries[1].text).to eq Placards::OPTIONS_ROW
    end

    it "opens the screen, and Escape puts the title menu back" do
      run = run_under root, title: true

      run.press Placards::OPTIONS_KEY.to_s
      expect(screen(run).showing?).to be_true
      expect(run.menu.showing?).to be_false
      expect(run.text).to contain "Options"

      run.press "Escape"
      expect(screen(run).showing?).to be_false
      expect(run.menu.showing?).to be_true
    end
  end

  describe "during play" do
    it "opens on O and closes on Escape with the game as it was" do
      run = run_under root
      app = run.session.app
      had = app.focus.current
      turn, said = run.turn, run.log.dup

      run.press "O"
      expect(screen(run).showing?).to be_true
      expect(run.play.modal?).to be_true
      expect(app.focus.scopes.size).to eq 2

      run.press "Escape"
      expect(screen(run).showing?).to be_false
      expect(app.focus.scopes.size).to eq 1
      expect(app.focus.current).to be had
      expect(run.turn).to eq turn
      expect(run.log).to eq said
    end

    it "keeps the game's keys away while it is up" do
      run = run_under root
      at = run.at

      run.press "O"
      run.press "i", "Q", "x"
      expect(run.menu.showing?).to be_false
      expect(run.prompt.asking?).to be_false
      expect(screen(run).showing?).to be_true

      run.press "Escape"
      expect(run.at).to eq at
      expect(run.turn).to eq 0
    end
  end

  describe "keys" do
    let(run) { run_under(root).tap(&.press "O") }

    it "starts on the first row" do
      expect(on_row run).to eq "motion"
    end

    it "hands the form the application" do
      expect(screen(run).form.app).to be run.session.app
    end

    it "moves with Down and Up, and with j and k" do
      run.press "Down"
      expect(on_row run).to eq "flicker"
      run.press "j"
      expect(on_row run).to eq "bar_color"
      run.press "k"
      expect(on_row run).to eq "flicker"
      run.press "Up"
      expect(on_row run).to eq "motion"
    end

    it "moves with Tab and Shift+Tab" do
      run.press "Tab"
      expect(on_row run).to eq "flicker"
      run.press "Shift+Tab"
      expect(on_row run).to eq "motion"
    end

    it "goes to the ends with Home and End" do
      run.press "End"
      expect(on_row run).to eq "name"
      run.press "Up", "Home"
      expect(on_row run).to eq "motion"
    end

    it "moves a screenful with PageDown and PageUp" do
      run.press "PageDown"
      expect(on_row run).not_to eq "motion"
      run.press "PageUp"
      expect(on_row run).to eq "motion"
    end

    it "turns a toggle with Space and with Enter" do
      run.press "Space"
      expect(screen(run).form["motion"]).to eq false
      run.press "Enter"
      expect(screen(run).form["motion"]).to eq true
    end

    it "moves a choice with Left and Right, and with h and l" do
      run.press "Down", "Down"
      run.press "Right"
      expect(screen(run).form["bar_color"]).to eq "bands"
      run.press "Left"
      expect(screen(run).form["bar_color"]).to eq "gradient"
      run.press "l"
      expect(screen(run).form["bar_color"]).to eq "bands"
      run.press "h"
      expect(screen(run).form["bar_color"]).to eq "gradient"
    end

    it "takes the next choice with Enter" do
      run.press "Down", "Down", "Enter"
      expect(screen(run).form["bar_color"]).to eq "bands"
    end

    it "types letters and ? into the name rather than moving" do
      run.press "End"
      run.type "jk?hl"
      expect(on_row run).to eq "name"
      expect(screen(run).help.open?).to be_false
      expect(screen(run).form["name"]).to eq "#{Roguelike::Tester::ANONYMOUS}jk?hl"
    end

    it "shows its own keys on ? and F1, and Escape goes back to the screen" do
      {"?", "F1"}.each do |key|
        run.press key
        expect(screen(run).help.open?).to be_true
        expect(run.text).to contain "the row below"

        run.press "Escape"
        expect(screen(run).help.open?).to be_false
        expect(screen(run).showing?).to be_true
        expect(on_row run).to eq "motion"
      end
    end
  end

  describe "a change" do
    it "writes the file and applies at once" do
      run = run_under root
      Roguelike::Ui::Motion.on = true

      run.press "O", "Space"
      expect(on_file(root)["motion"]).to eq false
      expect(Roguelike::Ui::Motion.on?).to be_false

      run.press "Down", "Down", "Right"
      expect(on_file(root)["bar_color"]).to eq "bands"
      expect(Options.current.try &.bar_color).to eq Options::BarColor::Bands
    end

    it "hands the options to the run after each change" do
      run = run_under root
      seen = [] of Bool
      run.play.on_options = ->(options : Options) { seen << options.flicker?; nil }

      run.press "O", "Down", "Space"
      expect(seen).to eq [false]
    end

    it "renames the tester and keeps the id" do
      Roguelike::Tester.new("4a1c4c39-3d3c-4d2d-9d56-1f5b1d0c9a10", "Hedrik").write root
      run = run_under root

      run.press "O", "End"
      expect(screen(run).form["name"]).to eq "Hedrik"
      run.type "a"

      written = Roguelike::Tester.read root
      expect(written.try &.name).to eq "Hedrika"
      expect(written.try &.id).to eq "4a1c4c39-3d3c-4d2d-9d56-1f5b1d0c9a10"
    end

    it "is shown again when the screen opens again" do
      run = run_under root
      run.press "O", "Space", "Escape", "O"

      expect(screen(run).form["motion"]).to eq false
    end
  end

  describe "a key a flag set" do
    it "carries a note naming the flag, and is the person's own once changed" do
      options = Options.arrange root, motion: false
      Options.current = options
      run = run_under root

      run.press "O"
      expect(screen(run).form.row("motion").try &.note).to eq "Set by --no-motion for this run"
      expect(run.text).to contain "Set by --no-motion for this run"

      run.press "Space"
      expect(options.overridden? "motion").to be_false
      expect(screen(run).form.row("motion").try &.note).to be_nil
      expect(on_file(root)["motion"]).to eq true
    end

    it "names the flag the way it was typed" do
      Options.current = Options.arrange root, update_check: true
      run = run_under root

      run.press "O"
      expect(screen(run).form.row("update_check").try &.note)
        .to eq "Set by --update-check for this run"
    end
  end

  it "draws the open screen the way it drew it last time" do
    run = run_under root, columns: Roguelike::Ui::Screen::MINIMUM_COLUMNS,
      rows: Roguelike::Ui::Screen::MINIMUM_ROWS
    run.press "O", "End"
    drawn = run.text

    expect(drawn).to eq Fixture.expected("screen/options.txt", drawn)
  end
end
