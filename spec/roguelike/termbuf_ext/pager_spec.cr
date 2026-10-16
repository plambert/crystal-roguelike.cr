require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Pager do
  alias Widgets = TermBuf::Widgets

  # A pager of *columns* by *rows*, over a buffer.
  record Paged, pager : Widgets::Pager, session : Headless::Session

  def paged(columns : Int32 = 30, rows : Int32 = 4) : Paged
    pager = Widgets::Pager.new
    session = Headless.open pager, columns, rows
    pager.resize columns, rows

    Paged.new pager, session
  end

  def messages(count : Int32) : Array(String)
    (1..count).map { |number| "Message number #{number}." }
  end

  # A pager showing *count* messages, at the newest line.
  def seen(count : Int32 = 9) : Paged
    run = paged
    run.pager.show messages(count)
    run.pager.to_newest
    run
  end

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

  describe "with nothing to show" do
    it "draws nothing" do
      run = paged

      expect(run.session.rows).to eq ["", "", "", ""]
    end
  end

  describe "fewer lines than the pane" do
    it "shows them all, oldest first" do
      run = paged
      run.pager.show messages(3)

      expect(run.session.rows[0, 3])
        .to eq ["Message number 1.", "Message number 2.", "Message number 3."]
      expect(run.pager.back).to eq 0
    end
  end

  describe "at the end" do
    it "follows lines that fit" do
      run = seen
      run.pager.show messages(11), arrived: 2

      expect(run.pager.back).to eq 0
      expect(run.session.row(3)).to eq "Message number 11."
    end

    it "parks on the first new line when more arrive than fit" do
      run = seen
      run.pager.show messages(15), arrived: 6

      expect(run.session.row(0)).to eq "Message number 10."
      expect(run.pager.newer).to eq 2
    end

    it "parks on the first new line when it is not told how many arrived" do
      run = seen
      run.pager.show messages(15)

      expect(run.session.row(0)).to eq "Message number 10."
    end

    it "follows again once scrolled to the end" do
      run = seen
      run.pager.show messages(15), arrived: 6
      run.pager.scroll_by 0, 40

      run.pager.show messages(16), arrived: 1

      expect(run.pager.back).to eq 0
      expect(run.session.row(3)).to eq "Message number 16."
    end

    it "follows every line while deferred" do
      run = seen
      run.pager.deferred = true

      run.pager.show messages(12), arrived: 3
      run.pager.show messages(15), arrived: 3

      expect(run.pager.back).to eq 0
    end

    it "parks on the first line that arrived while deferred once let go" do
      run = seen
      run.pager.deferred = true
      run.pager.show messages(12), arrived: 3
      run.pager.show messages(15), arrived: 3

      run.pager.deferred = false

      expect(run.session.row(0)).to eq "Message number 10."
    end

    it "takes no key" do
      run = seen
      run.pager.show messages(15), arrived: 6

      expect(run.pager.focusable?).to be_false
    end

    it "pages with one line kept from the page before" do
      run = paged 30, 3

      expect(run.pager.page).to eq 2
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

    # Six wrapped rows in a four row pane. One message can park the pane on
    # its own.
    it "parks on its first row" do
      run = paged 20, 4
      run.pager.show ["one two three four five six seven eight nine ten " \
                      "eleven twelve thirteen fourteen fifteen sixteen"], arrived: 1

      expect(run.pager.lines.size).to be > 4
      expect(run.pager.scroll_y).to eq 0
    end
  end

  # A capped log drops its oldest line for each one it gains, so its size
  # stops changing once it is full.
  describe "a source that drops its oldest lines" do
    it "parks on the first of what arrived" do
      run = seen 200
      run.pager.show messages(206)[6..], arrived: 6

      expect(run.pager.showing.first).to eq "Message number 201."
    end

    it "follows a source that shares no lines with the last" do
      run = seen 200
      run.pager.show ["Something else entirely."], arrived: 0

      expect(run.pager.back).to eq 0
    end

    it "parks on the oldest line kept when more arrived than the source keeps" do
      run = seen 200
      flood = (1..200).map { |number| "Found thing number #{number}." }

      run.pager.show flood, arrived: 400

      expect(run.pager.showing.first).to eq "Found thing number 1."
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

    # A long log wraps to more rows at a narrower width. The window stays at
    # the end rather than counting the extra rows as anything new.
    it "stays at the newest line when the width narrows" do
      run = paged 60, 4
      run.pager.show (1..50).map { |number| "Message number #{number} is long enough to wrap." }
      run.pager.to_newest

      run.pager.resize 20, 4

      expect(run.pager.back).to eq 0
      expect(run.pager.newer).to eq 0
    end

    it "keeps the line at the top of a scrolled window when the width changes" do
      run = paged 60, 4
      run.pager.show (1..50).map { |number| "Message number #{number} is long enough to wrap." }
      run.pager.scroll_by 0, -20
      top = run.pager.showing.first

      run.pager.resize 20, 4

      expect(run.pager.showing.first).to eq Widgets::Pager.wrap(top, 20).first
    end
  end

  describe "scrolling back" do
    it "shows the lines above the pane" do
      run = seen
      run.pager.scroll_by 0, -2

      expect(run.pager.back).to eq 2
      expect(run.pager.showing.first).to eq "Message number 4."
      expect(run.pager.showing.last).to eq "Message number 7."
    end

    it "stops at the oldest line" do
      run = seen
      run.pager.scroll_by 0, -40

      expect(run.pager.showing.first).to eq "Message number 1."
    end

    it "stops at the newest" do
      run = seen
      run.pager.scroll_by 0, 40

      expect(run.pager.back).to eq 0
      expect(run.pager.showing.last).to eq "Message number 9."
    end

    it "answers a notch of the wheel" do
      run = seen

      notch run, up: true

      expect(run.pager.back).to eq 1
      expect(run.session.row(3)).to eq "Message number 8."
    end

    it "stays where it is when a line arrives" do
      run = seen
      run.pager.scroll_by 0, -3
      showing = run.pager.showing

      run.pager.show messages(10), arrived: 1

      expect(run.pager.showing).to eq showing
      expect(run.pager.back).to eq 4
    end

    it "keeps its window when a capped source drops the lines it shows" do
      run = seen
      run.pager.scroll_by 0, -40
      showing = run.pager.showing

      run.pager.show messages(10)[1..], arrived: 1

      expect(run.pager.showing).to eq showing
      expect(run.pager.newer).to eq 6
    end

    it "lets go of the kept lines once the window moves on" do
      run = seen
      run.pager.scroll_by 0, -40
      run.pager.show messages(10)[1..], arrived: 1
      run.pager.to_newest

      run.pager.show messages(11)[2..], arrived: 1

      expect(run.pager.lines).to eq messages(11)[2..]
    end

    it "counts the lines below the window" do
      run = seen
      run.pager.scroll_by 0, -3

      expect(run.pager.newer).to eq 3
      run.pager.to_newest
      expect(run.pager.newer).to eq 0
    end
  end

  describe "the badge" do
    it "is not drawn unless an owner gives it text" do
      run = seen
      run.pager.scroll_by 0, -3

      expect(run.session.row(3)).to eq "Message number 6."
    end

    it "is drawn over the end of the last row" do
      run = seen
      run.pager.scroll_by 0, -3
      run.pager.badge = ->(count : Int32) { "[#{count}]" }

      expect(run.session.row(3)).to eq "Message number 6.          [3]"
    end

    it "goes to the newest line when clicked" do
      run = seen
      run.pager.scroll_by 0, -3
      run.pager.badge = ->(count : Int32) { "[#{count}]" }
      run.session.render

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, 28, 3, TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)

      expect(run.pager.back).to eq 0
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

  describe "a sampled frame" do
    it "draws the lines it names instead of the window" do
      run = seen

      run.pager.sampled = [0, 2, 4, 8]

      expect(run.session.rows).to eq ["Message number 1.", "Message number 3.",
                                      "Message number 5.", "Message number 9."]
    end

    it "is cleared by a scroll" do
      run = seen
      run.pager.sampled = [0, 2, 4, 8]

      run.pager.scroll_by 0, -1

      expect(run.pager.sampled).to be_nil
    end
  end
end
