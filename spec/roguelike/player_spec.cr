require "../spec_helper"

Spectator.describe Roguelike::Player do
  subject(player) { described_class.new "proving-ground", 6, 5 }

  it "stands where it was put" do
    expect(player.at).to eq({6, 5})
    expect(player.floor).to eq "proving-ground"
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
      expect(again.floor).to eq player.floor
    end

    # A save that stored the floor twice would hold one copy in the world and
    # one under the player. The two copies would then need to stay in step.
    it "names the floor rather than holding one" do
      stored = JSON.parse player.to_json

      expect(stored["floor"]).to eq "proving-ground"
    end

    it "keeps the scores, the level and the hit points" do
      hurt = described_class.new "proving-ground", 6, 5,
        attributes: Roguelike::Attributes.new(14, 11, 16, 9, 13)
      hurt.gain 100
      hurt.hurt 5

      again = described_class.from_json hurt.to_json

      expect(again.attributes.to_a).to eq hurt.attributes.to_a
      expect(again.level).to eq hurt.level
      expect(again.experience).to eq hurt.experience
      expect(again.hit_points).to eq hurt.hit_points
      expect(again.max_hit_points).to eq hurt.max_hit_points
    end
  end

  describe "hit points" do
    it "starts at full health" do
      expect(player.hit_points).to eq player.max_hit_points
      expect(player.alive?).to be_true
    end

    it "comes from constitution and level" do
      tough = described_class.new "floor", 0, 0,
        attributes: Roguelike::Attributes.new(constitution: 16)

      expect(tough.max_hit_points)
        .to eq Roguelike::Advancement.max_hit_points(1, 16)
      expect(tough.max_hit_points).to be > player.max_hit_points
    end

    it "falls when the character is hurt" do
      player.hurt 3

      expect(player.hit_points).to eq player.max_hit_points - 3
    end

    it "stops at nothing rather than going below it" do
      player.hurt 1_000

      expect(player.hit_points).to eq 0
      expect(player.alive?).to be_false
    end

    it "goes back up when the character heals" do
      player.hurt 5

      expect(player.heal(3)).to eq 3
      expect(player.hit_points).to eq player.max_hit_points - 2
    end

    it "heals no further than full health" do
      player.hurt 2

      expect(player.heal(1_000)).to eq 2
      expect(player.hit_points).to eq player.max_hit_points
    end
  end

  describe "#gain" do
    it "adds experience without a level at first" do
      expect(player.gain(1)).to eq 0
      expect(player.experience).to eq 1
      expect(player.level).to eq 1
    end

    it "raises the level at the threshold" do
      expect(player.gain(Roguelike::Advancement.threshold(2))).to eq 1
      expect(player.level).to eq 2
    end

    it "raises it more than once for a large gain" do
      expect(player.gain(Roguelike::Advancement.threshold(4))).to eq 3
      expect(player.level).to eq 4
    end

    # A character who levels up mid fight is better off than before, and is
    # not suddenly at full health either.
    it "adds the hit points the level gained, and no more" do
      player.hurt 5
      hurt = player.hit_points
      before = player.max_hit_points

      player.gain Roguelike::Advancement.threshold(2)

      expect(player.hit_points).to eq hurt + (player.max_hit_points - before)
      expect(player.hit_points).to be < player.max_hit_points
    end

    it "ignores a gain of nothing" do
      expect(player.gain(0)).to eq 0
      expect(player.gain(-5)).to eq 0
      expect(player.experience).to eq 0
    end

    it "counts down to the next level" do
      player.gain 5

      expect(player.to_next_level).to eq Roguelike::Advancement.threshold(2) - 5
    end
  end
end
