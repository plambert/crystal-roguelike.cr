require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Entry do
  alias Widgets = TermBuf::Widgets

  # An entry in a panel, over a buffer, with what it has been answered with.
  record Shown,
    entry : Widgets::Entry,
    session : Headless::Session,
    answers : Array(String?)

  def shown(question : String = "Who is playing?", value : String = "",
            placeholder : String? = nil,
            columns : Int32 = 60, rows : Int32 = 20) : Shown
    entry = Widgets::Entry.new
    answers = [] of String?
    entry.on_answer = ->(text : String?) { answers << text; nil }

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add entry

    session = Headless.open root, columns, rows
    entry.ask session.app, question, value, placeholder
    session.render

    Shown.new entry, session, answers
  end

  # Types *text* at whatever has the keyboard.
  def type(run : Shown, text : String) : Nil
    text.each_char do |character|
      run.session.send TermBuf::Events::Key.new(
        TermBuf::Key.character(character), Bytes.empty)
    end

    run.session.render
  end

  describe "#ask" do
    it "puts the box up" do
      expect(shown.entry.asking?).to be_true
    end

    it "writes the question" do
      run = shown "Who is playing?"

      expect(run.session.text).to contain "Who is playing?"
    end

    it "starts with the line it was given" do
      run = shown value: "Sparky"

      expect(run.entry.text).to eq "Sparky"
      expect(run.session.text).to contain "Sparky"
    end

    it "draws the placeholder on an empty line" do
      run = shown placeholder: "a name"

      expect(run.session.text).to contain "a name"
    end
  end

  describe "typing" do
    it "puts what was typed on the line" do
      run = shown
      type run, "Sparky"

      expect(run.entry.text).to eq "Sparky"
    end

    it "answers with the line on Enter" do
      run = shown
      type run, "Sparky"
      run.session.press "Enter"

      expect(run.answers).to eq ["Sparky"]
      expect(run.entry.asking?).to be_false
    end

    # A placeholder is drawn on an empty line. It is not an answer.
    it "answers with nothing typed on Enter over a bare line" do
      run = shown placeholder: "a name"
      run.session.press "Enter"

      expect(run.answers).to eq [""]
    end

    it "answers nothing on Escape" do
      run = shown
      type run, "Sparky"
      run.session.press "Escape"

      expect(run.answers).to eq [nil]
      expect(run.entry.asking?).to be_false
    end
  end

  describe "#cancel" do
    it "takes the box down and answers nothing" do
      run = shown
      run.entry.cancel

      expect(run.answers).to eq [nil]
      expect(run.entry.asking?).to be_false
    end

    it "does nothing when the box is down" do
      entry = Widgets::Entry.new
      answers = [] of String?
      entry.on_answer = ->(text : String?) { answers << text; nil }

      entry.cancel

      expect(answers).to be_empty
    end
  end

  # The box is modal, so a key nothing in it claims stops there.
  it "holds the keyboard while it is up" do
    reached = [] of String
    entry = Widgets::Entry.new

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add entry

    session = Headless.open root, 60, 20
    session.app.keymap = Widgets::Bindings.build do |map|
      map.bind TermBuf::Key.parse("F5"), "behind the box",
        ->(_context : Widgets::Context) { reached << "F5"; nil }
    end

    entry.ask session.app, "Who is playing?"
    session.render
    session.press "F5"

    expect(reached).to be_empty
  end

  describe "#fit_into" do
    it "leaves a margin on each side" do
      run = shown columns: 40
      box = run.entry.rect

      expect(box.width).to be <= 40 - 2 * Widgets::Entry::COLUMN_MARGIN
    end

    it "never goes below its floor on a narrow screen" do
      run = shown columns: 20
      box = run.entry.rect

      expect(box.width).to be >= Widgets::Entry::LEAST_WIDTH
    end
  end
end
