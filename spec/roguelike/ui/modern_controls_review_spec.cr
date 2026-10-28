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
end
