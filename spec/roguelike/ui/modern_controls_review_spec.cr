require "../../spec_helper"

Spectator.describe "modern controls reviewed interaction flows" do
  alias Command = Roguelike::Ui::Command
  alias Commands = Roguelike::Ui::Commands
  alias Context = Roguelike::Ui::CommandContext
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Options = Roguelike::Options

  after_each do
    Options.current = nil
    Roguelike::Ui::Motion.on = false
  end

  def options : Options
    found = Options.new
    found.control_scheme = Options::ControlScheme::Modern
    Options.current = found
    found
  end

  def state_root : Path
    Path[File.tempname("modern-controls-review", nil)].tap do |path|
      at_exit { FileUtils.rm_rf path.to_s }
    end
  end

  def run_with(items : Array(Item) = [] of Item,
               rows : Array(String) = ["#####", "#...#", "#...#", "#...#", "#####"],
               notes : Array(Roguelike::WhatsNew::Section) = [] of Roguelike::WhatsNew::Section) : Playing::Run
    options
    floor = Playing.daylight Roguelike::Floor.parse("review", rows)
    player = Roguelike::Player.new("review", 2, 2, hit_points: 40)
    items.each { |item| player.inventory.add item }
    game = Game.new Roguelike::World.new(Playing::SEED, {"review" => floor}), player
    run = Playing.open game, news: notes
    run.play.options_screen.root = state_root
    run
  end

  def choose_command(run : Playing::Run, label : String) : Nil
    run.press "r"
    menu = run.menu
    index : Int32? = nil
    Math.max(menu.pages.size, 1).times do
      index = menu.entries.index { |entry| entry.text.split(" — ", 2).first == label }
      break if index
      run.press "d"
    end
    wanted = index || raise "No command named #{label}"
    selected = menu.selected_index || 0
    while selected < wanted
      run.press "s"
      selected += 1
    end
    while selected > wanted
      run.press "w"
      selected -= 1
    end
    run.press "f"
  end

  it "shows the complete quantity of a perceived inventory group" do
    run = run_with [
      Item.new(Kind::Arrow, count: 4, blessing: Roguelike::Blessing::Cursed),
      Item.new(Kind::Arrow, count: 7),
    ]
    expect(run.game.player.inventory.size).to eq 1
    run.press "i"

    expect(run.menu.entries.any? { |entry| entry.text.includes?("11") && entry.text.includes?("arrow") })
      .to be_true
  end

  it "shows details for the highlighted inventory item" do
    run = run_with [Item.new(Kind::Dagger)]
    run.press "i"

    expect(run.play.tooltip.showing?).to be_true
    expect(run.text).to contain "weight"
    expect(run.turn).to eq 0
  end

  it "spikes the selected doorway rather than the first doorway" do
    run = run_with [Item.new(Kind::Spike, count: 3)],
      ["#####", "#.+.#", "#..+#", "#...#", "#####"]
    targets = Commands.targets(Command::SpikeDoor, Context.new(run.game))
    expect(targets.size).to eq 2
    selected = targets.size - 1
    wanted = targets.last.coordinate || raise "No selected doorway"
    other = targets.first.coordinate || raise "No other doorway"
    choose_command run, "Spike door"
    labels = run.menu.entries.map(&.text)
    selected.times { run.press "s" }
    run.press "f"

    expect(run.game.floor.spiked?(wanted[0], wanted[1])).to be_true
    expect(run.game.floor.spiked?(other[0], other[1])).to be_false
    expect(labels.uniq.size).to eq 2
    expect(run.turn).to eq 1
  end

  it "opens the color editor directly from its catalog command" do
    run = run_with
    choose_command run, "Color theme"

    expect(run.play.options_screen.theme_editor.showing?).to be_true
    expect(run.turn).to eq 0
  end

  it "does not open the new-character title after closing in-game news" do
    notes = Roguelike::WhatsNew.sections "## [0.7.0] - 2026-10-28\n\nReview notes.\n"
    run = run_with notes: notes
    choose_command run, "What is new"
    run.press "Escape"

    expect(run.menu.entries.any? { |entry| entry.text == "new character" }).to be_false
    expect(run.menu.title).to eq "Action catalog"
    expect(run.game.outcome.playing?).to be_true
    expect(run.turn).to eq 0
  end

  it "activates an options row with f without stealing text input" do
    run = run_with
    chosen = Options.current || raise "No options"
    run.play.show_options
    run.render
    expect(run.play.options_screen.focused_row.try(&.key)).to eq "motion"
    run.press "f"

    expect(chosen.motion?).to be_false
    expect(run.turn).to eq 0
  end

  it "keeps the catalog selection under options, theme, history, and help" do
    notes = Roguelike::WhatsNew.sections "## [0.7.0] - 2026-10-28\n\nReview notes.\n"
    run = run_with notes: notes

    choose_command run, "Options"
    run.press "F1", "Escape"
    expect(run.play.options_screen.showing?).to be_true
    run.press "Escape"
    expect(run.menu.title).to eq "Action catalog"
    expect(run.menu.entries[run.menu.selected_index || 0].text).to start_with "Options"

    run.press "Escape"
    choose_command run, "Color theme"
    run.press "F1", "Escape"
    expect(run.play.options_screen.theme_editor.showing?).to be_true
    run.press "Escape"
    expect(run.menu.title).to eq "Action catalog"
    expect(run.menu.entries[run.menu.selected_index || 0].text).to start_with "Color theme"

    run.press "Escape"
    choose_command run, "Message history"
    expect(run.play.history.showing?).to be_true
    run.press "Escape"
    expect(run.menu.title).to eq "Action catalog"

    run.press "Escape"
    choose_command run, "Help"
    run.press "Escape"
    expect(run.menu.title).to eq "Action catalog"
    expect(run.menu.entries[run.menu.selected_index || 0].text).to start_with "Help"
    expect(run.turn).to eq 0
  end

  it "remembers the inventory page and highlighted item when reopened" do
    run = run_with [Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)]
    run.press "i", "d"
    expect(run.menu.page_name).to eq "weapons"
    run.press "Escape", "i"

    expect(run.menu.page_name).to eq "weapons"
    expect(run.menu.entries.any?(&.text.includes?("dagger"))).to be_true
    expect(run.play.tooltip.showing?).to be_true
  end

  it "lets f type into a modern text field" do
    run = run_with
    run.play.show_options
    run.render
    run.press "End"
    form = run.play.options_screen.form
    before = form["name"].to_s
    expect(run.play.options_screen.focused_row.try(&.key)).to eq "name"
    run.press "f"

    expect(form["name"]).to eq "#{before}f"
    expect(run.turn).to eq 0
  end

  it "resets a selected theme color from its modern action row" do
    theme = Roguelike::Ui::Theme.current
    begin
      Roguelike::Ui::Theme.current = Roguelike::Ui::Theme::DEFAULT.with(
        "granite", TermBuf::Color.rgb(1, 2, 3))
      run = run_with
      run.play.show_options
      run.play.options_screen.show_theme_editor run.session.app
      run.render
      editor = run.play.options_screen.theme_editor
      run.press "f"
      expect(editor.picking?).to be_true
      run.press "Escape"
      run.press "s", "f"

      expect(Roguelike::Ui::Theme.current.granite).to eq Roguelike::Ui::Theme::DEFAULT.granite
    ensure
      Roguelike::Ui::Theme.current = theme
    end
  end

  it "keeps end-screen choices visible at the minimum terminal size" do
    options
    run = Playing.open Game.start(Roguelike::Rng.new(Playing::SEED)), 40, 16
    run.game.perform Roguelike::Action::Ascend.new
    run.play.refresh
    drawn = run.text

    expect(drawn).to contain "Play again"
    expect(drawn).to contain "[ Quit ]"
    expect(run.play.finished?).to be_false
    run.press "f"
    expect(run.play.finished?).to be_true
  end

  it "restores traditional title shortcuts after using the shared catalog" do
    chosen = options
    chosen.control_scheme = Options::ControlScheme::Traditional
    run = Playing.open
    run.press "F2", "Escape"
    run.play.show_title
    run.press "a"

    expect(run.entry.asking?).to be_true
    expect(run.menu.showing?).to be_false
    expect(run.game.turn).to eq 0
  end

  it "keeps empty-target feedback readable at 40 columns" do
    options
    floor = Playing.daylight Roguelike::Floor.parse("compact", ["#####", "#...#", "#...#", "#####"])
    game = Game.new Roguelike::World.new(Playing::SEED, {floor.id => floor}),
      Roguelike::Player.new(floor.id, 2, 1)
    run = Playing.open game, 40, 16
    choose_command run, "Read a scroll"

    expect(run.text).to contain "You have nothing to read."
    expect(run.text).to contain "Escape goes back."
    expect(run.turn).to eq 0
  end

  it "returns from catalog inventory to the catalog that opened it" do
    run = run_with [Item.new(Kind::Dagger)]
    choose_command run, "Inventory"
    expect(run.menu.title).to eq "Inventory"
    run.press "Escape"

    expect(run.menu.showing?).to be_true
    expect(run.menu.title).to eq "Action catalog"
    expect(run.turn).to eq 0
  end
end
