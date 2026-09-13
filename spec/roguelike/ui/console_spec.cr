require "../../spec_helper"

Spectator.describe "the debug console on the keyboard" do
  alias ConsolePane = Roguelike::Ui::ConsolePane
  alias Kind = Roguelike::ItemKind

  # A run with the console built, the way `--debug-console` starts one.
  def debugging : Playing::Run
    Playing.open Playing.field(30, 16), 80, 24, console: true
  end

  # The pane, or a failure saying the run was opened without one.
  def pane(run : Playing::Run) : ConsolePane
    found = run.console
    raise "this run has no debug console" unless found

    found
  end

  describe "with --debug-console" do
    it "opens on the backquote" do
      run = debugging

      run.press ConsolePane::TOGGLE

      expect(pane(run).showing?).to be_true
    end

    it "closes on the backquote a second time" do
      run = debugging

      run.press ConsolePane::TOGGLE
      run.press ConsolePane::TOGGLE

      expect(pane(run).showing?).to be_false
    end

    it "closes on Escape" do
      run = debugging

      run.press ConsolePane::TOGGLE
      run.press "Escape"

      expect(pane(run).showing?).to be_false
    end

    it "runs what is typed and shows what came back" do
      run = debugging

      run.press ConsolePane::TOGGLE
      run.type "spawn bow"
      run.press "Enter"

      expect(pane(run).console.lines.last).to eq "a - a bow"
      expect(run.game.player.inventory['a'].try &.kind).to eq Kind::Bow
    end

    it "draws what came back in the box" do
      run = debugging

      run.press ConsolePane::TOGGLE
      run.type "spawn bow"
      run.press "Enter"

      expect(run.text).to contain "a - a bow"
    end

    it "empties the line after the command runs" do
      run = debugging

      run.press ConsolePane::TOGGLE
      run.type "light"
      run.press "Enter"

      expect(pane(run).field.text).to eq ""
    end

    # A movement key typed into the box is text. The character must not walk
    # while somebody is typing.
    it "keeps the game from answering a key while it is up" do
      run = debugging
      before = run.at

      run.press ConsolePane::TOGGLE
      run.type "l"

      expect(run.at).to eq before
      expect(pane(run).field.text).to eq "l"
    end

    it "puts the character where goto sent them" do
      run = debugging

      run.press ConsolePane::TOGGLE
      run.type "goto 3,3"
      run.press "Enter"
      run.press "Escape"

      expect(run.at).to eq({3, 3})
      expect(run.map.screen_of 3, 3).not_to be_nil
    end

    # The console is a box over the screen, so nothing behind it answers a
    # pointer either.
    it "is modal" do
      run = debugging

      run.press ConsolePane::TOGGLE

      expect(run.play.modal?).to be_true
    end

    it "walks back through what was typed" do
      run = debugging

      run.press ConsolePane::TOGGLE
      run.type "light"
      run.press "Enter"
      run.press "Up"

      expect(pane(run).field.text).to eq "light"
    end

    it "completes a command name" do
      run = debugging

      run.press ConsolePane::TOGGLE
      run.type "rem"
      run.press "Tab"

      expect(pane(run).field.text).to eq "remove-curse"
    end

    it "lists the key in the help overlay" do
      run = debugging

      expect(run.play.bindings.bindings.any? do |entry|
        entry.description == "open the debug console"
      end).to be_true
    end
  end

  describe "without --debug-console" do
    it "builds no console at all" do
      expect(Playing.open(Playing.field(30, 16), 80, 24).console).to be_nil
    end

    it "leaves the backquote unbound" do
      run = Playing.open Playing.field(30, 16), 80, 24
      before = run.text

      run.press ConsolePane::TOGGLE

      expect(run.text).to eq before
    end

    it "binds nothing for it" do
      run = Playing.open Playing.field(30, 16), 80, 24

      expect(run.play.bindings.bindings.any? do |entry|
        entry.description == "open the debug console"
      end).to be_false
    end
  end
end
