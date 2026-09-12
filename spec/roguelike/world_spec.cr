require "../spec_helper"

Spectator.describe Roguelike::World do
  def sample(id : String) : Roguelike::Level
    Roguelike::Level.parse id, "###\n#.#\n###"
  end

  subject(world) { described_class.new 20260911_u64 }

  describe "#add" do
    it "keeps a level under its own name" do
      world.add sample("cellar")

      expect(world["cellar"].id).to eq "cellar"
      expect(world.size).to eq 1
    end

    it "answers the level it was given" do
      level = sample "cellar"

      expect(world.add(level)).to be level
    end

    it "replaces one of the same name" do
      world.add sample("cellar")
      world.add sample("cellar")

      expect(world.size).to eq 1
    end
  end

  describe "#[]?" do
    it "answers nothing for a level nobody put there" do
      expect(world["nowhere"]?).to be_nil
      expect(world.has?("nowhere")).to be_false
    end
  end

  describe ".on" do
    it "takes the run's seed off the generator" do
      rng = Roguelike::Rng.new 7_u64

      expect(described_class.on(rng).seed).to eq 7_u64
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      world.add Roguelike::Levels.proving_ground
      world.add sample("cellar")

      again = described_class.from_json world.to_json

      expect(again.seed).to eq world.seed
      expect(again.size).to eq 2
      expect(again["cellar"]).to eq world["cellar"]
      expect(again["proving-ground"]).to eq world["proving-ground"]
    end

    # The seed is the run's identity and everything random comes from it, so a
    # save that lost it could not reproduce anything.
    it "keeps the seed" do
      stored = JSON.parse world.to_json

      expect(stored["seed"].as_i64.to_u64).to eq 20260911_u64
    end

    it "round-trips a world with nothing in it" do
      expect(described_class.from_json(world.to_json).size).to eq 0
    end
  end
end
