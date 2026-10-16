require "../../spec_helper"

Spectator.describe Roguelike::Ui::LogPanel do
  alias Panel = Roguelike::Ui::FocusRing::Panel
  alias Palette = Roguelike::Ui::Palette
  alias Screen = Roguelike::Ui::Screen

  # Where a notch of the wheel lands on the log pane of an eighty by
  # twenty-four window.
  OVER_THE_PANE = {40, 21}

  # A run with *count* messages said, with the log at its newest line.
  def talkative(count : Int32 = 12, clock : Bool = false, motion : Bool = false) : Playing::Run
    run = Playing.open clock: clock, motion: motion
    run.clear_monsters
    count.times { |number| run.game.log.add "Something number #{number} happened." }
    run.play.refresh
    run.pager.to_newest
    run.render

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
      run.pager.to_newest
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
      run.pager.to_newest

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
      run.pager.to_newest
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
      run.pager.to_newest

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

  describe "losing focus" do
    it "shrinks and keeps its place" do
      run = talkative 40
      run.press "Shift+Tab"
      run.press "Home"

      run.press "Tab"

      expect(run.screen.log_size).to eq 4
      expect(run.pager.back).to be > 0
      expect(run.row(23)).to contain "newer"
    end
  end

  describe "jumping to the end" do
    # The log focused and scrolled to its oldest line, with motion on.
    def far_back : Playing::Run
      run = talkative 40, clock: true, motion: true
      run.press "Shift+Tab"
      run.run_timers
      run.press "Home"
      run.run_timers
      run
    end

    # What each frame drew, from the one drawn now.
    def jumped(run : Playing::Run) : Array(Array(Int32))
      [run.pager.shown] + frames(run).map(&.[1])
    end

    it "inserts sampled rows on End, ending on the last rows" do
      run = far_back
      expect(run.pager.scroll_y).to eq 0

      run.press "End"
      drawn = jumped run

      last = run.pager.lines.size - 1
      expect(drawn.last).to eq ((last - 5)..last).to_a
      expect(drawn.size).to be <= Roguelike::Ui::LogPanel::RETURN_FRAMES + 1

      # The rows inserted along the way skip, so the scroll reads as a
      # scroll and still ends in a few frames.
      seen = drawn.flat_map(&.itself).uniq!.sort!
      expect(seen.each_cons_pair.any? { |(above, below)| below - above > 1 }).to be_true
      expect(run.pager.back).to eq 0
      expect(run.pager.sampled).to be_nil
    end

    it "does the same on Enter" do
      run = far_back

      run.press "Enter"
      drawn = jumped run

      expect(drawn.size).to be > 2
      expect(run.pager.back).to eq 0
    end

    it "lands on the end at once with motion off" do
      run = talkative 40
      run.press "Shift+Tab"
      run.press "Home"

      run.press "End"

      expect(run.pager.back).to eq 0
    end
  end

  describe "scrolled while unfocused" do
    it "stays where it is when a message arrives, and the badge counts it" do
      run = talkative 40
      6.times { run.wheel *OVER_THE_PANE, up: true }
      showing = run.pager.showing

      run.game.log.add "Something new happened."
      run.play.refresh
      run.render

      expect(run.pager.showing).to eq showing
      expect(run.row(23)).to contain "\u2193 7 newer"
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

  # A log at its cap drops its oldest line for each one it gains, so its
  # size stays the same while messages arrive.
  describe "at the log's cap" do
    LIMIT = Roguelike::MessageLog::LIMIT

    # A run whose log is full, with every line read.
    def capped(clock : Bool = false, motion : Bool = false) : Playing::Run
      run = Playing.open clock: clock, motion: motion
      run.clear_monsters
      LIMIT.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      run.pager.to_newest
      run.render
      run.run_timers if clock
      run
    end

    # Says one new thing, the way a turn does.
    def say_more(run : Playing::Run) : Nil
      run.game.log.add "Something new happened."
      run.play.refresh
      run.render
    end

    it "holds a focused log scrolled to the top in place as a message arrives" do
      run = capped
      run.press "Shift+Tab"
      run.press "Shift+Up", "Shift+Up", "PageUp", "Home"
      showing = run.pager.showing
      newer = run.pager.newer

      say_more run

      expect(run.game.log.lines.size).to eq LIMIT
      expect(run.pager.showing).to eq showing
      expect(run.pager.newer).to eq newer + 1
      expect(run.row(23)).to contain "\u2193 #{newer + 1} newer"
    end

    it "holds a focused log scrolled part way in place as a message arrives" do
      run = capped
      run.press "Shift+Tab"
      run.press "PageUp", "PageUp"
      showing = run.pager.showing
      newer = run.pager.newer

      say_more run

      expect(run.pager.showing).to eq showing
      expect(run.pager.newer).to eq newer + 1
    end

    it "holds an unfocused log still too, and the badge counts up" do
      run = capped
      6.times { run.wheel *OVER_THE_PANE, up: true }
      showing = run.pager.showing

      say_more run

      expect(run.pager.showing).to eq showing
      expect(run.pager.newer).to eq 7
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

  describe "a turn that says more than fits" do
    it "parks a grown log on the first new line" do
      run = talkative
      run.press "Shift+Tab"

      12.times { |number| run.game.log.add "Something else number #{number}." }
      run.play.refresh
      run.render

      expect(run.pager.showing.first).to eq "Something else number 0."
      expect(run.pager.showing.size).to eq 6
      expect(run.row(23)).to contain "\u2193 6 newer"
      expect(run.row(23)).not_to contain "--More--"
    end

    it "leaves a log scrolled back where it is" do
      run = talkative
      3.times { run.wheel *OVER_THE_PANE, up: true }
      showing = run.pager.showing

      12.times { |number| run.game.log.add "Something else number #{number}." }
      run.play.refresh
      run.render

      expect(run.pager.showing).to eq showing
      expect(run.pager.newer).to eq 15
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
