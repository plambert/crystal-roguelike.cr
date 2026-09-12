require "../../spec_helper"

Spectator.describe Roguelike::Ui::Keys do
  # An application over a buffer with the game's own keys on it, and the
  # counter that says whether the quit binding fired.
  record Wired,
    session : Headless::Session,
    help : TermBuf::Widgets::HelpOverlay,
    quits : Array(Bool)

  def wired(columns : Int32 = 80, rows : Int32 = 24) : Wired
    screen = Roguelike::Ui::Screen.new
    screen.fit columns, rows
    screen.scaffold 20260911_u64

    session = Headless.open screen.root, columns, rows
    quits = [] of Bool
    help = described_class.install(session.app) { quits << true }

    session.render
    Wired.new session, help, quits
  end

  describe "Q" do
    it "asks to leave" do
      run = wired

      run.session.press "Q"

      expect(run.quits.size).to eq 1
    end

    it "does not fire on a lowercase q, which quaffs" do
      run = wired

      run.session.press "q"

      expect(run.quits).to be_empty
    end
  end

  describe "the help overlay" do
    it "is down to begin with" do
      expect(wired.help.open?).to be_false
    end

    it "comes up on a question mark" do
      run = wired

      run.session.press "?"

      expect(run.help.open?).to be_true
    end

    it "comes up on F1" do
      run = wired

      run.session.press "F1"

      expect(run.help.open?).to be_true
    end

    it "goes down again on Escape" do
      run = wired

      run.session.press "?"
      run.session.press "Escape"

      expect(run.help.open?).to be_false
    end

    it "lists the keys that work" do
      run = wired

      run.session.press "?"
      drawn = run.session.text

      expect(drawn).to contain "leave the game"
      expect(drawn).to contain "show the keys that work here"
    end

    # It is modal, so the application's own keys are out of reach while it is
    # up. That is what modal means, and Escape is the way back.
    it "holds the keyboard while it is up" do
      run = wired

      run.session.press "?"
      run.session.press "Q"

      expect(run.quits).to be_empty
    end

    it "gives the keyboard back when it goes down" do
      run = wired

      run.session.press "?"
      run.session.press "Escape"
      run.session.press "Q"

      expect(run.quits.size).to eq 1
    end
  end
end
