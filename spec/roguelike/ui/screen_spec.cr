require "../../spec_helper"

Spectator.describe Roguelike::Ui::Screen do
  # A screen fitted to *columns* by *rows*, and filled. Every example here
  # measures one of these.
  def laid_out(columns : Int32, rows : Int32) : Roguelike::Ui::Screen
    screen = Roguelike::Ui::Screen.new
    screen.fit columns, rows

    Headless.open(screen.root, columns, rows).render
    screen
  end

  describe "at 80 by 24" do
    subject(screen) { laid_out 80, 24 }

    it "fills the screen" do
      expect(screen.root.rect).to eq TermBuf::Rect.new(0, 0, 80, 24)
    end

    it "gives the map everything the sidebar and the rule do not take" do
      expect(screen.map.rect).to eq TermBuf::Rect.new(0, 0, 55, 19)
    end

    it "puts the rule between the map and the sidebar" do
      expect(screen.gutter.rect).to eq TermBuf::Rect.new(55, 0, 1, 19)
    end

    it "holds the sidebar at its own width" do
      expect(screen.sidebar.rect)
        .to eq TermBuf::Rect.new(56, 0, Roguelike::Ui::Screen::SIDEBAR_WIDTH, 19)
    end

    it "gives the log its rows across the whole screen" do
      expect(screen.log.rect)
        .to eq TermBuf::Rect.new(0, 20, 80, Roguelike::Ui::Screen::LOG_ROWS)
    end

    it "leaves no row unaccounted for" do
      expect(screen.map.rect.height + 1 + screen.log.rect.height).to eq 24
    end
  end

  describe "at 200 by 50" do
    subject(screen) { laid_out 200, 50 }

    it "gives the extra width to the map and not to the sidebar" do
      expect(screen.map.rect.width).to eq 175
      expect(screen.sidebar.rect.width).to eq Roguelike::Ui::Screen::SIDEBAR_WIDTH
    end

    it "gives the extra height to the map and not to the log" do
      expect(screen.map.rect.height).to eq 45
      expect(screen.log.rect.height).to eq Roguelike::Ui::Screen::LOG_ROWS
    end
  end

  describe "#fit" do
    it "keeps the sidebar at the narrowest width it is shown at" do
      screen = laid_out Roguelike::Ui::Screen::SIDEBAR_MINIMUM_COLUMNS, 24

      expect(screen.sidebar?).to be_true
    end

    it "drops the sidebar rather than squeezing the map" do
      screen = laid_out Roguelike::Ui::Screen::SIDEBAR_MINIMUM_COLUMNS - 1, 24

      expect(screen.sidebar?).to be_false
    end

    it "gives the whole width to the map once the sidebar has gone" do
      screen = laid_out 50, 20

      expect(screen.map.rect).to eq TermBuf::Rect.new(0, 0, 50, 15)
    end

    it "takes no room for a sidebar that is not there" do
      screen = laid_out 50, 20

      expect(screen.sidebar.rect.width).to eq 0
      expect(screen.gutter.rect.width).to eq 0
    end

    it "brings the sidebar back when there is room again" do
      screen = Roguelike::Ui::Screen.new
      session = Headless.open screen.root, 40, 20

      screen.fit 40, 20
      session.render
      expect(screen.sidebar?).to be_false

      screen.fit 100, 20
      session.resize 100, 20
      session.render
      expect(screen.sidebar?).to be_true
      expect(screen.sidebar.rect.width).to eq Roguelike::Ui::Screen::SIDEBAR_WIDTH
    end
  end

  describe ".fits?" do
    it "takes a terminal at the minimum" do
      expect(described_class.fits?(40, 16)).to be_true
    end

    it "refuses one a column short" do
      expect(described_class.fits?(39, 16)).to be_false
    end

    it "refuses one a row short" do
      expect(described_class.fits?(40, 15)).to be_false
    end
  end

  describe "the notice" do
    it "is down while there is room for the game" do
      screen = laid_out 40, 16

      expect(screen.playing?).to be_true
      expect(screen.notice.hidden?).to be_true
    end

    it "replaces the game when the terminal is too narrow" do
      screen = laid_out 39, 16

      expect(screen.playing?).to be_false
      expect(screen.notice.hidden?).to be_false
    end

    it "replaces the game when the terminal is too short" do
      screen = laid_out 40, 15

      expect(screen.playing?).to be_false
    end

    it "says what is needed and what there is" do
      screen = laid_out 24, 8

      expect(screen.notice_text.text).to contain "40 columns and 16 rows"
      expect(screen.notice_text.text).to contain "24 by 8"
    end

    it "takes no room from the game it is not replacing" do
      screen = laid_out 80, 24

      expect(screen.notice.rect.height).to eq 0
      expect(screen.map.rect).to eq TermBuf::Rect.new(0, 0, 55, 19)
    end

    it "goes away again when the window is made larger" do
      screen = Roguelike::Ui::Screen.new
      session = Headless.open screen.root, 30, 10

      screen.fit 30, 10
      session.render
      expect(screen.playing?).to be_false

      screen.fit 80, 24
      session.resize 80, 24
      session.render
      expect(screen.playing?).to be_true
      expect(screen.map.rect).to eq TermBuf::Rect.new(0, 0, 55, 19)
    end

    it "draws what it drew last time" do
      screen = Roguelike::Ui::Screen.new
      screen.fit 30, 10

      drawn = Headless.open(screen.root, 30, 10).text

      expect(drawn).to eq Fixture.expected("screen/30x10-too-small.txt", drawn)
    end
  end

  describe ".map_rows" do
    it "takes the rule and the log off the height" do
      expect(described_class.map_rows(24)).to eq 19
    end

    it "does not go negative on a screen with no room at all" do
      expect(described_class.map_rows(2)).to eq 0
    end
  end

  describe "the whole screen" do
    it "draws what it drew last time at 80 by 24" do
      screen = Roguelike::Ui::Screen.new
      screen.fit 80, 24

      drawn = Headless.open(screen.root, 80, 24).text

      expect(drawn).to eq Fixture.expected("screen/80x24.txt", drawn)
    end

    it "draws what it drew last time at 200 by 50" do
      screen = Roguelike::Ui::Screen.new
      screen.fit 200, 50

      drawn = Headless.open(screen.root, 200, 50).text

      expect(drawn).to eq Fixture.expected("screen/200x50.txt", drawn)
    end

    it "draws what it drew last time with no sidebar" do
      screen = Roguelike::Ui::Screen.new
      screen.fit 50, 20

      drawn = Headless.open(screen.root, 50, 20).text

      expect(drawn).to eq Fixture.expected("screen/50x20-no-sidebar.txt", drawn)
    end
  end
end
