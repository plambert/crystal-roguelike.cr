require "../../spec_helper"

Spectator.describe Roguelike::Ui::LogPanel do
  alias Panel = Roguelike::Ui::FocusRing::Panel
  alias Palette = Roguelike::Ui::Palette
  alias Screen = Roguelike::Ui::Screen

  # Where a notch of the wheel lands on the log pane of an eighty by
  # twenty-four window.
  OVER_THE_PANE = {40, 21}

  # A run with *count* messages said and every held page read.
  def talkative(count : Int32 = 12, clock : Bool = false, motion : Bool = false) : Playing::Run
    run = Playing.open clock: clock, motion: motion
    run.clear_monsters
    count.times { |number| run.game.log.add "Something number #{number} happened." }
    run.play.refresh
    run.render

    while run.pager.holding?
      run.press "."
    end

    run.run_timers if clock
    run
  end

  # The style drawn at *x*, *y*.
  def drawn_style(run : Playing::Run, x : Int32, y : Int32) : TermBuf::Style
    found = run.buffer.hit x, y
    raise "nothing is drawn at #{x},#{y}" unless found

    run.buffer.styles[found.cell.style]
  end

  # Fires the armed timers one at a time, and answers what each frame drew:
  # the height of the log pane and the lines the pager showed.
  def frames(run : Playing::Run) : Array({Int32, Array(Int32)})
    drawn = [] of {Int32, Array(Int32)}
    100.times do
      break unless run.tick

      run.render
      drawn << {run.screen.log_size, run.pager.shown}
    end
    drawn
  end

  describe "growing on focus" do
    it "grows to show what it holds, up to a quarter of the height" do
      run = talkative

      run.press "Shift+Tab"

      expect(run.screen.log_size).to eq 6
      expect(run.screen.log.rect.height).to eq 6
      expect(run.pager.rows).to eq 6
      expect(run.screen.map.rect.height).to eq 24 - 1 - 6
    end

    it "grows no further than what it holds" do
      run = Playing.open rows: 60
      run.pager.catch_up
      3.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      run.render
      lines = run.pager.lines.size

      run.press "Shift+Tab"

      expect(lines).to be < Screen.log_most(60)
      expect(run.screen.log_size).to eq Math.max(lines, Screen.log_height(60))
    end

    it "never shrinks below its unfocused height" do
      run = Playing.open rows: 60
      run.pager.catch_up

      run.press "Shift+Tab"

      expect(run.screen.log_size).to eq Screen.log_height(60)
    end

    it "grows a row a frame when motion is on" do
      run = talkative clock: true, motion: true

      run.press "Shift+Tab"
      expect(run.screen.log_size).to eq 5

      run.run_timers
      run.render

      expect(run.screen.log_size).to eq 6
      expect(run.screen.log.rect.height).to eq 6
    end

    it "keeps the character in view as the map shrinks" do
      run = Playing.open Playing.field
      12.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      run.pager.catch_up
      x, y = run.at
      rows = run.screen.map.rect.height
      run.map.camera = {run.map.camera[0], y - rows + 1}
      run.render
      expect(run.map.screen_of(x, y)).not_to be_nil

      run.press "Shift+Tab"

      expect(run.screen.map.rect.height).to be < rows
      expect(run.map.screen_of(x, y)).not_to be_nil
    end

    it "keeps the banner's row at every height" do
      run = talkative
      banner = run.screen.show_banner
      banner.text = "the banner"
      run.play.fit 80, 24
      run.render

      run.press "Shift+Tab"

      expect(run.row(24 - 6)).to contain "the banner"
      expect(run.pager.rows).to eq 5
    end
  end

  describe "the scrollbar" do
    it "is blank while everything fits" do
      run = Playing.open
      run.pager.catch_up

      expect(run.pager.lines.size).to be <= run.pager.rows
      (20..23).each { |row| expect(run.row(row)[79]?).to be_nil }
    end

    it "shows while the log holds more than it shows, focused or not" do
      run = talkative

      expect(run.row(23)[79]).to eq '█'

      run.press "Shift+Tab"

      expect(run.row(23)[79]).to eq '█'
      expect(run.row(18)[79]).to eq '│'
    end
  end

  describe "going back on losing focus" do
    it "shrinks and scrolls to the end with sampled rows, ending on the last rows" do
      run = talkative 40, clock: true, motion: true
      run.press "Shift+Tab"
      run.run_timers
      run.press "Home"
      run.run_timers
      expect(run.pager.scroll_y).to eq 0

      run.press "Tab"
      drawn = [{run.screen.log_size, run.pager.shown}] + frames(run)

      last = run.pager.lines.size - 1
      expect(drawn.first[0]).to be < 6
      expect(drawn.last[0]).to eq 4
      expect(drawn.last[1]).to eq ((last - 3)..last).to_a
      expect(drawn.size).to be <= Roguelike::Ui::LogPanel::RETURN_FRAMES + 1

      # The rows inserted along the way skip, so the scroll reads as a
      # scroll and still ends in a few frames.
      seen = drawn.flat_map(&.[1]).uniq!.sort!
      expect(seen.each_cons_pair.any? { |(above, below)| below - above > 1 }).to be_true
      expect(run.pager.back).to eq 0
      expect(run.pager.sampled).to be_nil
    end

    it "lands on the end at once with motion off" do
      run = talkative 40
      run.press "Shift+Tab"
      run.press "Home"

      run.press "Tab"

      expect(run.screen.log_size).to eq 4
      expect(run.pager.back).to eq 0
    end
  end

  describe "scrolled while unfocused" do
    it "stays scrolled until a message arrives, then scrolls back to the line before it" do
      run = talkative 40, clock: true, motion: true
      6.times { run.wheel *OVER_THE_PANE, up: true }
      before = run.pager.lines.size - 1

      run.game.log.add "Something new happened."
      run.play.refresh
      drawn = [run.pager.shown] + frames(run).map(&.[1])

      expect(drawn.last(2).first.last).to eq before
      expect(drawn.last(2).first).to eq ((before - 3)..before).to_a
      expect(run.pager.back).to eq 0
      expect(run.rows[23]).to contain "Something new happened."
    end
  end

  describe "scrolled while focused" do
    it "stays where it is when a message arrives" do
      run = talkative 40
      run.press "Shift+Tab"
      run.press "PageUp"
      showing = run.pager.showing

      run.game.log.add "Something new happened."
      run.play.refresh
      run.render

      expect(run.pager.showing).to eq showing
      expect(run.pager.newer).to be > 0
    end
  end

  describe "the newer badge" do
    it "counts the messages below the view" do
      run = talkative
      3.times { run.wheel *OVER_THE_PANE, up: true }

      expect(run.row(23)).to contain "↓ 3 newer"
    end

    it "is drawn white on blue" do
      run = talkative
      3.times { run.wheel *OVER_THE_PANE, up: true }
      spot = run.row(23).index!("↓")

      style = drawn_style run, spot, 23
      expect(style.foreground).to eq Palette::NEWER_BADGE.foreground
      expect(style.background).to eq Palette::NEWER_BADGE.background
    end

    it "covers only its own width" do
      run = talkative
      3.times { run.wheel *OVER_THE_PANE, up: true }

      expect(run.row(23)[24..]).to start_with "│ Something number"
    end

    it "updates as messages arrive" do
      run = talkative
      run.press "Shift+Tab"
      run.press "Shift+Up", "Shift+Up"
      expect(run.row(23)).to contain "↓ 2 newer"

      run.game.log.add "Something new happened."
      run.play.refresh
      run.render

      expect(run.row(23)).to contain "↓ 3 newer"
    end

    it "is gone at the newest line" do
      run = talkative

      expect(run.row(23)).not_to contain "newer"
    end

    it "scrolls to the end when clicked" do
      run = talkative
      3.times { run.wheel *OVER_THE_PANE, up: true }
      spot = run.row(23).index!("↓")

      run.click spot, 23

      expect(run.pager.back).to eq 0
      expect(run.row(23)).not_to contain "newer"
    end
  end

  describe "a held page" do
    it "holds a taller page in a grown log" do
      run = talkative
      run.press "Shift+Tab"

      12.times { |number| run.game.log.add "Something else number #{number}." }
      run.play.refresh
      run.render

      expect(run.pager.holding?).to be_true
      expect(run.pager.page).to eq 5
      expect(run.row(23)).to contain "--More--"
    end

    it "is shown from its read mark however far the log was scrolled" do
      run = talkative
      3.times { run.wheel *OVER_THE_PANE, up: true }

      12.times { |number| run.game.log.add "Something else number #{number}." }
      run.play.refresh
      run.render

      expect(run.pager.holding?).to be_true
      expect(run.pager.showing.first).to eq "Something else number 0."

      while run.pager.holding?
        run.press "."
      end

      expect(run.pager.back).to eq 0
    end
  end

  describe "drawn" do
    it "draws the focused log grown, with more than fits" do
      run = talkative
      run.press "Shift+Tab"
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/log-focused-grown.txt", drawn)
    end

    it "draws the badge on a log scrolled back" do
      run = talkative
      3.times { run.wheel *OVER_THE_PANE, up: true }
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/log-newer-badge.txt", drawn)
    end
  end
end
