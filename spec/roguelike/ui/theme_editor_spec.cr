require "../../spec_helper"

Spectator.describe Roguelike::Ui::ThemeEditor do
  alias Options = Roguelike::Options
  alias Theme = Roguelike::Ui::Theme
  alias Palette = Roguelike::Ui::Palette
  alias Depth = TermBuf::Widgets::Depth
  alias Color = TermBuf::Color
  alias Editor = Roguelike::Ui::ThemeEditor
  alias Library = Roguelike::Ui::ThemeLibrary

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
    keys = editor(run).form.rows.map &.key
    editor(run).form.rows.size.times do
      at = keys.index(editor(run).focused_row.try &.key) || 0
      wanted = keys.index!(key)
      break if at == wanted
      run.press(at < wanted ? "Down" : "Up")
    end
    expect(editor(run).focused_row.try &.key).to eq key
  end

  # What the status line under the preview says.
  def status(run : Playing::Run) : String
    editor(run).status.text
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
    Theme.current_name = nil
    Library.problem = nil
    Palette.rebuild
    FileUtils.rm_rf root.to_s
  end

  it "opens from the options screen over the options" do
    run = run_under root
    open_editor run

    expect(editor(run).showing?).to be_true
    expect(run.play.options_screen.showing?).to be_true
    expect(run.text).to contain "Color theme"
    expect(editor(run).focused_row.try &.key).to eq "theme-default"
    expect(editor(run).form.app).to be run.session.app
  end

  it "has a section per group and a row per color, in order" do
    run = run_under root
    open_editor run

    form = editor(run).form
    expect(form.sections.compact_map(&.name)).to eq ["Themes", "Share"] + Theme::ENTRIES.map(&.group).uniq! + ["Reset"]
    expect(form.rows.map(&.key)).to eq %w[theme-default theme-high-contrast theme-paper] +
                                       [Editor::COPY_KEY, Editor::NAME_KEY, Editor::SAVE_KEY, Editor::PASTE_KEY] +
                                       Theme::ENTRIES.map(&.key) + [Editor::RESET_KEY]
    expect(form.row("granite").try &.label).to eq "Granite"
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
      expect(Theme.current_name).to eq "Default"
      expect(editor(run).form["hero"]).to eq Theme::DEFAULT.hero
      expect(on_file(root)["hero"]).to eq Theme::Hex.to_hex(Theme::DEFAULT.hero)
      expect(editor(run).showing?).to be_true
    end
  end

  describe "keys" do
    it "moves with j and k, and between groups with h and l" do
      run = run_under root
      open_editor run
      go_to run, "granite"

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
      go_to run, "granite"

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

  describe "sharing" do
    let(moss) { Theme::DEFAULT.with("ground", red).with("hero", Color.rgb(0x010203)) }

    it "copies the theme in use to the clipboard as an rltheme: link with its name" do
      run = run_under root
      copied = [] of String
      run.session.app.copy = ->(text : String) { copied << text; nil }
      open_editor run
      go_to run, "hero"
      pick run, "ff0000"

      go_to run, Editor::COPY_KEY
      run.press "Enter"

      expect(copied.size).to eq 1
      expect(copied.first).to start_with "rltheme:"
      expect(Theme.parse_shared copied.first).to eq({Theme.current, Editor::UNNAMED})
      expect(status run).to eq "Copied My theme to the clipboard."
      expect(run.text).to contain "Copied My theme to the clipboard."
    end

    it "says so when there is no clipboard" do
      run = run_under root
      run.session.app.copy = nil
      open_editor run
      go_to run, Editor::COPY_KEY
      run.press "Enter"

      expect(status run).to contain "no clipboard"
    end

    it "saves under the typed name with Enter in the name row" do
      run = run_under root
      open_editor run
      go_to run, "ground"
      pick run, "ff0000"

      go_to run, Editor::NAME_KEY
      run.press "Ctrl+U"
      run.type "Red sky"
      run.press "Enter"

      expect(Library.read Library.directory(root) / "red-sky.json")
        .to eq Library::Named.new("Red sky", Theme.current)
      expect(on_file(root)["name"]).to eq "Red sky"
      expect(Theme.current_name).to eq "Red sky"
      expect(status run).to contain "Saved Red sky"
    end

    it "saves under the name in the name row from the save row" do
      run = run_under root
      open_editor run
      go_to run, Editor::SAVE_KEY
      run.press "Enter"

      expect(Library.saved(root).map &.name).to eq [Editor::UNNAMED]
    end

    it "takes r and ? as letters in a text row" do
      run = run_under root
      open_editor run
      go_to run, Editor::NAME_KEY
      run.press "Ctrl+U"
      run.type "r?"

      expect(editor(run).form[Editor::NAME_KEY]).to eq "r?"
      expect(editor(run).help.open?).to be_false
    end

    it "uses a pasted rltheme: link, saves it under its name and empties the row" do
      run = run_under root
      open_editor run
      before = edge_cell run
      go_to run, Editor::PASTE_KEY
      run.paste moss.to_uri("Moss")

      expect(Theme.current).to eq moss
      expect(Theme.current_name).to eq "Moss"
      expect(editor(run).form["ground"]).to eq red
      expect(editor(run).form[Editor::PASTE_KEY]).to eq ""
      expect(editor(run).form[Editor::NAME_KEY]).to eq "Moss"
      expect(Library.saved root).to eq [Library::Named.new("Moss", moss)]
      expect(on_file(root)["ground"]).to eq "#ff0000"
      expect(edge_cell run).not_to eq before
      expect(status run).to contain "Using Moss"
    end

    it "uses pasted theme JSON with no name and saves no file" do
      run = run_under root
      open_editor run
      go_to run, Editor::PASTE_KEY
      run.paste %({"ground": "#ff0000", "sparkle": "#ffffff"})

      expect(Theme.current).to eq Theme::DEFAULT.with("ground", red)
      expect(Library.saved root).to be_empty
      expect(status run).to contain "Type a name and save it"
    end

    it "uses a theme typed into the paste row on Enter" do
      run = run_under root
      open_editor run
      go_to run, Editor::PASTE_KEY
      run.type %({"ground": "#ff0000"})
      run.press "Enter"

      expect(Theme.current.ground).to eq red
    end

    it "names the bad colors of a pasted theme and changes nothing" do
      run = run_under root
      open_editor run
      go_to run, Editor::PASTE_KEY
      run.paste %({"name": "Bad", "ground": "#ff0000", "hero": "white"})

      expect(Theme.current).to eq Theme::DEFAULT
      expect(Library.saved root).to be_empty
      expect(File.exists? Theme.path(root)).to be_false
      expect(status run).to eq "These colors are not #rrggbb: hero. Nothing was changed."
    end

    it "says so for a pasted link that is not base64 and changes nothing" do
      run = run_under root
      open_editor run
      go_to run, Editor::PASTE_KEY
      run.paste "rltheme:%%%"

      expect(Theme.current).to eq Theme::DEFAULT
      expect(status run).to eq "This rltheme: link is not base64. Nothing was changed."
    end

    it "says so for pasted text that is not JSON and changes nothing" do
      run = run_under root
      open_editor run
      go_to run, Editor::PASTE_KEY
      run.paste "a lovely theme"

      expect(Theme.current).to eq Theme::DEFAULT
      expect(status run).to contain "not JSON"
    end

    it "ignores a paste into any other row" do
      run = run_under root
      open_editor run
      go_to run, Editor::NAME_KEY
      run.paste moss.to_named_json("Moss")

      expect(Theme.current).to eq Theme::DEFAULT
    end
  end

  describe "the built-in themes" do
    let(moss) { Theme::DEFAULT.with("ground", red) }

    it "offers a new name for saving a built-in theme" do
      Theme.current, Theme.current_name = Theme::PAPER, "Paper"
      run = run_under root
      open_editor run

      expect(editor(run).form[Editor::NAME_KEY]).to eq "Paper copy"
    end

    it "refuses to save under the name of a built-in theme" do
      run = run_under root
      open_editor run
      go_to run, Editor::NAME_KEY
      run.press "Ctrl+U"
      run.type "paper"
      run.press "Enter"

      expect(Library.saved root).to be_empty
      expect(status run).to eq "Paper is one of the game's own themes. Save it under another name."
    end

    it "uses a pasted built-in theme by its name and saves nothing" do
      run = run_under root
      open_editor run
      go_to run, Editor::PASTE_KEY
      run.paste Theme::PAPER.to_named_json("paper")

      expect(Theme.current).to eq Theme::PAPER
      expect(Theme.current_name).to eq "Paper"
      expect(Library.saved root).to be_empty
    end

    it "saves a pasted theme with a built-in name and other colors under a new name" do
      run = run_under root
      open_editor run
      go_to run, Editor::PASTE_KEY
      run.paste moss.to_named_json("Paper")

      expect(Theme.current).to eq moss
      expect(Theme.current_name).to eq "Paper copy"
      expect(Library.saved root).to eq [Library::Named.new("Paper copy", moss)]
    end

    it "says once what went wrong writing the built-in files" do
      Library.problem = "The built-in theme files could not be written."
      run = run_under root
      open_editor run
      expect(status run).to eq "The built-in theme files could not be written."

      run.press "Escape", "Enter"
      expect(editor(run).showing?).to be_true
      expect(status run).to eq ""
    end
  end

  describe "the themes section" do
    let(moss) { Theme::DEFAULT.with("ground", red) }

    it "lists the built-in themes, then the saved ones by name" do
      Library.save root, "Moss", moss
      Library.save root, "Amber", Theme::PAPER
      run = run_under root
      open_editor run

      choices = editor(run).choices.values.map &.name
      expect(choices).to eq ["Default", "High contrast", "Paper", "Amber", "Moss"]
      expect(run.text).to contain "High contrast"
    end

    it "marks the theme in use and starts the keyboard on it" do
      Theme.current = Theme::PAPER
      run = run_under root
      open_editor run

      row = editor(run).form.row("theme-paper").as(TermBuf::Widgets::Form::ActionRow)
      expect(row.hint).to eq "in use, dark ink, for a light terminal"
      expect(editor(run).focused_row.try &.key).to eq "theme-paper"
    end

    it "draws with a theme chosen with Enter and writes it with its name" do
      Library.save root, "Moss", moss
      run = run_under root
      open_editor run
      before = edge_cell run
      go_to run, "theme-moss"
      run.press "Enter"

      expect(Theme.current).to eq moss
      expect(Theme.current_name).to eq "Moss"
      expect(on_file(root)["name"]).to eq "Moss"
      expect(editor(run).form["ground"]).to eq red
      expect(editor(run).form[Editor::NAME_KEY]).to eq "Moss"
      expect(edge_cell run).not_to eq before
      expect(status run).to eq "Using Moss."
      expect(editor(run).form.row("theme-moss").as(TermBuf::Widgets::Form::ActionRow).hint).to eq "in use"
    end

    it "offers a copy name after choosing a built-in theme" do
      run = run_under root
      open_editor run
      go_to run, "theme-high-contrast"
      run.press "Enter"

      expect(Theme.current).to eq Theme::HIGH_CONTRAST
      expect(editor(run).form[Editor::NAME_KEY]).to eq "High contrast copy"
    end

    it "drops the in use mark once a color changes" do
      run = run_under root
      open_editor run
      go_to run, "hero"
      pick run, "ff0000"

      expect(editor(run).form.row("theme-default").as(TermBuf::Widgets::Form::ActionRow).hint)
        .to eq "the game's own colors"
    end

    it "lists a theme as soon as it is saved, keeping the keyboard where it was" do
      run = run_under root
      open_editor run
      go_to run, Editor::NAME_KEY
      run.press "Ctrl+U"
      run.type "Moss"
      run.press "Enter"

      expect(editor(run).choices.keys).to contain "theme-moss"
      expect(editor(run).focused_row.try &.key).to eq Editor::NAME_KEY
      expect(run.text).to contain "Moss"
    end

    it "lists a pasted theme as soon as it is saved" do
      run = run_under root
      open_editor run
      go_to run, Editor::PASTE_KEY
      run.paste moss.to_named_json("Moss")

      expect(editor(run).choices.keys).to contain "theme-moss"
      expect(editor(run).focused_row.try &.key).to eq Editor::PASTE_KEY
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
