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
end
