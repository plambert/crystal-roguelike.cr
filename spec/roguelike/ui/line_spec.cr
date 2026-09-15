require "../../spec_helper"

Spectator.describe Roguelike::Ui::Line do
  alias Line = Roguelike::Ui::Line

  # *line* drawn in a window *columns* wide, as one row of text.
  def drawn(line : Line, columns : Int32 = 20) : String
    root = TermBuf::Widgets::Panel.new(
      width: TermBuf::Widgets::Layout::Sizing.grow,
      height: TermBuf::Widgets::Layout::Sizing.grow)
    root.add line

    Headless.open(root, columns, 1).rows.first
  end

  describe "#put" do
    it "writes a piece at the column it was given" do
      line = Line.new
      line.put 0, "ac"
      line.put 4, "5"

      expect(drawn line).to eq "ac  5"
    end

    it "answers the column after the piece" do
      expect(Line.new.put 3, "abc").to eq 6
    end

    it "keeps the pieces in the order they were written" do
      line = Line.new
      line.put 4, "second"
      line.put 0, "first"

      expect(line.spans.map &.text).to eq ["second", "first"]
    end
  end

  describe "#text" do
    it "answers every piece in column order" do
      line = Line.new
      line.put 6, "long swd"
      line.put 0, "wpn"

      expect(line.text).to eq "wpnlong swd"
    end

    it "answers nothing for an empty row" do
      expect(Line.new.text).to eq ""
    end
  end

  describe "#clear" do
    it "takes everything off the row" do
      line = Line.new
      line.put 0, "gone"
      line.clear

      expect(line.spans).to be_empty
      expect(drawn line).to eq ""
    end
  end

  describe "#draw" do
    it "marks a piece that ran off the right edge" do
      line = Line.new
      line.put 0, "a name far too long for this"

      drawn_row = drawn line, 10
      expect(drawn_row.size).to eq 10
      expect(drawn_row).to end_with Line::ELLIPSIS
    end

    it "writes nothing for a piece that starts past the edge" do
      line = Line.new
      line.put 40, "away"

      expect(drawn line, 10).to eq ""
    end

    # A row that wrapped would push everything under it down by one, and the
    # sidebar is a stack of rows that have to line up.
    it "never takes more than one row" do
      line = Line.new
      line.put 0, "a name far too long for ten columns"

      root = TermBuf::Widgets::Panel.new(
        width: TermBuf::Widgets::Layout::Sizing.grow,
        height: TermBuf::Widgets::Layout::Sizing.grow)
      root.add line

      expect(Headless.open(root, 10, 4).rows.count { |row| !row.empty? }).to eq 1
    end
  end
end
