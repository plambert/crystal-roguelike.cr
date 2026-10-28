require "../../spec_helper"

Spectator.describe "the explore page of the options screen" do
  alias Action = Roguelike::Action
  alias Options = Roguelike::Options
  alias Placards = Roguelike::Ui::Placards
  alias Settings = Roguelike::Explore::Settings

  # A state directory of the spec's own, so nothing reaches the person's.
  def state : Path
    Path[File.tempname "roguelike-explore-page", nil].tap { |made| Dir.mkdir_p made }
  end

  # A run with its options screen writing under *root*.
  def run_under(root : Path, title : Bool = false) : Playing::Run
    run = Playing.open title: title
    run.play.options_screen.root = root
    run
  end

  # The explore page, once it has been opened.
  def page(run : Playing::Run) : Roguelike::Ui::OptionsScreen
    run.play.options_screen.explore_page.as(Roguelike::Ui::OptionsScreen)
  end

  # Opens the options screen, and the explore page from its last row but one.
  def open_page(run : Playing::Run, first : String = "O") : Nil
    run.press first, "End", "Up", "Enter"
  end

  let(root) { state }

  before_each { Options.current = Options.read(root) }

  after_each do
    Options.current = nil
    Roguelike::Tester.current = nil
    FileUtils.rm_rf root.to_s
  end

  it "opens from the Explore row and closes back to the options" do
    run = run_under root
    open_page run

    expect(page(run).showing?).to be_true
    expect(run.text).to contain "Where to walk"
    expect(run.text).to contain "Reach"

    run.press "Escape"
    expect(page(run).showing?).to be_false
    expect(run.play.options_screen.showing?).to be_true
  end

  it "changes the character's settings during play, and not the file" do
    run = run_under root
    turn = run.turn
    open_page run

    run.press "Down", "Down", "Space"

    expect(run.play.game.explore_settings.gold?).to be_false
    expect(run.turn).to eq turn
    expect(File.exists? Options.path(root)).to be_false
  end

  it "shows the character's own settings during play" do
    run = run_under root
    run.play.game.perform Action::Configure.new(Settings.parse "reach=2")
    open_page run

    expect(page(run).form["explore.reach"]).to eq 2
  end

  it "sets what a new character starts with from the title screen" do
    run = run_under root, title: true
    open_page run, Placards::OPTIONS_KEY.to_s

    run.press "Down", "Down", "Space"

    expect(JSON.parse(File.read Options.path(root))["explore"]["gold"]).to eq false
    expect(run.play.game.explore_settings.gold?).to be_true
  end

  it "gives a new character the settings in the options" do
    options = Options.new
    options.explore = Settings.parse "gold=off,stop=stairs"
    Options.current = options
    run = run_under root, title: true

    run.press Placards::NEW_KEY.to_s, "Enter"

    expect(run.play.game.explore_settings).to eq options.explore
  end
end
