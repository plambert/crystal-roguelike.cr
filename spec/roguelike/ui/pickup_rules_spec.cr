require "../../spec_helper"

Spectator.describe "the pickup rules on the options screen" do
  alias Action = Roguelike::Action
  alias Group = Roguelike::ItemFilter::Group
  alias Options = Roguelike::Options
  alias Outcome = Roguelike::Pickup::Outcome
  alias Pickup = Roguelike::Pickup
  alias Placards = Roguelike::Ui::Placards
  alias Rule = Roguelike::Pickup::Rule
  alias Trait = Roguelike::ItemFilter::Trait

  # A state directory of the spec's own, so nothing reaches the person's.
  def state : Path
    Path[File.tempname "roguelike-pickup-rules", nil].tap { |made| Dir.mkdir_p made }
  end

  # A run with its options screen writing under *root*.
  def run_under(root : Path, title : Bool = false) : Playing::Run
    run = Playing.open title: title
    run.play.options_screen.root = root
    run
  end

  def editor(run : Playing::Run) : Roguelike::Ui::FilterEditor(Outcome)
    run.play.options_screen.pickup_editor
  end

  # Opens the options screen, and the rules from its last row but one.
  def open_rules(run : Playing::Run, first : String = "O") : Nil
    run.press first, "End", "Up", "Enter"
  end

  def rules(run : Playing::Run) : Pickup::Rules
    run.play.game.pickup_rules
  end

  let(root) { state }

  before_each { Options.current = Options.read(root) }

  after_each do
    Options.current = nil
    Roguelike::Tester.current = nil
    FileUtils.rm_rf root.to_s
  end

  it "opens from the Pickup rules row and closes back to the options" do
    run = run_under root
    open_rules run

    expect(editor(run).showing?).to be_true
    expect(run.text).to contain "1. Any gold"
    expect(run.text).to contain "6. Anything that stacks with what you carry"
    expect(run.text).to contain "Anything else"

    run.press "Escape"
    expect(editor(run).showing?).to be_false
    expect(run.play.options_screen.showing?).to be_true
  end

  it "removes a rule from the character's rules during play, and not the file" do
    run = run_under root
    turn = run.turn
    open_rules run

    run.press "-"

    expect(rules(run).rules.size).to eq 5
    expect(rules(run).rules.first).to eq Pickup.default.rules[1]
    expect(run.turn).to eq turn
    expect(File.exists? Options.path(root)).to be_false
  end

  it "moves a rule down" do
    run = run_under root
    open_rules run

    run.press "]"

    expect(rules(run).rules[0]).to eq Pickup.default.rules[1]
    expect(rules(run).rules[1]).to eq Pickup.default.rules[0]
  end

  it "adds a rule and opens it to edit" do
    run = run_under root
    open_rules run

    run.press "End", "+"

    expect(editor(run).rule_editor.showing?).to be_true
    expect(rules(run).rules.size).to eq 7
    expect(rules(run).rules.last).to eq Rule.new(Outcome::Take)
  end

  it "edits the sort of item a rule is about from a menu" do
    run = run_under root
    open_rules run

    run.press "End", "+", "Enter"
    expect(run.text).to contain "Throwing weapon"
    run.press "Down", "Down", "Down", "Enter"

    expect(rules(run).rules.last).to eq Rule.new(Outcome::Take, Group::Weapon)
    expect(run.text).to contain "Any melee weapon: take"
  end

  it "edits what a rule asks and what it decides" do
    run = run_under root
    open_rules run

    run.press "End", "+", "End", "Right"
    expect(rules(run).rules.last.outcome).to eq Outcome::Leave

    run.press "Up", "Right"
    expect(rules(run).rules.last.wants? Trait::Better).to be_true
    run.press "Right"
    expect(rules(run).rules.last.wants? Trait::Better).to be_false
    run.press "Left", "Left"
    expect(rules(run).rules.last.tests).to be_empty

    run.press "Escape"
    expect(editor(run).showing?).to be_true
    expect(run.text).to contain "7. Anything"
  end

  it "walks from the rules to the rows under them and back" do
    run = run_under root
    open_rules run

    run.press "End", "Down"
    expect(editor(run).listing?).to be_false
    run.press "Left"
    expect(rules(run).otherwise).to eq Outcome::Take

    run.press "Up"
    expect(editor(run).listing?).to be_true
    expect(editor(run).list.selected).to eq 5

    run.press "Tab"
    expect(editor(run).listing?).to be_false
    run.press "Shift+Tab"
    expect(editor(run).listing?).to be_true
  end

  it "puts the default rules back" do
    run = run_under root
    run.play.game.perform Action::Configure.new(pickup: Pickup::Rules.new(Array(Rule).new, Outcome::Take))
    open_rules run
    expect(run.text).to contain "No rules"

    run.press "End", "Enter"

    expect(rules(run)).to eq Pickup.default
    expect(run.text).to contain "1. Any gold"
  end

  it "adds a rule from the row under the rules" do
    run = run_under root
    open_rules run

    run.press "End", "Down", "Down", "Enter"

    expect(rules(run).rules.size).to eq 7
    expect(editor(run).rule_editor.showing?).to be_true
  end

  it "shows the character's own rules during play" do
    run = run_under root
    run.play.game.perform Action::Configure.new(
      pickup: Pickup::Rules.new([Rule.new(Outcome::Take, Group::Potion)], Outcome::Leave))
    open_rules run

    expect(run.text).to contain "1. Any potion"
    expect(run.text).not_to contain "Any gold"
  end

  it "sets what a new character starts with from the title screen" do
    run = run_under root, title: true
    open_rules run, Placards::OPTIONS_KEY.to_s

    run.press "-"

    stored = JSON.parse(File.read Options.path(root))["pickup"]["rules"].as_a
    expect(stored.size).to eq 5
    expect(rules(run)).to eq Pickup.default
    expect(Options.read(root).pickup.rules.size).to eq 5
  end

  it "gives a new character the rules in the options" do
    options = Options.new
    options.pickup = Pickup::Rules.new [Rule.new(Outcome::Take, Group::Gold)], Outcome::Leave
    Options.current = options
    run = run_under root, title: true

    run.press Placards::NEW_KEY.to_s, "Enter"

    expect(rules(run)).to eq options.pickup
  end

  it "answers the modern letters" do
    options = Options.new
    options.control_scheme = Options::ControlScheme::Modern
    Options.current = options
    run = run_under root
    run.play.show_options
    run.press "End", "Up", "Enter"

    run.press "s", "s"
    expect(editor(run).list.selected).to eq 2
    run.press "w", "f"
    expect(editor(run).rule_editor.showing?).to be_true
  end

  it "keeps the rows under the rules in view on a short screen" do
    run = run_under root
    many = Array.new(30) { Rule.new Outcome::Take, Group::Potion }
    run.play.game.perform Action::Configure.new(pickup: Pickup::Rules.new(many, Outcome::Leave))
    open_rules run

    expect(run.text).to contain "Anything else"
    expect(run.text).to contain " 1. Any potion"
    run.press "End"
    expect(run.text).to contain "30. Any potion"
  end
end
