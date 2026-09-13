require "../spec_helper"

Spectator.describe Roguelike::Line do
  alias Line = Roguelike::Line

  describe ".between" do
    it "walks a straight row" do
      expect(Line.between({0, 0}, {3, 0})).to eq [{0, 0}, {1, 0}, {2, 0}, {3, 0}]
    end

    it "walks a straight column" do
      expect(Line.between({0, 0}, {0, 3})).to eq [{0, 0}, {0, 1}, {0, 2}, {0, 3}]
    end

    it "walks a diagonal" do
      expect(Line.between({0, 0}, {3, 3})).to eq [{0, 0}, {1, 1}, {2, 2}, {3, 3}]
    end

    it "walks backwards as readily as forwards" do
      expect(Line.between({3, 3}, {0, 0})).to eq [{3, 3}, {2, 2}, {1, 1}, {0, 0}]
    end

    it "answers one square for a line that goes nowhere" do
      expect(Line.between({2, 2}, {2, 2})).to eq [{2, 2}]
    end

    it "moves one square at a time" do
      steps = Line.between({0, 0}, {9, 4})

      steps.each_cons(2) do |pair|
        expect((pair[1][0] - pair[0][0]).abs).to be <= 1
        expect((pair[1][1] - pair[0][1]).abs).to be <= 1
      end
    end

    it "ends where it was told to" do
      [{7, 2}, {-4, 6}, {3, -8}, {-5, -5}].each do |target|
        expect(Line.between({0, 0}, target).last).to eq target
      end
    end
  end

  describe ".beyond" do
    it "starts past the square it is told to look through" do
      found = [] of {Int32, Int32}
      Line.beyond({0, 0}, {2, 0}, 3) { |spot| found << spot }

      expect(found).to eq [{3, 0}, {4, 0}, {5, 0}]
    end

    it "takes no more than the reach" do
      found = [] of {Int32, Int32}
      Line.beyond({0, 0}, {1, 1}, 2) { |spot| found << spot }

      expect(found).to eq [{2, 2}, {3, 3}]
    end

    # The walk moves one square at a time, so a shallow line steps twice
    # across for each step down rather than jumping the whole way.
    it "keeps going along the same line" do
      found = [] of {Int32, Int32}
      Line.beyond({10, 10}, {8, 9}, 4) { |spot| found << spot }

      whole = Line.between({10, 10}, {2, 6})
      expect(found).to eq whole[3, 4]
    end

    it "moves away from where it started" do
      found = [] of {Int32, Int32}
      Line.beyond({10, 10}, {8, 9}, 4) { |spot| found << spot }

      across = found.map { |spot| spot[0] }
      expect(across).to eq across.sort.reverse!
      expect(found.last[0]).to be < 8
    end

    it "yields nothing when the two ends are the same square" do
      found = [] of {Int32, Int32}
      Line.beyond({4, 4}, {4, 4}, 5) { |spot| found << spot }

      expect(found).to be_empty
    end
  end
end
