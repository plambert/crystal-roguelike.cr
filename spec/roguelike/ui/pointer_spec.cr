require "../../spec_helper"

Spectator.describe Roguelike::Ui::Pointer do
  subject(pointer) { described_class.new }

  describe "before the pointer has been anywhere" do
    it "asks for no cursor and no shape" do
      expect(pointer.spot).to be_nil
      expect(pointer.shape).to be_nil
      expect(pointer.cursor).to be_nil
    end
  end

  describe "#over" do
    it "puts the terminal's cursor where the pointer is" do
      pointer.over 12, 5

      expect(pointer.spot).to eq({12, 5})
      expect(pointer.cursor).to eq({12, 5})
    end

    it "asks for the shape the map wants" do
      pointer.over 12, 5

      expect(pointer.shape).to eq Roguelike::Ui::Pointer::OVER_MAP
    end

    it "follows the pointer" do
      pointer.over 12, 5
      pointer.over 13, 5

      expect(pointer.cursor).to eq({13, 5})
    end
  end

  describe "#away" do
    it "gives the cursor and the shape back" do
      pointer.over 12, 5
      pointer.away

      expect(pointer.cursor).to be_nil
      expect(pointer.shape).to be_nil
    end

    it "does nothing to a pointer that was already away" do
      pointer.away

      expect(pointer.shape).to be_nil
    end
  end

  describe ".sequence" do
    it "asks for a shape by name" do
      expect(described_class.sequence("crosshair")).to eq "\e]22;crosshair\e\\"
    end

    # OSC 22 with nothing after the semicolon is the reset, and a terminal
    # that does not know the sequence at all ignores it.
    it "asks for the terminal's own with no name at all" do
      expect(described_class.sequence(nil)).to eq "\e]22;\e\\"
    end

    it "names a shape every terminal we support knows" do
      expect(Roguelike::Ui::Pointer::OVER_MAP).to eq "crosshair"
    end
  end
end
