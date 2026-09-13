require "../spec_helper"

Spectator.describe Roguelike::Knowledge do
  alias Floor = Roguelike::Floor
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Source = Roguelike::LightSource
  alias Terrain = Roguelike::Terrain
  alias Vision = Roguelike::Vision

  ROOM = [
    "#######",
    "#.....#",
    "#..<..#",
    "#.....#",
    "#######",
  ]

  def spot : Floor
    Playing.daylight Floor.parse("room", ROOM)
  end

  subject(knowledge) { described_class.new "room" }

  it "starts knowing nothing" do
    expect(knowledge.empty?).to be_true
    expect(knowledge.size).to eq 0
    expect(knowledge[3, 2]).to be_nil
    expect(knowledge.seen? 3, 2).to be_false
  end

  describe "#see" do
    it "records what is on a square" do
      floor = spot
      knowledge.see floor, 3, 2, 7

      memory = knowledge[3, 2]
      raise "nothing was remembered" unless memory

      expect(memory.terrain).to eq Terrain::StairsUp
      expect(memory.turn).to eq 7
      expect(knowledge.seen? 3, 2).to be_true
    end

    it "records the top of the pile" do
      floor = spot
      floor.drop 1, 1, Item.new Kind::Dagger
      floor.drop 1, 1, Item.new Kind::Cap

      knowledge.see floor, 1, 1
      expect(knowledge[1, 1].try &.item.try &.kind).to eq Kind::Cap
    end

    it "records a fixture" do
      floor = Playing.daylight Floor.parse("lit", ["#####", "#.|.#", "#...#", "#####"])
      knowledge.see floor, 2, 1

      expect(knowledge[2, 1].try &.fixture.try &.kind).to eq Roguelike::FixtureKind::Sconce
    end

    it "ignores a square off the floor" do
      knowledge.see spot, 99, 99

      expect(knowledge.empty?).to be_true
    end

    it "replaces what was remembered before" do
      floor = spot
      knowledge.see floor, 1, 1, 1
      floor.drop 1, 1, Item.new Kind::Dagger
      knowledge.see floor, 1, 1, 9

      expect(knowledge[1, 1].try &.item).not_to be_nil
      expect(knowledge[1, 1].try &.turn).to eq 9
    end
  end

  # A memory is a copy rather than a view. The floor goes on changing after a
  # creature looks away, and what they remember does not.
  describe "what it holds is a copy" do
    it "keeps the item as it was after the one on the floor changes" do
      floor = spot
      torch = Item.new Kind::Torch
      floor.drop 1, 1, torch

      knowledge.see floor, 1, 1
      torch.kindle

      expect(torch.lit?).to be_true
      expect(knowledge[1, 1].try &.item.try &.lit?).to be_false
    end

    it "keeps the fixture as it was after the one on the floor is lit" do
      floor = Playing.daylight Floor.parse("lit", ["#####", "#.|.#", "#...#", "#####"])
      fitting = floor.fixture 2, 1
      raise "no sconce" unless fitting

      knowledge.see floor, 2, 1
      fitting.kindle

      expect(fitting.lit?).to be_true
      expect(knowledge[2, 1].try &.fixture.try &.lit?).to be_false
    end

    it "keeps the terrain as it was after a door opens" do
      floor = Playing.daylight Floor.parse("door", ["###", "#+#", "###"])

      knowledge.see floor, 1, 1
      floor.set 1, 1, Terrain::OpenDoor

      expect(knowledge[1, 1].try &.terrain).to eq Terrain::ClosedDoor
    end
  end

  describe "#learn" do
    it "records every square a vision reaches and no other" do
      floor = spot
      vision = Vision.from floor, 3, 2, [] of Source

      knowledge.learn floor, vision, 4

      expect(knowledge.size).to eq vision.size
      vision.each { |square| expect(knowledge.seen? square[0], square[1]).to be_true }
    end

    it "records nothing outside the vision" do
      floor = Playing.daylight Floor.parse("rooms",
        ["#######", "#..#..#", "#######"])
      knowledge.learn floor, Vision.from(floor, 1, 1, [] of Source), 0

      expect(knowledge.seen? 1, 1).to be_true
      expect(knowledge.seen? 5, 1).to be_false
    end
  end

  describe "#age" do
    it "says how many turns ago a square was seen" do
      knowledge.see spot, 1, 1, 3

      memory = knowledge[1, 1]
      raise "nothing was remembered" unless memory

      expect(memory.age 10).to eq 7
      expect(memory.age 3).to eq 0
      expect(memory.age 1).to eq 0
    end
  end

  # A monster that has seen the character goes to where it saw them rather
  # than to where they are now.
  describe "where somebody was last seen" do
    it "records a square and a turn" do
      knowledge.saw Roguelike::Knowledge::PLAYER, 4, 7, 12

      sighting = knowledge.sighting Roguelike::Knowledge::PLAYER
      raise "nobody was seen" unless sighting

      expect(sighting.at).to eq({4, 7})
      expect(sighting.turn).to eq 12
      expect(sighting.age 20).to eq 8
      expect(sighting.age 12).to eq 0
    end

    it "answers nothing for somebody never seen" do
      expect(knowledge.sighting Roguelike::Knowledge::PLAYER).to be_nil
    end

    it "replaces the square when they are seen again" do
      knowledge.saw Roguelike::Knowledge::PLAYER, 4, 7, 12
      knowledge.saw Roguelike::Knowledge::PLAYER, 9, 2, 30

      expect(knowledge.sighting(Roguelike::Knowledge::PLAYER).try &.at).to eq({9, 2})
    end

    it "keeps one per creature seen" do
      knowledge.saw Roguelike::Knowledge::PLAYER, 4, 7, 12
      knowledge.saw "goblin-one", 1, 1, 3

      expect(knowledge.sighting(Roguelike::Knowledge::PLAYER).try &.at).to eq({4, 7})
      expect(knowledge.sighting("goblin-one").try &.at).to eq({1, 1})
    end

    it "forgets one on its own" do
      knowledge.saw Roguelike::Knowledge::PLAYER, 4, 7, 12
      knowledge.lost Roguelike::Knowledge::PLAYER

      expect(knowledge.sighting Roguelike::Knowledge::PLAYER).to be_nil
    end

    it "round-trips through JSON" do
      knowledge.saw Roguelike::Knowledge::PLAYER, 4, 7, 12
      again = described_class.from_json knowledge.to_json

      expect(again).to eq knowledge
      expect(again.sighting(Roguelike::Knowledge::PLAYER).try &.at).to eq({4, 7})
    end
  end

  # A band whose members each keep their own beliefs gives each of them a
  # copy to start from. What one learns after that is its own.
  describe "#copy" do
    it "holds what the original held" do
      knowledge.learn spot, Vision.lit(spot, 3, 2), 4
      knowledge.saw Roguelike::Knowledge::PLAYER, 1, 1, 4

      expect(knowledge.copy).to eq knowledge
    end

    it "goes its own way after that" do
      knowledge.saw Roguelike::Knowledge::PLAYER, 1, 1, 4
      mine = knowledge.copy
      mine.saw Roguelike::Knowledge::PLAYER, 8, 8, 9

      expect(knowledge.sighting(Roguelike::Knowledge::PLAYER).try &.at).to eq({1, 1})
      expect(mine.sighting(Roguelike::Knowledge::PLAYER).try &.at).to eq({8, 8})
    end

    it "does not share what it remembers of the floor" do
      knowledge.see spot, 1, 1, 1
      mine = knowledge.copy
      mine.see spot, 2, 2, 2

      expect(knowledge.size).to eq 1
      expect(mine.size).to eq 2
    end
  end

  describe "#forget" do
    it "throws everything away" do
      knowledge.learn spot, Vision.lit(spot, 3, 2), 0
      knowledge.saw Roguelike::Knowledge::PLAYER, 1, 1, 0
      knowledge.forget

      expect(knowledge.empty?).to be_true
      expect(knowledge.sightings).to be_empty
    end
  end

  describe "#to_map" do
    it "draws what is remembered and the unknown mark elsewhere" do
      floor = Playing.daylight Floor.parse("rooms", ["#####", "#.#.#", "#####"])
      knowledge.learn floor, Vision.from(floor, 1, 1, [] of Source), 0

      expect(knowledge.to_map(floor).join '\n').to eq "###??\n#.#??\n###??"
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      floor = spot
      floor.drop 1, 1, Item.new Kind::Dagger
      knowledge.learn floor, Vision.lit(floor, 3, 2), 5

      again = described_class.from_json knowledge.to_json

      expect(again).to eq knowledge
      expect(again.floor).to eq "room"
      expect(again.size).to eq knowledge.size
      expect(again[1, 1].try &.item.try &.kind).to eq Kind::Dagger
      expect(again[1, 1].try &.turn).to eq 5
    end

    it "round-trips a fixture through JSON" do
      floor = Playing.daylight Floor.parse("lit", ["#####", "#.!.#", "#...#", "#####"])
      knowledge.learn floor, Vision.lit(floor, 2, 2), 0

      again = described_class.from_json knowledge.to_json

      expect(again[2, 1].try &.fixture.try &.lit?).to be_true
      expect(again[2, 1].try &.fixture.try &.attached).to eq Roguelike::Direction::North
    end
  end

  describe "on the player" do
    it "gives the floor they stand on an empty one" do
      player = Roguelike::Player.new "room", 3, 2

      expect(player.knowledge.floor).to eq "room"
      expect(player.knowledge.empty?).to be_true
    end

    it "keeps one per floor" do
      player = Roguelike::Player.new "room", 3, 2
      player.knowledge.see spot, 1, 1

      player.floor = "cellar"
      expect(player.knowledge.empty?).to be_true

      player.floor = "room"
      expect(player.knowledge.size).to eq 1
    end

    it "answers nothing for a floor never walked on" do
      expect(Roguelike::Player.new("room", 3, 2).knowledge?("cellar")).to be_nil
    end

    it "round-trips through JSON" do
      player = Roguelike::Player.new "room", 3, 2
      player.knowledge.see spot, 1, 1, 2

      again = Roguelike::Player.from_json player.to_json

      expect(again.memory).to eq player.memory
      expect(again.knowledge[1, 1].try &.turn).to eq 2
    end
  end
end
