require "../../spec_helper"

Spectator.describe Roguelike::Ui::Pointer do
  alias Pointer = Roguelike::Ui::Pointer

  subject(pointer) { described_class.new }

  describe "before the pointer has been anywhere" do
    it "asks for no cursor and knows of no shape" do
      expect(pointer.spot).to be_nil
      expect(pointer.cursor).to be_nil
      expect(pointer.shape).to be_nil
    end

    # A program gives back what it took and no more. A terminal whose pointer
    # was never changed is left alone.
    it "says nothing when the pointer was never over the map" do
      expect(pointer.away).to be_nil
    end
  end

  describe "#over" do
    it "puts the terminal's cursor where the pointer is" do
      pointer.over 12, 5

      expect(pointer.spot).to eq({12, 5})
      expect(pointer.cursor).to eq({12, 5})
    end

    it "asks for the shape the map wants" do
      expect(pointer.over(12, 5)).to eq Pointer.sequence(Pointer::OVER_MAP)
      expect(pointer.shape).to eq Pointer::OVER_MAP
    end

    it "says nothing the second time, having already said it" do
      pointer.over 12, 5

      expect(pointer.over(13, 5)).to be_nil
    end

    it "follows the pointer even when it says nothing" do
      pointer.over 12, 5
      pointer.over 13, 5

      expect(pointer.cursor).to eq({13, 5})
    end
  end

  describe "#away" do
    it "hides the terminal's cursor" do
      pointer.over 12, 5
      pointer.away

      expect(pointer.cursor).to be_nil
    end

    # There is no reset that works. Kitty takes an empty payload as one and
    # ghostty parses the payload as a shape name, so the empty form leaves a
    # ghostty pointer on the crosshair it was last told to draw.
    it "asks for a named shape rather than for a reset" do
      pointer.over 12, 5

      expect(pointer.away).to eq Pointer.sequence(Pointer::ELSEWHERE)
      expect(pointer.shape).to eq Pointer::ELSEWHERE
    end

    it "says nothing the second time" do
      pointer.over 12, 5
      pointer.away

      expect(pointer.away).to be_nil
    end

    it "asks again after the pointer has been back over the map" do
      pointer.over 12, 5
      pointer.away
      pointer.over 12, 5

      expect(pointer.away).to eq Pointer.sequence(Pointer::ELSEWHERE)
    end
  end

  describe ".sequence" do
    it "asks for a shape by name" do
      expect(described_class.sequence("crosshair")).to eq "\e]22;crosshair\e\\"
    end

    # `default`, `text` and `pointer` are the three every terminal with OSC 22
    # at all supports. Anything outside that set is a portability bet.
    it "names shapes every terminal we support knows" do
      expect(Pointer::OVER_MAP).to eq "crosshair"
      expect(Pointer::ELSEWHERE).to eq "text"
    end
  end
end
