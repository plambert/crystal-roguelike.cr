require "../spec_helper"

Spectator.describe Roguelike::Game do
  alias Direction = Roguelike::Direction
  alias Terrain = Roguelike::Terrain

  # A run on the shipped floor with nothing alive on it.
  #
  # Nothing in this file is about being chased. The slime in the first room
  # walks at a character carrying a lit torch from the moment the run starts,
  # and a creature standing in the way is a different spec's subject.
  subject(game) do
    found = described_class.start Roguelike::Rng.new(Playing::SEED)
    found.floor.monsters.clear
    found
  end

  describe ".start" do
    it "puts the character on the staircase they came down by" do
      expect(game.player.at).to eq game.floor.find(Terrain::StairsUp)
    end

    it "starts on turn nothing" do
      expect(game.turn).to eq 0
    end

    it "takes the run's seed off the generator" do
      expect(game.world.seed).to eq Playing::SEED
    end

    it "puts the character on the floor the world holds" do
      expect(game.floor.id).to eq game.player.floor
    end
  end

  describe ".entrance" do
    it "finds the up staircase" do
      floor = Roguelike::Floor.parse "sample", "###\n#<#\n###"

      expect(described_class.entrance(floor)).to eq({1, 1})
    end

    it "falls back to anywhere somebody could stand" do
      floor = Roguelike::Floor.parse "sample", "###\n#.#\n###"

      expect(described_class.entrance(floor)).to eq({1, 1})
    end

    it "refuses a floor with nowhere to stand" do
      floor = Roguelike::Floor.parse "solid", "###\n###"

      expect { described_class.entrance(floor) }.to raise_error ArgumentError, /nowhere/
    end
  end

  # A game on *map*, with the character at *x*, *y*.
  def one_room(map : String, x : Int32, y : Int32) : Roguelike::Game
    floor = Roguelike::Floor.parse "room", map

    described_class.new Roguelike::World.new(1_u64, {"room" => floor}),
      Roguelike::Player.new("room", x, y)
  end

  describe "#step" do
    # The up staircase sits in a room. Every square around it is floor.
    it "moves one square and takes a turn" do
      start = game.player.at

      expect(game.step(Direction::East).moved?).to be_true
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
        expect(game.step(direction).moved?).to be_true
        expect(game.step(direction.opposite).moved?).to be_true
        expect(game.player.at).to eq start
      end

      expect(game.turn).to eq 16
    end

    # A blocked step is not an action. No other creature on the floor should
    # get a turn out of it.
    it "will not walk into rock, and costs no turn for trying" do
      shut = one_room "###\n#<#\n###", 1, 1

      Direction.each do |direction|
        expect(shut.step(direction).blocked?).to be_true
      end

      expect(shut.player.at).to eq({1, 1})
      expect(shut.turn).to eq 0
    end

    # A person opens a door in one turn. They walk through it in the next.
    it "opens a shut door and stays where it is" do
      shut = one_room "###\n#<+\n###", 1, 1

      expect(shut.step(Direction::East).opened?).to be_true
      expect(shut.player.at).to eq({1, 1})
      expect(shut.floor.terrain(2, 1)).to eq Terrain::OpenDoor
      expect(shut.turn).to eq 1
    end

    it "walks through the door it opened, on the next step" do
      shut = one_room "###\n#<+\n###", 1, 1

      shut.step Direction::East
      expect(shut.step(Direction::East).moved?).to be_true
      expect(shut.player.at).to eq({2, 1})
      expect(shut.turn).to eq 2
    end

    it "walks through a door standing open" do
      open = one_room "###\n#<'\n###", 1, 1

      expect(open.step(Direction::East).moved?).to be_true
      expect(open.player.at).to eq({2, 1})
    end

    it "will not walk off the floor" do
      edge = one_room "<", 0, 0

      Direction.each { |direction| expect(edge.step(direction).blocked?).to be_true }
      expect(edge.turn).to eq 0
    end

    # North out of the starting room reaches rock. East would open the door
    # and keep going.
    it "counts only the turns that happened" do
      walk = ([Direction::North] * 40)
      taken = walk.count { |direction| game.step(direction).turn? }

      expect(game.turn).to eq taken
      expect(taken).to be < walk.size
    end
  end

  describe "#wait" do
    it "takes a turn and moves nobody" do
      start = game.player.at

      game.wait

      expect(game.player.at).to eq start
      expect(game.turn).to eq 1
    end

    # Nothing acts once the run is over, and a turn spent after it would
    # count against a character who is no longer playing.
    it "takes no turn once the run is over" do
      game.ascend
      game.wait

      expect(game.turn).to eq 0
    end
  end

  describe "#open" do
    it "opens a shut door and takes a turn" do
      shut = one_room "###\n#<+\n###", 1, 1

      expect(shut.open(Direction::East)).to be_true
      expect(shut.floor.terrain(2, 1)).to eq Terrain::OpenDoor
      expect(shut.turn).to eq 1
    end

    it "will not open rock, and costs no turn for trying" do
      shut = one_room "###\n#<+\n###", 1, 1

      expect(shut.open(Direction::North)).to be_false
      expect(shut.turn).to eq 0
    end

    it "will not open a door that is already open" do
      open = one_room "###\n#<'\n###", 1, 1

      expect(open.open(Direction::East)).to be_false
    end
  end

  describe "#close" do
    it "closes an open door and takes a turn" do
      open = one_room "###\n#<'\n###", 1, 1

      expect(open.close(Direction::East)).to be_true
      expect(open.floor.terrain(2, 1)).to eq Terrain::ClosedDoor
      expect(open.turn).to eq 1
    end

    it "will not close a door that is already shut" do
      shut = one_room "###\n#<+\n###", 1, 1

      expect(shut.close(Direction::East)).to be_false
      expect(shut.turn).to eq 0
    end
  end

  describe "#doors" do
    it "finds every shut door beside the character" do
      two = one_room "#+#\n#<+\n###", 1, 1

      expect(two.doors(Terrain::ClosedDoor).to_set)
        .to eq [Direction::North, Direction::East].to_set
    end

    it "finds nothing when there is nothing" do
      none = one_room "###\n#<#\n###", 1, 1

      expect(none.doors(Terrain::ClosedDoor)).to be_empty
    end

    it "looks on the diagonals too" do
      corner = one_room "##+\n#<#\n###", 1, 1

      expect(corner.doors(Terrain::ClosedDoor)).to eq [Direction::NorthEast]
    end
  end

  describe "#descend" do
    it "wins the run from the down staircase" do
      down = one_room "###\n#>#\n###", 1, 1

      expect(down.descend).to be_true
      expect(down.outcome).to eq Roguelike::Outcome::Won
      expect(down.over?).to be_true
    end

    it "does nothing anywhere else" do
      expect(game.descend).to be_false
      expect(game.outcome).to eq Roguelike::Outcome::Playing
      expect(game.over?).to be_false
    end
  end

  describe "#ascend" do
    it "ends the run from the up staircase, without a win" do
      expect(game.ascend).to be_true
      expect(game.outcome).to eq Roguelike::Outcome::Left
      expect(game.over?).to be_true
    end

    it "does nothing anywhere else" do
      away = one_room "###\n#.#\n###", 1, 1

      expect(away.ascend).to be_false
      expect(away.outcome).to eq Roguelike::Outcome::Playing
    end
  end

  describe "#standing_on" do
    it "answers the terrain under the character" do
      expect(game.standing_on).to eq Terrain::StairsUp
    end
  end

  describe "#blocking" do
    it "names what is in the way" do
      shut = one_room "###\n#<+\n###", 1, 1

      expect(shut.blocking(Direction::East)).to eq Terrain::ClosedDoor
      expect(shut.blocking(Direction::North)).to eq Terrain::Granite
    end

    it "answers nothing when the way is clear" do
      expect(game.blocking(Direction::East)).to be_nil
    end

    it "answers nothing off the floor" do
      edge = one_room "<", 0, 0

      expect(edge.blocking(Direction::East)).to be_nil
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      3.times { game.step Direction::East }
      again = described_class.from_json game.to_json

      expect(again.turn).to eq game.turn
      expect(again.player.at).to eq game.player.at
      expect(again.floor).to eq game.floor
      expect(again.world.seed).to eq game.world.seed
    end

    it "keeps playing from where it was read back" do
      5.times { game.step Direction::East }
      again = described_class.from_json game.to_json

      expect(again.step(Direction::South)).to eq game.step(Direction::South)
      expect(again.player.at).to eq game.player.at
    end

    it "keeps a door that was opened" do
      shut = one_room "###\n#<+\n###", 1, 1
      shut.open Direction::East

      again = described_class.from_json shut.to_json

      expect(again.floor.terrain(2, 1)).to eq Terrain::OpenDoor
    end

    it "keeps the outcome" do
      game.ascend
      again = described_class.from_json game.to_json

      expect(again.outcome).to eq Roguelike::Outcome::Left
    end
  end
end
