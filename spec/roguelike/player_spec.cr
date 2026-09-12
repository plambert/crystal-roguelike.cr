require "../spec_helper"

Spectator.describe Roguelike::Player do
  subject(player) { described_class.new "proving-ground", 6, 5 }

  it "knows where it is" do
    expect(player.at).to eq({6, 5})
    expect(player.level).to eq "proving-ground"
  end

  describe "#move_to" do
    it "goes where it is put" do
      player.move_to 7, 9

      expect(player.at).to eq({7, 9})
    end

    it "takes a pair as well as two numbers" do
      player.move_to({7, 9})

      expect(player.at).to eq({7, 9})
    end
  end

  describe "#at?" do
    it "knows which square it is standing on" do
      expect(player.at?(6, 5)).to be_true
      expect(player.at?(6, 6)).to be_false
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      again = described_class.from_json player.to_json

      expect(again.at).to eq player.at
      expect(again.level).to eq player.level
    end

    # A save that held the level twice — once in the world and once under the
    # player — would have two of them to keep in step.
    it "names the level rather than holding one" do
      stored = JSON.parse player.to_json

      expect(stored["level"]).to eq "proving-ground"
    end
  end
end
