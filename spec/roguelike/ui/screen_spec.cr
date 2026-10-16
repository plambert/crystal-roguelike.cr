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

    it "runs the info panel down the whole left side at its narrow width" do
      expect(screen.info.rect)
        .to eq TermBuf::Rect.new(0, 0, Roguelike::Ui::Screen::INFO_WIDTH, 24)
    end

    it "puts the rule between the info panel and the map" do
      expect(screen.gutter.rect).to eq TermBuf::Rect.new(24, 0, 1, 24)
    end

    it "gives the map everything the info panel, the rules and the log do not take" do
      expect(screen.map.rect).to eq TermBuf::Rect.new(25, 0, 55, 19)
    end

    it "puts the rule under the map" do
      expect(screen.rule.rect).to eq TermBuf::Rect.new(25, 19, 55, 1)
    end

    it "gives the log its rows under the map" do
      expect(screen.log.rect)
        .to eq TermBuf::Rect.new(25, 20, 55, Roguelike::Ui::Screen::LOG_ROWS)
    end

    it "leaves no row unaccounted for" do
      expect(screen.map.rect.height + 1 + screen.log.rect.height).to eq 24
    end

    it "answers the old name with the info panel" do
      expect(screen.sidebar).to be screen.info
    end
  end

  describe "at 200 by 50" do
    subject(screen) { laid_out 200, 50 }

    it "gives the info panel its widest width" do
      expect(screen.info.rect.width).to eq Roguelike::Ui::Screen::INFO_MOST_WIDTH
    end

    it "gives the rest of the extra width to the map" do
      expect(screen.map.rect).to eq TermBuf::Rect.new(37, 0, 163, 43)
    end

    it "gives the log its taller height" do
      expect(screen.log.rect)
        .to eq TermBuf::Rect.new(37, 44, 163, Roguelike::Ui::Screen::TALL_LOG_ROWS)
    end
  end

  describe ".info_width" do
    {% for pair in [{40, 24}, {80, 24}, {100, 24}, {103, 24}, {104, 25}, {120, 29},
                    {140, 34}, {147, 35}, {148, 36}, {200, 36}, {400, 36}] %}
      it "is {{ pair[1] }} at {{ pair[0] }} columns" do
        expect(described_class.info_width({{ pair[0] }})).to eq {{ pair[1] }}
      end
    {% end %}
  end

  describe ".log_height" do
    {% for pair in [{16, 4}, {24, 4}, {40, 4}, {41, 6}, {50, 6}, {100, 6}] %}
      it "is {{ pair[1] }} at {{ pair[0] }} rows" do
        expect(described_class.log_height({{ pair[0] }})).to eq {{ pair[1] }}
      end
    {% end %}
  end

  describe ".log_width" do
    it "takes the info panel, the rule and the padding off the width" do
      expect(described_class.log_width(80)).to eq 53
      expect(described_class.log_width(200)).to eq 161
    end

    it "takes only the padding once the info panel has gone" do
      expect(described_class.log_width(50)).to eq 48
    end
  end

  describe "#fit" do
    it "keeps the info panel at the narrowest width it is shown at" do
      screen = laid_out Roguelike::Ui::Screen::INFO_MINIMUM_COLUMNS, 24

      expect(screen.info?).to be_true
    end

    it "drops the info panel rather than squeezing the map" do
      screen = laid_out Roguelike::Ui::Screen::INFO_MINIMUM_COLUMNS - 1, 24

      expect(screen.info?).to be_false
    end

    it "gives the whole width to the map once the info panel has gone" do
      screen = laid_out 50, 20

      expect(screen.map.rect).to eq TermBuf::Rect.new(0, 0, 50, 15)
      expect(screen.log.rect).to eq TermBuf::Rect.new(0, 16, 50, 4)
    end

    it "takes no room for an info panel that is not there" do
      screen = laid_out 50, 20

      expect(screen.info.rect.width).to eq 0
      expect(screen.gutter.rect.width).to eq 0
    end

    it "brings the info panel back when there is room again" do
      screen = Roguelike::Ui::Screen.new
      session = Headless.open screen.root, 40, 20

      screen.fit 40, 20
      session.render
      expect(screen.info?).to be_false

      screen.fit 120, 20
      session.resize 120, 20
      session.render
      expect(screen.info?).to be_true
      expect(screen.info.rect.width).to eq 29
    end

    it "sizes the log again when the terminal grows tall" do
      screen = Roguelike::Ui::Screen.new
      session = Headless.open screen.root, 80, 24

      screen.fit 80, 24
      session.render
      expect(screen.log_rows).to eq 4

      screen.fit 80, 50
      session.resize 80, 50
      session.render
      expect(screen.log.rect.height).to eq 6
      expect(screen.log_rows).to eq 6
    end
  end

  describe "the info panel" do
    # A screen at 80 by 24 with *count* one-row labels in the info panel.
    def holding(count : Int32) : {Roguelike::Ui::Screen, Headless::Session}
      screen = Roguelike::Ui::Screen.new
      screen.fit 80, 24
      labels = Array(TermBuf::Widgets::Widget).new(count) { |index| TermBuf::Widgets::Label.new "row #{index}" }
      labels.each { |label| screen.info.add label }

      session = Headless.open screen.root, 80, 24
      session.render
      {screen, session}
    end

    it "draws a plain rule beside content that fits" do
      _, session = holding 10

      expect(session.rows.map(&.[24])).to all eq '│'
    end

    it "puts a thumb on the rule when the content does not fit" do
      _, session = holding 60

      expect(session.rows.map(&.[24])).to contain '█'
    end

    it "scrolls as one under the wheel" do
      screen, session = holding 60
      session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::WheelDown, 5, 5,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)
      session.render

      expect(screen.info.scroll_y).to be > 0
      expect(session.row(0)).not_to contain "row 0"
    end

    it "takes no keys" do
      screen, _ = holding 60

      expect(screen.info.keymap).to be_nil
      expect(screen.info.focusable?).to be_false
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
      expect(screen.map.rect).to eq TermBuf::Rect.new(25, 0, 55, 19)
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
      expect(screen.map.rect).to eq TermBuf::Rect.new(25, 0, 55, 19)
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

    it "takes the taller log off a tall terminal" do
      expect(described_class.map_rows(50)).to eq 43
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

    it "draws what it drew last time with no info panel" do
      screen = Roguelike::Ui::Screen.new
      screen.fit 50, 20

      drawn = Headless.open(screen.root, 50, 20).text

      expect(drawn).to eq Fixture.expected("screen/50x20-no-info.txt", drawn)
    end
  end
end
