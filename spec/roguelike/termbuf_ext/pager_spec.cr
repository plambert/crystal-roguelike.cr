require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Pager do
  alias Widgets = TermBuf::Widgets

  # A pager of *columns* by *rows*, over a buffer.
  record Paged, pager : Widgets::Pager, session : Headless::Session

  def paged(columns : Int32 = 30, rows : Int32 = 4) : Paged
    pager = Widgets::Pager.new
    session = Headless.open pager, columns, rows
    pager.app = session.app
    pager.resize columns, rows

    Paged.new pager, session
  end

  def messages(count : Int32) : Array(String)
    (1..count).map { |number| "Message number #{number}." }
  end

  describe "with nothing to show" do
    it "draws nothing and holds nothing" do
      run = paged

      expect(run.pager.holding?).to be_false
      expect(run.session.rows).to eq ["", "", "", ""]
    end
  end

  describe "fewer lines than the pane" do
    it "shows them all, oldest first" do
      run = paged
      run.pager.show messages(3)

      expect(run.session.rows[0, 3])
        .to eq ["Message number 1.", "Message number 2.", "Message number 3."]
      expect(run.pager.holding?).to be_false
    end
  end

  describe "as many lines as the pane" do
    it "shows them all without holding" do
      run = paged
      run.pager.show messages(4)

      expect(run.pager.holding?).to be_false
      expect(run.session.row(3)).to eq "Message number 4."
    end
  end

  describe "more lines than the pane" do
    # One row goes to the marker. A page that used every row would leave
    # nowhere to say that more is coming.
    it "holds after one page, with a row left for the marker" do
      run = paged
      run.pager.show messages(6)

      expect(run.pager.holding?).to be_true
      expect(run.session.rows[0, 3])
        .to eq ["Message number 1.", "Message number 2.", "Message number 3."]
      expect(run.session.row(3)).to eq "--More--"
    end

    it "shows the rest on a key, with older lines for context" do
      run = paged
      run.pager.show messages(6)
      run.session.press "l"

      expect(run.pager.holding?).to be_false
      expect(run.session.rows)
        .to eq ["Message number 3.", "Message number 4.",
                "Message number 5.", "Message number 6."]
    end

    # A pager that let other keys through would walk the character while the
    # person was reading.
    it "takes every key while it holds" do
      run = paged
      run.pager.show messages(6)

      expect(run.pager.focusable?).to be_true
    end

    it "gives the keyboard back once the reading is done" do
      run = paged
      run.pager.show messages(6)
      run.session.press "l"

      expect(run.pager.focusable?).to be_false
    end

    it "pages twice when there is twice as much" do
      run = paged
      run.pager.show messages(9)

      expect(run.session.row(0)).to eq "Message number 1."
      expect(run.pager.advance).to be_true

      expect(run.session.row(0)).to eq "Message number 4."
      expect(run.pager.holding?).to be_true
      expect(run.pager.advance).to be_true

      expect(run.pager.holding?).to be_false
      expect(run.session.row(3)).to eq "Message number 9."
    end

    # Twenty lines through a three row pane. Two lines a page, ten pages.
    it "walks twenty lines through a three row pane" do
      run = paged 30, 3
      run.pager.show messages(20)

      pages = [] of Array(String)
      loop do
        pages << run.pager.showing
        break unless run.pager.advance
      end

      expect(pages.size).to eq 10
      expect(pages.first).to eq ["Message number 1.", "Message number 2."]
      expect(pages[1]).to eq ["Message number 3.", "Message number 4."]
      expect(pages.last).to eq ["Message number 18.", "Message number 19.",
                                "Message number 20."]
      expect(run.pager.unread).to eq 0
    end
  end

  # A capped log drops its oldest line for each one it gains, so its size
  # stops changing once it is full.
  describe "a source that drops its oldest lines" do
    # A pager over 200 lines, every one of them read.
    def full : Paged
      run = paged
      run.pager.show messages(200)
      run.pager.catch_up
      run
    end

    it "holds when as many arrive as are dropped" do
      run = full
      run.pager.show messages(206)[6..]

      expect(run.pager.unread).to eq 6
      expect(run.pager.holding?).to be_true
    end

    it "pages through what arrived, skipping none" do
      run = full
      run.pager.show messages(206)[6..]

      pages = [] of String
      while run.pager.holding?
        pages.concat run.pager.showing
        run.pager.advance
      end

      # The last view keeps older lines above the newest for context.
      rest = run.pager.showing
      pages.concat rest[(rest.index(pages.last) || -1) + 1..]

      expect(pages).to eq messages(206).last(6)
    end

    # The read mark counts wrapped lines, so a dropped line that wrapped
    # takes more than one off it. Taking one would leave three unread, which
    # a four row pane shows without holding.
    it "counts the wrapped lines of what was dropped" do
      run = paged
      long = "A single message far too long to fit on one row here."
      run.pager.show [long] + messages(10)
      run.pager.catch_up

      run.pager.show messages(15)

      expect(run.pager.unread).to eq 5
      expect(run.pager.holding?).to be_true
    end

    it "holds nothing for a source that shares no lines with the last" do
      run = full
      run.pager.show ["Something else entirely."]

      expect(run.pager.holding?).to be_false
    end

    it "holds everything when told more arrived than the source keeps" do
      run = full
      flood = (1..200).map { |number| "Found thing number #{number}." }

      run.pager.show flood, arrived: 400

      expect(run.pager.unread).to eq 200
      expect(run.pager.holding?).to be_true
    end

    it "counts the dropped lines from the arrival count" do
      run = full
      run.pager.show messages(206)[6..], arrived: 6

      expect(run.pager.unread).to eq 6
      expect(run.pager.holding?).to be_true
    end
  end

  describe "a line longer than the pane" do
    it "wraps rather than being cut" do
      run = paged
      run.pager.show ["A single message far too long to fit on one row here."]

      expect(run.pager.lines.size).to be > 1
      expect(run.pager.lines.join(" ").gsub(/\s+/, " "))
        .to eq "A single message far too long to fit on one row here."
    end

    # Six wrapped rows in a four row pane. One message can hold the pane on
    # its own.
    it "counts its wrapped rows toward a page" do
      run = paged 20, 4
      run.pager.show ["one two three four five six seven eight nine ten " \
                      "eleven twelve thirteen fourteen fifteen sixteen"]

      expect(run.pager.lines.size).to be > 4
      expect(run.pager.holding?).to be_true
    end
  end

  describe "#resize" do
    it "wraps again at the new width" do
      run = paged 40, 4
      run.pager.show ["one two three four five six seven eight nine ten"]
      narrow = run.pager.lines.size

      run.pager.resize 15, 4

      expect(run.pager.lines.size).to be > narrow
    end

    it "shows nothing at no width at all" do
      run = paged
      run.pager.show messages(3)
      run.pager.resize 0, 0

      expect(run.pager.showing).to be_empty
    end
  end

  describe "#catch_up" do
    it "marks every line as seen" do
      run = paged
      run.pager.show messages(9)
      run.pager.catch_up

      expect(run.pager.unread).to eq 0
      expect(run.pager.holding?).to be_false
    end
  end

  describe "#advance" do
    it "does nothing while the pager is not holding" do
      run = paged
      run.pager.show messages(2)

      expect(run.pager.advance).to be_false
    end
  end

  describe "scrolling back" do
    # A notch of the wheel over the pane.
    #
    # The pane is drawn first. A widget the tree has not laid out yet sits
    # nowhere, and a report lands on nothing.
    def notch(run : Paged, up : Bool) : Nil
      run.session.render
      button = up ? TermBuf::Input::Mouse::Button::WheelUp : TermBuf::Input::Mouse::Button::WheelDown

      run.session.send TermBuf::Events::Mouse.new(
        button, 1, 1, TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)
      run.session.render
    end

    it "shows the lines above the pane" do
      run = paged
      run.pager.show messages(9)
      run.pager.catch_up
      run.pager.scroll_by 0, -2

      expect(run.pager.back).to eq 2
      expect(run.pager.showing.first).to eq "Message number 4."
      expect(run.pager.showing.last).to eq "Message number 7."
    end

    it "stops at the oldest line" do
      run = paged
      run.pager.show messages(9)
      run.pager.catch_up
      run.pager.scroll_by 0, -40

      expect(run.pager.showing.first).to eq "Message number 1."
    end

    it "stops at the newest" do
      run = paged
      run.pager.show messages(9)
      run.pager.catch_up
      run.pager.scroll_by 0, 40

      expect(run.pager.back).to eq 0
      expect(run.pager.showing.last).to eq "Message number 9."
    end

    it "answers a notch of the wheel" do
      run = paged
      run.pager.show messages(9)
      run.pager.catch_up

      notch run, up: true

      expect(run.pager.back).to eq 1
      expect(run.session.row(3)).to eq "Message number 8."
    end

    # What just happened is what a person wants to see. A pane left where it
    # was scrolled to would go quietly stale.
    it "goes back to the newest when a line arrives" do
      run = paged
      run.pager.show messages(9)
      run.pager.catch_up
      run.pager.scroll_by 0, -3
      run.pager.show messages(10)

      expect(run.pager.back).to eq 0
      expect(run.pager.showing.last).to eq "Message number 10."
    end

    it "changes nothing while the pager holds" do
      run = paged
      run.pager.show messages(9)

      run.pager.scroll_by 0, -2
      notch run, up: true

      expect(run.pager.back).to eq 0
      expect(run.pager.showing.first).to eq "Message number 1."
    end

    # The marker is asking for a key. A notch down is as good an answer as
    # one.
    it "takes a notch down as a page while it holds" do
      run = paged
      run.pager.show messages(9)

      notch run, up: false

      expect(run.pager.read).to eq 3
      expect(run.pager.showing.first).to eq "Message number 4."
    end
  end

  describe "accents" do
    # The style the buffer drew the cell at *column* on *row* in.
    def style_at(run : Paged, column : Int32, row : Int32) : TermBuf::Style
      run.session.render
      found = run.session.buffer.hit column, row
      raise "nothing is drawn at #{column}, #{row}" unless found

      run.session.buffer.styles[found.cell.style]
    end

    # Accents every "hat" in a line.
    def hats(run : Paged) : TermBuf::Style
      mark = TermBuf::Style::DEFAULT.underlined
      run.pager.accents = ->(line : String) do
        found = [] of Widgets::Pager::Accent
        line.scan(/hat/) { |match| found << Widgets::Pager::Accent.new(match.begin, 3, mark) }
        found
      end
      mark
    end

    it "draws the accented characters in the accent's style and leaves the rest" do
      run = paged
      mark = hats run
      run.pager.show ["A red hat."]

      expect(run.session.row 0).to eq "A red hat."
      expect(style_at run, 6, 0).to eq mark
      expect(style_at run, 8, 0).to eq mark
      expect(style_at run, 5, 0).to eq TermBuf::Style::DEFAULT
      expect(style_at run, 9, 0).to eq TermBuf::Style::DEFAULT
    end

    it "lays the accent over the fresh style" do
      run = paged
      mark = hats run
      bright = TermBuf::Style::DEFAULT.bold
      run.pager.fresh_style = bright
      run.pager.fresh = 1
      run.pager.show ["A red hat."]

      expect(style_at run, 6, 0).to eq bright.merge(mark)
      expect(style_at run, 0, 0).to eq bright
    end

    it "finds accents on each wrapped line and keeps the row count" do
      run = paged columns: 12
      mark = hats run
      run.pager.show ["A very tall hat sits here."]

      expect(run.pager.lines).to eq ["A very tall", "hat sits", "here."]
      expect(style_at run, 0, 1).to eq mark
      expect(style_at run, 3, 1).to eq TermBuf::Style::DEFAULT
    end
  end

  describe "scrolled back" do
    # A scrolled pager, with every line read.
    def scrolled(back : Int32 = 3) : Paged
      run = paged
      run.pager.show messages(9)
      run.pager.catch_up
      run.pager.scroll_by 0, -back
      run
    end

    it "keeps its window when asked to as a line arrives" do
      run = scrolled
      showing = run.pager.showing

      run.pager.show messages(10), arrived: 1, keep: true

      expect(run.pager.showing).to eq showing
      expect(run.pager.back).to eq 4
    end

    it "counts the lines below the window" do
      run = scrolled

      expect(run.pager.newer).to eq 3
      run.pager.to_newest
      expect(run.pager.newer).to eq 0
    end

    it "draws a badge over the end of the last row when it has one" do
      run = scrolled
      run.pager.badge = ->(count : Int32) { "[#{count}]" }

      expect(run.session.row(3)).to eq "Message number 6.          [3]"
    end

    it "goes to the newest line when the badge is clicked" do
      run = scrolled
      run.pager.badge = ->(count : Int32) { "[#{count}]" }
      run.session.render

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, 28, 3, TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)

      expect(run.pager.back).to eq 0
    end
  end

  describe "a sampled frame" do
    it "draws the lines it names instead of the window" do
      run = paged
      run.pager.show messages(9)
      run.pager.catch_up

      run.pager.sampled = [0, 2, 4, 8]

      expect(run.session.rows).to eq ["Message number 1.", "Message number 3.",
                                      "Message number 5.", "Message number 9."]
    end

    it "is cleared by a scroll" do
      run = paged
      run.pager.show messages(9)
      run.pager.catch_up
      run.pager.sampled = [0, 2, 4, 8]

      run.pager.scroll_by 0, -1

      expect(run.pager.sampled).to be_nil
    end
  end
end
