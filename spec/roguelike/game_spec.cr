require "../spec_helper"

Spectator.describe Roguelike::Game do
  alias Direction = Roguelike::Direction
  alias Terrain = Roguelike::Terrain

  subject(game) { described_class.start Roguelike::Rng.new(Playing::SEED) }

  describe ".start" do
    it "puts the character on the staircase they came down by" do
      expect(game.player.at).to eq game.level.find(Terrain::StairsUp)
    end

    it "starts on turn nothing" do
      expect(game.turn).to eq 0
    end

    it "takes the run's seed off the generator" do
      expect(game.world.seed).to eq Playing::SEED
    end

    it "puts the character on the level the world holds" do
      expect(game.level.id).to eq game.player.level
    end
  end

  describe ".entrance" do
    it "finds the up staircase" do
      level = Roguelike::Level.parse "sample", "###\n#<#\n###"

      expect(described_class.entrance(level)).to eq({1, 1})
    end

    it "falls back to anywhere somebody could stand" do
      level = Roguelike::Level.parse "sample", "###\n#.#\n###"

      expect(described_class.entrance(level)).to eq({1, 1})
    end

    it "refuses a level with nowhere to stand" do
      level = Roguelike::Level.parse "solid", "###\n###"

      expect { described_class.entrance(level) }.to raise_error ArgumentError, /nowhere/
    end
  end

  describe "#step" do
    # The up staircase sits in a room, so every direction out of it is floor.
    it "moves one square and takes a turn" do
      start = game.player.at

      expect(game.step(Direction::East)).to be_true
      expect(game.player.at).to eq({start[0] + 1, start[1]})
      expect(game.turn).to eq 1
    end

    it "moves on the diagonals too" do
      start = game.player.at
      game.step Direction::SouthEast

      expect(game.player.at).to eq({start[0] + 1, start[1] + 1})
    end

    it "goes all eight ways and comes back where it started" do
      start = game.player.at

      Direction.each do |direction|
        expect(game.step(direction)).to be_true
        expect(game.step(direction.opposite)).to be_true
        expect(game.player.at).to eq start
      end

      expect(game.turn).to eq 16
    end

    # A step into a wall is not the character doing anything, so nothing else
    # on the level should get a turn out of it.
    it "will not walk into rock, and costs no turn for trying" do
      level = Roguelike::Level.parse "cell", "###\n#<#\n###"
      shut = described_class.new(Roguelike::World.new(1_u64, {"cell" => level}),
        Roguelike::Player.new("cell", 1, 1))

      Direction.each do |direction|
        expect(shut.step(direction)).to be_false
      end

      expect(shut.player.at).to eq({1, 1})
      expect(shut.turn).to eq 0
    end

    it "will not walk through a shut door" do
      level = Roguelike::Level.parse "hall", "###\n#<+\n###"
      shut = described_class.new(Roguelike::World.new(1_u64, {"hall" => level}),
        Roguelike::Player.new("hall", 1, 1))

      expect(shut.step(Direction::East)).to be_false
      expect(shut.turn).to eq 0
    end

    it "walks through a door standing open" do
      level = Roguelike::Level.parse "hall", "###\n#<'\n###"
      open = described_class.new(Roguelike::World.new(1_u64, {"hall" => level}),
        Roguelike::Player.new("hall", 1, 1))

      expect(open.step(Direction::East)).to be_true
      expect(open.player.at).to eq({2, 1})
    end

    it "will not walk off the level" do
      level = Roguelike::Level.parse "ledge", "<"
      edge = described_class.new(Roguelike::World.new(1_u64, {"ledge" => level}),
        Roguelike::Player.new("ledge", 0, 0))

      Direction.each { |direction| expect(edge.step(direction)).to be_false }
      expect(edge.turn).to eq 0
    end

    it "counts only the turns that happened" do
      walk = ([Direction::East] * 40)
      taken = walk.count { |direction| game.step direction }

      expect(game.turn).to eq taken
      expect(taken).to be < walk.size
    end
  end

  describe "#blocking" do
    it "names what is in the way" do
      level = Roguelike::Level.parse "hall", "###\n#<+\n###"
      shut = described_class.new(Roguelike::World.new(1_u64, {"hall" => level}),
        Roguelike::Player.new("hall", 1, 1))

      expect(shut.blocking(Direction::East)).to eq Terrain::ClosedDoor
      expect(shut.blocking(Direction::North)).to eq Terrain::Granite
    end

    it "answers nothing when the way is clear" do
      expect(game.blocking(Direction::East)).to be_nil
    end

    it "answers nothing off the level" do
      level = Roguelike::Level.parse "ledge", "<"
      edge = described_class.new(Roguelike::World.new(1_u64, {"ledge" => level}),
        Roguelike::Player.new("ledge", 0, 0))

      expect(edge.blocking(Direction::East)).to be_nil
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      3.times { game.step Direction::East }
      again = described_class.from_json game.to_json

      expect(again.turn).to eq game.turn
      expect(again.player.at).to eq game.player.at
      expect(again.level).to eq game.level
      expect(again.world.seed).to eq game.world.seed
    end

    it "keeps playing from where it was read back" do
      5.times { game.step Direction::East }
      again = described_class.from_json game.to_json

      expect(again.step(Direction::South)).to eq game.step(Direction::South)
      expect(again.player.at).to eq game.player.at
    end
  end
end
