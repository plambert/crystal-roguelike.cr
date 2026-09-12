require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Cells do
  describe ".of" do
    subject(cells) { described_class.of([[1, 2, 3], [4, 5, 6]]) }

    it "is as wide as a row" do
      expect(cells.columns).to eq 3
    end

    it "is as tall as it has rows" do
      expect(cells.rows).to eq 2
    end

    it "answers both extents at once" do
      expect(cells.size).to eq({3, 2})
    end

    it "answers what is at a spot" do
      expect(cells.cell(2, 1)).to eq 6
      expect(cells.cell(0, 0)).to eq 1
    end

    it "knows what is inside it" do
      expect(cells.contains?(2, 1)).to be_true
      expect(cells.contains?(3, 1)).to be_false
      expect(cells.contains?(2, 2)).to be_false
      expect(cells.contains?(-1, 0)).to be_false
    end

    it "is not empty" do
      expect(cells.empty?).to be_false
    end

    it "refuses rows of different lengths" do
      expect { described_class.of([[1, 2], [3]]) }.to raise_error ArgumentError
    end

    it "takes nothing at all" do
      empty = described_class.of([] of Array(Int32))

      expect(empty.empty?).to be_true
      expect(empty.size).to eq({0, 0})
    end
  end

  describe ".from" do
    it "answers what the block answers" do
      cells = described_class.from(10, 4, ->(x : Int32, y : Int32) { x * y })

      expect(cells.size).to eq({10, 4})
      expect(cells.cell(3, 2)).to eq 6
    end

    it "asks the block only about what it is asked about" do
      asked = [] of {Int32, Int32}
      cells = described_class.from(1000, 1000, ->(x : Int32, y : Int32) do
        asked << {x, y}
        0
      end)

      cells.cell 5, 7

      expect(asked).to eq [{5, 7}]
    end
  end
end
