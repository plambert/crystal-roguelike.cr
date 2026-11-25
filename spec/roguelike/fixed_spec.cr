require "../spec_helper"

Spectator.describe Roguelike::FixedPoint do
  describe ".divide" do
    it "rounds half up" do
      expect(described_class.divide(5_i64, 2_i64)).to eq 3
      expect(described_class.divide(7_i64, 2_i64)).to eq 4
      expect(described_class.divide(14_i64, 10_i64)).to eq 1
      expect(described_class.divide(15_i64, 10_i64)).to eq 2
    end

    it "divides exactly when it can" do
      expect(described_class.divide(0_i64, 7_i64)).to eq 0
      expect(described_class.divide(21_i64, 7_i64)).to eq 3
    end

    it "refuses a negative numerator and a denominator of zero or less" do
      expect { described_class.divide(-1_i64, 2_i64) }.to raise_error ArgumentError
      expect { described_class.divide(1_i64, 0_i64) }.to raise_error ArgumentError
      expect { described_class.divide(1_i64, -2_i64) }.to raise_error ArgumentError
    end

    it "takes the largest product the design forms" do
      largest = Int32::MAX.to_i64 * Roguelike::Chance::SCALE

      expect(described_class.divide(largest, Roguelike::Chance::SCALE.to_i64))
        .to eq Int32::MAX
    end
  end

  describe ".divide_signed" do
    it "rounds a negative numerator by its magnitude" do
      expect(described_class.divide_signed(-5_i64, 2_i64)).to eq -3
      expect(described_class.divide_signed(-14_i64, 10_i64)).to eq -1
      expect(described_class.divide_signed(5_i64, 2_i64)).to eq 3
    end
  end
end

Spectator.describe Roguelike::Fixed do
  describe "#to_s" do
    it "shows one decimal place, rounded half up" do
      expect(described_class.new(1378).to_s).to eq "13.8"
      expect(described_class.new(1210).to_s).to eq "12.1"
      expect(described_class.new(1215).to_s).to eq "12.2"
      expect(described_class.new(1214).to_s).to eq "12.1"
      expect(described_class.new(5).to_s).to eq "0.1"
      expect(described_class.new(900).to_s).to eq "9.0"
    end

    it "writes zero as a bare 0" do
      expect(Roguelike::Fixed::ZERO.to_s).to eq "0"
      expect(described_class.new(4).to_s).to eq "0"
    end

    it "shows a negative value as the negative of its magnitude" do
      expect(described_class.new(-125).to_s).to eq "-1.3"
      expect(described_class.new(-100).to_s).to eq "-1.0"
    end
  end

  describe ".whole" do
    it "holds whole units in hundredths" do
      expect(described_class.whole(13).value).to eq 1300
    end

    it "raises past the range of its type" do
      expect { described_class.whole(Int32::MAX) }.to raise_error OverflowError
    end
  end

  describe "arithmetic" do
    it "adds and subtracts" do
      expect((described_class.new(1300) + described_class.new(78)).value).to eq 1378
      expect((described_class.new(100) - described_class.new(250)).value).to eq -150
    end

    it "raises on overflow" do
      expect { described_class.new(Int32::MAX) + described_class.new(1) }
        .to raise_error OverflowError
    end

    it "scales by a ratio, rounding half up" do
      flat = described_class.new 1300

      expect((flat * Roguelike::Ratio.new(10_600)).value).to eq 1378
      expect((described_class.new(1) * Roguelike::Ratio.new(5_000)).value).to eq 1
      expect((described_class.new(-1) * Roguelike::Ratio.new(5_000)).value).to eq -1
    end

    it "clamps below zero" do
      expect(described_class.new(-3).clamp_positive).to eq Roguelike::Fixed::ZERO
      expect(described_class.new(3).clamp_positive.value).to eq 3
    end

    it "compares by value" do
      expect(described_class.new(1)).to be < described_class.new(2)
    end

    it "multiplies by a whole number" do
      expect((described_class.new(275) * 4).value).to eq 1100
      expect { described_class.new(Int32::MAX) * 2 }.to raise_error OverflowError
    end
  end

  describe "#ceil" do
    it "rounds up to a whole number" do
      expect(described_class.new(1).ceil).to eq 1
      expect(described_class.new(100).ceil).to eq 1
      expect(described_class.new(101).ceil).to eq 2
      expect(described_class.new(0).ceil).to eq 0
    end

    it "rounds a negative quantity toward zero" do
      expect(described_class.new(-50).ceil).to eq 0
      expect(described_class.new(-150).ceil).to eq -1
    end
  end

  describe "JSON" do
    it "is a bare integer" do
      expect(described_class.new(1378).to_json).to eq "1378"
      expect(described_class.from_json("-25").value).to eq -25
    end
  end
end

Spectator.describe Roguelike::Chance do
  alias Chance = Roguelike::Chance

  describe ".new" do
    it "holds 0 to 10,000 basis points" do
      expect(Chance.new(0).value).to eq 0
      expect(Chance.new(10_000).value).to eq 10_000
    end

    it "refuses anything outside that" do
      expect { Chance.new(-1) }.to raise_error ArgumentError
      expect { Chance.new(10_001) }.to raise_error ArgumentError
    end
  end

  describe ".clamped" do
    it "holds a value to the range" do
      expect(Chance.clamped(-50).value).to eq 0
      expect(Chance.clamped(12_000).value).to eq 10_000
      expect(Chance.clamped(1_200).value).to eq 1_200
    end
  end

  describe "#to_s" do
    it "shows a percentage with one decimal place, rounded half up" do
      expect(Chance.new(6049).to_s).to eq "60.5%"
      expect(Chance.new(5184).to_s).to eq "51.8%"
      expect(Chance.new(5185).to_s).to eq "51.9%"
      expect(Chance.new(1200).to_s).to eq "12.0%"
      expect(Chance.new(10_000).to_s).to eq "100.0%"
    end

    it "writes zero as 0%" do
      expect(Chance::NEVER.to_s).to eq "0%"
    end
  end

  describe ".sum" do
    it "adds chances" do
      expect(Chance.sum([Chance.new(300), Chance.new(400)]).value).to eq 700
    end

    it "stops at the cap" do
      sources = [Chance.new(5_000), Chance.new(4_000)]

      expect(Chance.sum(sources, cap: Chance.new(7_500)).value).to eq 7_500
    end

    it "stops at certainty without a cap" do
      expect(Chance.sum([Chance.new(9_000), Chance.new(9_000)]).value).to eq 10_000
    end

    it "is zero with no sources" do
      expect(Chance.sum([] of Chance)).to eq Chance::NEVER
    end
  end

  describe ".stack" do
    it "folds 1 - Π(1 - p)" do
      sources = [Chance.new(2_000), Chance.new(1_000)]

      expect(Chance.stack(sources).value).to eq 2_800
    end

    it "gives the same result in any order" do
      sources = [Chance.new(3_333), Chance.new(17), Chance.new(6_667), Chance.new(1)]

      expect(Chance.stack(sources)).to eq Chance.stack(sources.reverse)
      expect(Chance.stack(sources)).to eq Chance.stack(sources.shuffle(Random.new(3)))
    end

    it "rounds once per source at the folding scale" do
      sources = [Chance.new(1), Chance.new(1), Chance.new(1)]

      expect(Chance.stack(sources).value).to eq 3
    end

    it "is the one source when there is one" do
      expect(Chance.stack([Chance.new(1_234)]).value).to eq 1_234
    end

    it "is zero with no sources" do
      expect(Chance.stack([] of Chance)).to eq Chance::NEVER
    end

    it "is certain when any source is certain" do
      expect(Chance.stack([Chance.new(10), Chance::ALWAYS])).to eq Chance::ALWAYS
    end

    it "takes many large sources without overflow" do
      sources = Array.new(64) { Chance.new(9_999) }

      expect(Chance.stack(sources)).to eq Chance::ALWAYS
    end
  end

  describe "#complement" do
    it "is the chance it does not come up" do
      expect(Chance.new(1_200).complement.value).to eq 8_800
    end
  end

  describe "JSON" do
    it "is a bare integer" do
      expect(Chance.new(1200).to_json).to eq "1200"
      expect(Chance.from_json("1200").value).to eq 1200
    end

    it "refuses an integer outside the range" do
      expect { Chance.from_json("10001") }.to raise_error ArgumentError
    end
  end
end

Spectator.describe Roguelike::Ratio do
  alias Ratio = Roguelike::Ratio

  describe "#to_s" do
    it "shows a multiplier with one decimal place" do
      expect(Ratio.new(15_000).to_s).to eq "×1.5"
      expect(Ratio.new(11_000).to_s).to eq "×1.1"
      expect(Ratio.new(20_000).to_s).to eq "×2.0"
    end
  end

  describe "#percent" do
    it "shows a signed percentage" do
      expect(Ratio.new(600).percent).to eq "+6%"
      expect(Ratio.new(650).percent).to eq "+6.5%"
      expect(Ratio.new(-800).percent).to eq "-8%"
      expect(Ratio.new(0).percent).to eq "+0%"
    end
  end

  describe "arithmetic" do
    it "adds and subtracts" do
      expect((Ratio.new(600) + Ratio.new(2_500)).value).to eq 3_100
      expect((Ratio.new(600) - Ratio.new(2_500)).value).to eq -1_900
    end
  end

  describe "JSON" do
    it "is a bare integer" do
      expect(Ratio.new(-600).to_json).to eq "-600"
      expect(Ratio.from_json("15000").value).to eq 15_000
    end
  end
end
