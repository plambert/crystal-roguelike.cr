require "../../spec_helper"

Spectator.describe Roguelike::Ui::FocusRing do
  alias Panel = Roguelike::Ui::FocusRing::Panel

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
    it "moves the focus to the panel a left click lands in" do
      run = Playing.open

      run.click *middle(run.screen.info)
      expect(run.play.ring.current).to eq Panel::Info

      run.click *middle(run.screen.log)
      expect(run.play.ring.current).to eq Panel::Log

      run.click *middle(run.screen.map)
      expect(run.play.ring.current).to eq Panel::Map
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
end
