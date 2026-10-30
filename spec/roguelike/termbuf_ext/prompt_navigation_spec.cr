require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Prompt do
  alias Widgets = TermBuf::Widgets
  alias Choice = TermBuf::Widgets::Prompt::Choice
  alias Navigation = TermBuf::Widgets::Navigation

  record Asked,
    prompt : Widgets::Prompt,
    session : Headless::Session,
    answers : Array(Char?)

  def asked(question : String = "Really leave?", columns : Int32 = 50,
            rows : Int32 = 5) : Asked
    prompt = Widgets::Prompt.new
    answers = [] of Char?
    prompt.on_answer = ->(key : Char?) { answers << key; nil }

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add prompt
    session = Headless.open root, columns, rows
    prompt.ask session.app, question,
      [Choice.new('y', "Yes"), Choice.new('n', "No")],
      default: 'n', navigation: Navigation.selectable
    session.render

    Asked.new prompt, session, answers
  end

  def readable(run : Asked) : String
    run.session.rows.join(' ').gsub(/[╭╮╰╯─│]/, " ").gsub(/\s+/, " ")
  end

  it "offers named choices with the safe default selected" do
    run = asked

    expect(run.prompt.offered).to contain "No"
    expect(run.prompt.offered).not_to contain "[ Yes ]"
    expect(run.prompt.offered).to contain "[ No ]"
  end

  it "moves with w/s and arrows without binding the option letters" do
    run = asked

    run.session.press "y"
    expect(run.answers).to be_empty
    expect(run.prompt.asking?).to be_true

    run.session.press "w"
    expect(run.prompt.offered).to contain "[ Yes ]"
    run.session.press "Down"
    expect(run.prompt.offered).to contain "[ No ]"
  end

  it "moves across the side-by-side choices with a/d and the left and right arrows" do
    run = asked

    run.session.press "Left"
    expect(run.prompt.offered).to contain "[ Yes ]"
    run.session.press "Right"
    expect(run.prompt.offered).to contain "[ No ]"
    run.session.press "a"
    expect(run.prompt.offered).to contain "[ Yes ]"
    run.session.press "d"
    expect(run.prompt.offered).to contain "[ No ]"
    expect(run.answers).to be_empty
  end

  it "moves across the choices with the left and right arrows under the plain navigation" do
    prompt = Widgets::Prompt.new
    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add prompt
    session = Headless.open root, 50, 5
    prompt.ask session.app, "Really leave?",
      [Choice.new('y', "Yes"), Choice.new('n', "No")],
      default: 'n', navigation: Navigation.new

    session.press "Left"
    expect(prompt.offered).to contain "[ Yes ]"
    session.press "Right"
    expect(prompt.offered).to contain "[ No ]"
    session.press "Up"
    expect(prompt.offered).to contain "[ Yes ]"
  end

  it "confirms the selected safe choice with f or Enter" do
    run = asked
    run.session.press "Enter"

    expect(run.answers).to eq ['n']
    expect(run.prompt.asking?).to be_false
  end

  it "confirms an explicitly chosen answer with f and cancels with Escape" do
    run = asked
    run.session.press "w"
    run.session.press "f"
    expect(run.answers).to eq ['y']

    canceled = asked
    canceled.session.press "Escape"
    expect(canceled.answers).to eq [nil]
  end

  it "shows both answers inside a 40 by 16 screen for a long exit question" do
    run = asked "Leave the dungeon by this staircase?", 40, 16
    screen = readable(run)

    expect(screen).to contain "Leave the dungeon"
    expect(screen).to contain "Yes"
    expect(screen).to contain "[ No ]"
    expect(run.prompt.rect.x).to be >= 0
    expect(run.prompt.rect.y).to be >= 0
    expect(run.prompt.rect.x + run.prompt.rect.width).to be <= 40
    expect(run.prompt.rect.y + run.prompt.rect.height).to be <= 16

    run.session.press "w"
    expect(run.prompt.offered).to contain "[ Yes ]"
    run.session.press "s"
    expect(run.prompt.offered).to contain "[ No ]"
    run.session.press "f"
    expect(run.answers).to eq ['n']

    canceled = asked "Leave the dungeon by this staircase?", 40, 16
    canceled.session.press "Escape"
    expect(canceled.answers).to eq [nil]
  end

  it "wraps a longer question and keeps answers visible at compact and wide sizes" do
    question = "Are you sure you want to leave the dungeon by this staircase? " \
               "This ends the expedition and abandons every item you are carrying."

    [{40, 16}, {80, 24}].each do |columns, rows|
      run = asked question, columns, rows
      screen = readable(run)

      expect(screen).to contain "Are you sure you want"
      expect(screen).to contain "every item you are carrying."
      expect(screen).to contain "Yes"
      expect(screen).to contain "[ No ]"
      expect(run.prompt.rect.x + run.prompt.rect.width).to be <= columns
      expect(run.prompt.rect.y + run.prompt.rect.height).to be <= rows

      run.session.press "w"
      run.session.press "s"
      run.session.press "f"
      expect(run.answers).to eq ['n']
    end
  end

  it "preserves the selected answer when a wide prompt is resized" do
    run = asked "Leave the dungeon by this staircase?", 80, 24
    run.session.press "w"
    run.session.resize 40, 16
    run.prompt.refit run.session.app.tree.screen

    expect(readable(run)).to contain "[ Yes ]"
    expect(readable(run)).to contain "No"
    expect(run.prompt.rect.right).to be <= 40
    expect(run.prompt.rect.bottom).to be <= 16
    expect(run.answers).to be_empty
  end
end
