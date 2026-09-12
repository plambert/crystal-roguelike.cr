require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Prompt do
  alias Widgets = TermBuf::Widgets

  # A prompt in a panel, over a buffer, with the answers it was given.
  record Asked,
    prompt : Widgets::Prompt,
    session : Headless::Session,
    answers : Array(Char?)

  # The row a prompt draws its question on. The box takes one row above it.
  def said(session : Headless::Session) : String
    session.rows.find(&.includes?('[')) || ""
  end

  def asked(question : String = "Really leave?", keys : String = "yn",
            default : Char? = 'n', columns : Int32 = 40) : Asked
    prompt = Widgets::Prompt.new
    answers = [] of Char?
    prompt.on_answer = ->(key : Char?) { answers << key; nil }

    root = Widgets::Panel.new(
      width: Widgets::Layout::Sizing.grow,
      height: Widgets::Layout::Sizing.grow)
    root.add prompt

    session = Headless.open root, columns, 3
    prompt.ask session.app, question, keys, default
    session.render

    Asked.new prompt, session, answers
  end

  describe "before a question" do
    it "is hidden and takes no keyboard" do
      prompt = described_class.new

      expect(prompt.asking?).to be_false
      expect(prompt.hidden?).to be_true
      expect(prompt.focusable?).to be_false
    end

    # A prompt is a float. It is not in the tree at all until the first
    # question puts it there.
    it "draws nothing" do
      root = Widgets::Panel.new(
        width: Widgets::Layout::Sizing.grow,
        height: Widgets::Layout::Sizing.grow)

      expect(Headless.open(root, 40, 3).rows).to eq ["", "", ""]
    end
  end

  describe "#ask" do
    it "shows the question and the keys" do
      run = asked

      expect(run.prompt.asking?).to be_true
      expect(said(run.session)).to contain "Really leave?"
      expect(said(run.session)).to contain "[yN]"
    end

    # The convention is an upper case letter for the default answer. `[yN]`
    # says that `n` happens on Enter.
    it "writes the default key in upper case" do
      expect(asked(default: 'y').prompt.offered).to eq "Yn"
      expect(asked(default: nil).prompt.offered).to eq "yn"
    end

    it "takes the keyboard" do
      expect(asked.prompt.focusable?).to be_true
    end

    it "refuses a default that is not one of the keys" do
      run = asked
      expect { run.prompt.ask run.session.app, "Why?", "yn", default: 'q' }
        .to raise_error ArgumentError, /not one of/
    end
  end

  describe "answering" do
    it "takes a key that is offered" do
      run = asked
      run.session.press "y"

      expect(run.answers).to eq ['y']
      expect(run.prompt.asking?).to be_false
      expect(run.prompt.hidden?).to be_true
    end

    it "takes the other key too" do
      run = asked
      run.session.press "n"

      expect(run.answers).to eq ['n']
    end

    it "answers with the default on Enter" do
      run = asked
      run.session.press "Enter"

      expect(run.answers).to eq ['n']
    end

    it "ignores Enter when there is no default" do
      run = asked default: nil
      run.session.press "Enter"

      expect(run.answers).to be_empty
      expect(run.prompt.asking?).to be_true
    end

    it "answers nothing on Escape" do
      run = asked
      run.session.press "Escape"

      expect(run.answers).to eq [nil]
      expect(run.prompt.asking?).to be_false
    end

    # A prompt that let other keys through would run a movement binding while
    # the person was answering a question.
    it "swallows a key that is not offered" do
      run = asked
      run.session.press "h"
      run.session.press "Q"

      expect(run.answers).to be_empty
      expect(run.prompt.asking?).to be_true
    end

    it "answers once and then lets keys past" do
      run = asked
      run.session.press "y"
      run.session.press "y"

      expect(run.answers).to eq ['y']
    end
  end

  describe "#cancel" do
    it "takes the question down and answers nothing" do
      run = asked
      run.prompt.cancel

      expect(run.answers).to eq [nil]
      expect(run.prompt.asking?).to be_false
    end

    it "does nothing when no question is up" do
      prompt = described_class.new
      answers = [] of Char?
      prompt.on_answer = ->(key : Char?) { answers << key; nil }

      prompt.cancel

      expect(answers).to be_empty
    end
  end

  describe "a second question" do
    it "replaces the first" do
      run = asked
      run.prompt.ask run.session.app, "Open which way?", "hjkl"
      run.session.render

      expect(said(run.session)).to contain "Open which way?"
      expect(said(run.session)).to contain "[hjkl]"
      expect(run.answers).to be_empty
    end
  end
end
