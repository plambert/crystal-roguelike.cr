require "../../spec_helper"

Spectator.describe Roguelike::Ui::FocusRing do
  alias Panel = Roguelike::Ui::FocusRing::Panel
  alias Palette = Roguelike::Ui::Palette

  # The style drawn at *x*, *y*.
  def drawn_style(run : Playing::Run, x : Int32, y : Int32) : TermBuf::Style
    found = run.buffer.hit x, y
    raise "nothing is drawn at #{x},#{y}" unless found

    run.buffer.styles[found.cell.style]
  end

  # The screen, then a blank row, then one row of marks for each row of
  # the screen. `T` is a cell on the focus ground, `R` a cell in the rule's
  # focus color, and `.` any other cell.
  def marked(run : Playing::Run) : String
    text = run.text
    marks = (0...run.buffer.height).map do |row|
      String.build do |line|
        run.buffer.width.times do |column|
          style = drawn_style run, column, row
          line << if style.background == Palette::FOCUS_GROUND
            'T'
          elsif style.foreground == Palette::FOCUS_RULE.foreground
            'R'
          else
            '.'
          end
        end
      end
    end

    "#{text}\n\n#{marks.join '\n'}"
  end

  # The center of *widget*, in buffer cells.
  def middle(widget : TermBuf::Widgets::Widget) : {Int32, Int32}
    box = widget.rect
    {box.x + box.width // 2, box.y + box.height // 2}
  end

  describe "Tab" do
    it "starts on the map" do
      expect(Playing.open.play.ring.current).to eq Panel::Map
    end

    it "moves from the map to the info panel, the log and back" do
      run = Playing.open
      seen = (1..3).map do
        run.press "Tab"
        run.play.ring.current
      end

      expect(seen).to eq [Panel::Info, Panel::Log, Panel::Map]
    end

    it "goes the other way with Shift+Tab" do
      run = Playing.open
      seen = (1..3).map do
        run.press "Shift+Tab"
        run.play.ring.current
      end

      expect(seen).to eq [Panel::Log, Panel::Info, Panel::Map]
    end

    it "passes over a hidden info panel" do
      run = Playing.open columns: 50, rows: 20

      run.press "Tab"
      expect(run.play.ring.current).to eq Panel::Log

      run.press "Tab"
      expect(run.play.ring.current).to eq Panel::Map
    end

    it "gives the map the focus when a resize hides the info panel" do
      run = Playing.open
      run.press "Tab"

      run.resize 50, 20

      expect(run.play.ring.current).to eq Panel::Map
    end

    it "stays inside an open menu" do
      run = Playing.open
      run.press "i"
      expect(run.menu.showing?).to be_true

      run.press "Tab"

      expect(run.menu.showing?).to be_true
      expect(run.play.ring.current).to eq Panel::Map
    end

    it "stays inside the message history" do
      run = Playing.open
      run.press Roguelike::Ui::HistoryPane::TOGGLE
      expect(run.play.history.showing?).to be_true

      run.press "Tab"

      expect(run.play.history.showing?).to be_true
      expect(run.play.ring.current).to eq Panel::Map
    end
  end

  describe "Escape" do
    it "gives the focus back to the map from the info panel and the log" do
      run = Playing.open

      run.press "Tab", "Escape"
      expect(run.play.ring.current).to eq Panel::Map

      run.press "Shift+Tab", "Escape"
      expect(run.play.ring.current).to eq Panel::Map
    end

    it "takes back a command waiting for a direction while the map has the focus" do
      run = Playing.open
      run.press "G"
      expect(run.play.pending).not_to be_nil

      run.press "Escape"

      expect(run.play.pending).to be_nil
    end
  end

  describe "the game's keys" do
    it "move the character while the info panel has the focus" do
      run = Playing.open Playing.field(20, 12)
      before = run.at

      run.press "Tab", "l"

      expect(run.play.ring.current).to eq Panel::Info
      expect(run.at).to eq({before[0] + 1, before[1]})
    end

    it "move the character while the log has the focus" do
      run = Playing.open Playing.field(20, 12)
      before = run.at

      run.press "Shift+Tab", "j"

      expect(run.play.ring.current).to eq Panel::Log
      expect(run.at).to eq({before[0], before[1] + 1})
    end
  end

  describe "the pointer" do
    it "moves the focus to the map or the log on a left click" do
      run = Playing.open

      run.click *middle(run.screen.log)
      expect(run.play.ring.current).to eq Panel::Log

      run.click *middle(run.screen.map)
      expect(run.play.ring.current).to eq Panel::Map
    end

    it "leaves the focus alone on a click in the info panel" do
      run = Playing.open

      run.click *middle(run.screen.info)
      expect(run.play.ring.current).to eq Panel::Map

      run.press "Tab"
      run.press "Tab"
      run.click *middle(run.screen.info)
      expect(run.play.ring.current).to eq Panel::Log
    end

    it "does not move the focus with the wheel" do
      run = Playing.open

      run.wheel *middle(run.screen.log)
      run.wheel *middle(run.screen.info), up: false

      expect(run.play.ring.current).to eq Panel::Map
    end

    it "does not move the focus while a menu is up" do
      run = Playing.open
      run.press "i"

      run.click 1, 1

      expect(run.play.ring.current).to eq Panel::Map
    end
  end

  describe "the tint" do
    it "puts the focused info panel on the focus ground" do
      run = Playing.open
      run.press "Tab"

      expect(run.screen.info_panel.style.try &.background).to eq Palette::FOCUS_GROUND
      expect(run.screen.log.style).to be_nil
    end

    it "moves to the log and leaves the info panel as it was" do
      run = Playing.open
      run.press "Tab", "Tab"

      expect(run.screen.log.style.try &.background).to eq Palette::FOCUS_GROUND
      expect(run.screen.info_panel.style).to be_nil
    end

    it "fades from the flash to the gray when motion is on" do
      run = Playing.open clock: true, motion: true
      run.press "Tab"

      expect(run.screen.info_panel.style.try &.background).to eq Palette::FOCUS_FLASH

      run.run_timers

      expect(run.screen.info_panel.style.try &.background).to eq Palette::FOCUS_GROUND
    end

    it "draws the rules beside the focused panel in the focus color" do
      run = Playing.open

      expect(run.screen.gutter.style).to eq Palette::FOCUS_RULE
      expect(run.screen.rule.style).to eq Palette::FOCUS_RULE

      run.press "Tab"
      expect(run.screen.gutter.style).to eq Palette::FOCUS_RULE
      expect(run.screen.rule.style).to be_nil

      run.press "Tab"
      expect(run.screen.gutter.style).to be_nil
      expect(run.screen.rule.style).to eq Palette::FOCUS_RULE
    end
  end

  describe "the screen at 80 by 24" do
    it "marks the map's rules when the map has the focus" do
      run = Playing.open
      drawn = marked run

      expect(drawn).to eq Fixture.expected("screen/focus-map.txt", drawn)
    end

    it "tints the info panel when it has the focus" do
      run = Playing.open
      run.press "Tab"
      drawn = marked run

      expect(drawn).to eq Fixture.expected("screen/focus-info.txt", drawn)
    end

    it "tints the log when it has the focus" do
      run = Playing.open
      run.press "Shift+Tab"
      drawn = marked run

      expect(drawn).to eq Fixture.expected("screen/focus-log.txt", drawn)
    end
  end
end
