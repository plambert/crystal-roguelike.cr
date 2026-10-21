require "../../spec_helper"

Spectator.describe Roguelike::Ui::ThemeEditor do
  alias Options = Roguelike::Options
  alias Theme = Roguelike::Ui::Theme
  alias Palette = Roguelike::Ui::Palette
  alias Depth = TermBuf::Widgets::Depth
  alias Color = TermBuf::Color

  # A state directory of the spec's own, so nothing reaches the person's.
  def state : Path
    Path[File.tempname "roguelike-theme-editor", nil].tap { |made| Dir.mkdir_p made }
  end

  # A run with its options screen writing under *root*.
  def run_under(root : Path, columns : Int32 = 80, rows : Int32 = 24) : Playing::Run
    run = Playing.open columns: columns, rows: rows
    run.play.options_screen.root = root
    run
  end

  def editor(run : Playing::Run) : Roguelike::Ui::ThemeEditor
    run.play.options_screen.theme_editor
  end

  # Opens the options screen and then the editor from its theme row.
  def open_editor(run : Playing::Run) : Nil
    run.press "O", "Down", "Down", "Down", "Enter"
  end

  # Moves the keyboard down to the row filed under *key*.
  def go_to(run : Playing::Run, key : String) : Nil
    Theme::ENTRIES.index!(&.key.==(key)).times { run.press "Down" }
  end

  # Opens the picker on the row with the keyboard and types *hex* into it.
  def pick(run : Playing::Run, hex : String) : Nil
    run.press "Enter", "Tab", "Tab", "Tab", "Tab", "Ctrl+U"
    run.type hex
    run.press "Enter"
  end

  # The theme file under *root*, parsed.
  def on_file(root : Path) : JSON::Any
    JSON.parse File.read(Theme.path root)
  end

  # The style of a map cell at the right edge of the screen, which the boxes
  # leave uncovered.
  def edge_cell(run : Playing::Run) : UInt32?
    run.buffer.hit(*run.on_map(run.screen.map.rect.width - 1, 2)).try &.cell.style
  end

  let(root) { state }
  let(red) { Color.rgb 0xFF0000 }

  before_each { Options.current = Options.read(root) }

  after_each do
    Options.current = nil
    Roguelike::Tester.current = nil
    Theme.current = Theme::DEFAULT
    Palette.rebuild
    FileUtils.rm_rf root.to_s
  end

  it "opens from the options screen over the options" do
    run = run_under root
    open_editor run

    expect(editor(run).showing?).to be_true
    expect(run.play.options_screen.showing?).to be_true
    expect(run.text).to contain "Color theme"
    expect(editor(run).focused_row.try &.key).to eq "granite"
    expect(editor(run).form.app).to be run.session.app
  end

  it "has a section per group and a row per color, in order" do
    run = run_under root
    open_editor run

    form = editor(run).form
    expect(form.sections.compact_map(&.name)).to eq Theme::ENTRIES.map(&.group).uniq! + ["Reset"]
    expect(form.rows.map(&.key)).to eq Theme::ENTRIES.map(&.key) + [Roguelike::Ui::ThemeEditor::RESET_KEY]
    expect(form.rows.first.label).to eq "Granite"
  end

  describe "a change" do
    it "rebuilds the palette, writes the file and draws the screen behind in it" do
      run = run_under root
      open_editor run
      before = edge_cell run

      go_to run, "ground"
      pick run, "ff0000"

      expect(Theme.current.ground).to eq red
      expect(Palette.ground_style.background).to eq red
      expect(on_file(root)["ground"]).to eq "#ff0000"
      expect(edge_cell run).not_to eq before
      expect(editor(run).showing?).to be_true
    end

    it "gives the copied colors the new theme" do
      run = run_under root
      open_editor run

      go_to run, "message_new"
      pick run, "ff0000"

      expect(run.pager.fresh_style.try &.foreground).to eq red
    end

    it "keeps an Rgb color when the picker chose a palette index" do
      expect(Roguelike::Ui::ThemeEditor.stored Color.indexed(196)).to eq red
      expect(Roguelike::Ui::ThemeEditor.stored red).to eq red
    end
  end

  it "offers the 256 colors on a terminal without 24 bit color" do
    run = run_under root
    run.play.color_depth = Depth::Indexed256
    open_editor run

    expect(editor(run).form.depth).to eq Depth::Indexed256
  end

  it "puts one color back with r" do
    run = run_under root
    open_editor run
    before = edge_cell run

    go_to run, "ground"
    pick run, "ff0000"
    expect(edge_cell run).not_to eq before
    run.press "r"

    expect(Theme.current.ground).to eq Theme::DEFAULT.ground
    expect(on_file(root)["ground"]).to eq Theme::Hex.to_hex(Theme::DEFAULT.ground)
    expect(editor(run).form["ground"]).to eq Theme::DEFAULT.ground
    expect(edge_cell run).to eq before
  end

  describe "the reset row" do
    it "asks first, and n leaves every color as it was" do
      run = run_under root
      open_editor run
      go_to run, "hero"
      pick run, "ff0000"

      run.press "End", "Enter"
      expect(run.prompt.asking?).to be_true
      expect(run.text).to contain "Put every color back?"

      run.press "n"
      expect(run.prompt.asking?).to be_false
      expect(Theme.current.hero).to eq red
      expect(editor(run).showing?).to be_true
    end

    it "puts every color back on y" do
      run = run_under root
      open_editor run
      go_to run, "hero"
      pick run, "ff0000"

      run.press "End", "Enter", "y"
      expect(Theme.current).to eq Theme::DEFAULT
      expect(editor(run).form["hero"]).to eq Theme::DEFAULT.hero
      expect(on_file(root)["hero"]).to eq Theme::Hex.to_hex(Theme::DEFAULT.hero)
      expect(editor(run).showing?).to be_true
    end
  end

  describe "keys" do
    it "moves with j and k, and between groups with h and l" do
      run = run_under root
      open_editor run

      run.press "j"
      expect(editor(run).focused_row.try &.key).to eq "sandstone"
      run.press "k"
      expect(editor(run).focused_row.try &.key).to eq "granite"
      run.press "l"
      expect(editor(run).focused_row.try &.key).to eq "white_slime"
      run.press "h"
      expect(editor(run).focused_row.try &.key).to eq "granite"
    end

    it "shows its own keys on ? and F1" do
      run = run_under root
      open_editor run

      {"?", "F1"}.each do |key|
        run.press key
        expect(editor(run).help.open?).to be_true
        expect(run.text).to contain "put this color back"

        run.press "Escape"
        expect(editor(run).help.open?).to be_false
        expect(editor(run).showing?).to be_true
      end
    end

    it "puts the color back with Escape in the picker and keeps the editor up" do
      run = run_under root
      open_editor run

      run.press "Enter", "Right", "Escape"
      expect(editor(run).showing?).to be_true
      expect(editor(run).picking?).to be_false
      expect(Theme.current.granite).to eq Theme::DEFAULT.granite
    end

    it "goes back to the options screen on Escape" do
      run = run_under root
      open_editor run

      run.press "Escape"
      expect(editor(run).showing?).to be_false
      expect(run.play.options_screen.showing?).to be_true
      expect(run.play.options_screen.focused_row.try &.key).to eq "theme"
      expect(run.text).to contain "Options"
    end
  end

  it "draws the open editor the way it drew it last time" do
    run = run_under root, columns: Roguelike::Ui::Screen::MINIMUM_COLUMNS,
      rows: Roguelike::Ui::Screen::MINIMUM_ROWS
    open_editor run
    drawn = run.text

    expect(drawn).to eq Fixture.expected("screen/theme-editor.txt", drawn)
  end
end
