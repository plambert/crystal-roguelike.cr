require "../spec_helper"

Spectator.describe "creatures and doors" do
  alias Apply = Roguelike::Apply
  alias Awareness = Roguelike::Awareness
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Notice = Roguelike::Notice
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias Step = Roguelike::Step
  alias Terrain = Roguelike::Terrain
  alias World = Roguelike::World

  SEED = 20260930_u64

  # Two rooms joined by one shut door at 4,1. The character starts west of
  # it and a creature east of it.
  ROOMS = [
    "##########",
    "#...+....#",
    "#.<.#....#",
    "#...#....#",
    "##########",
  ]

  DOOR = {4, 1}

  # A game on `ROOMS` with the character at *hero* and one creature at *at*.
  #
  # The band has walked the whole floor and knows where the character is,
  # so the door is the only thing between them. The character carries three
  # spikes.
  def rooms(species : Species = Species::Goblin, at : {Int32, Int32} = {7, 1},
            hero : {Int32, Int32} = {3, 1}) : {Game, Monster}
    floor = Playing.daylight Floor.parse("rooms", ROOMS)
    creature = Monster.new species, at[0], at[1], "band-one"
    floor.place creature

    player = Player.new floor.id, hero[0], hero[1], hit_points: 500
    player.inventory.add Item.new(ItemKind::Spike, count: 3)
    game = Game.new World.new(SEED, {floor.id => floor}), player
    hunting game, creature

    {game, creature}
  end

  # Tells the band *creature* belongs to the whole floor and where the
  # character stands.
  def hunting(game : Game, creature : Monster) : Nil
    band = knowledge game, creature
    game.floor.each { |column, row, _tile| band.see game.floor, column, row }
    band.saw Knowledge::PLAYER, game.player.x, game.player.y, game.turn
    game.floor.band(creature.band).try &.awareness = Awareness::Hunting
  end

  def knowledge(game : Game, creature : Monster) : Knowledge
    band = game.floor.band creature.band
    raise "the floor has lost the band" unless band

    band.knowledge game.floor.id
  end

  # The letter the character carries spikes under.
  def spikes(game : Game) : Char
    game.player.inventory.each { |letter, item| return letter if item.kind.spike? }
    raise "the character carries no spikes"
  end

  def spiked(game : Game) : Bool
    game.apply Apply.aimed(spikes(game), *DOOR)
  end

  describe "a goblin behind a shut door" do
    it "opens it and comes on" do
      game, creature = rooms

      8.times { game.wait }

      expect(game.floor.terrain(*DOOR)).to eq Terrain::OpenDoor
      expect(Notice.touching? creature.at, game.player.at).to be_true
      expect(game.log.lines.any? &.includes?("opens the door")).to be_true
    end

    it "spends a turn opening it" do
      game, creature = rooms at: {5, 1}

      game.wait
      expect(game.floor.terrain(*DOOR)).to eq Terrain::OpenDoor
      expect(creature.at).to eq({5, 1})

      game.wait
      expect(creature.at).to eq DOOR
    end
  end

  describe "a slime behind a shut door" do
    it "stays behind it" do
      game, creature = rooms Species::Slime

      12.times { game.wait }

      expect(game.floor.terrain(*DOOR)).to eq Terrain::ClosedDoor
      expect(creature.x).to be > DOOR[0]
    end
  end

  describe "a spiked door" do
    it "takes a spike out of the pack" do
      game, _ = rooms

      expect(spiked game).to be_true
      expect(game.floor.spiked?(*DOOR)).to be_true
      expect(game.player.inventory.count spikes(game)).to eq 2
    end

    it "is offered to apply only once" do
      game, _ = rooms

      expect(game.appliable).to contain Apply.aimed(spikes(game), *DOOR)
      spiked game
      expect(game.appliable.none? &.aimed?).to be_true
    end

    it "stops a goblin on the far side" do
      game, creature = rooms
      spiked game

      20.times { game.wait }

      expect(game.floor.terrain(*DOOR)).to eq Terrain::ClosedDoor
      expect(creature.x).to be > DOOR[0]
      expect(knowledge(game, creature).barred?(*DOOR)).to be_true
    end

    it "opens from the near side and gives the spike back" do
      game, _ = rooms
      spiked game

      expect(game.open Direction::East).to be_true
      expect(game.floor.terrain(*DOOR)).to eq Terrain::OpenDoor
      expect(game.floor.spiked?(*DOOR)).to be_false
      expect(game.player.inventory.count spikes(game)).to eq 3
      expect(game.log.lines.last).to contain "pull the spike"
    end

    it "does not open from the far side, and takes no turn trying" do
      game, _ = rooms Species::Slime, at: {8, 3}, hero: {5, 1}
      game.floor.drive_spike DOOR[0], DOOR[1], Direction::West, Item.new(ItemKind::Spike)
      turn = game.turn

      expect(game.step Direction::West).to eq Step::Blocked
      expect(game.turn).to eq turn
      expect(game.floor.terrain(*DOOR)).to eq Terrain::ClosedDoor
      expect(game.player.knowledge.barred?(*DOOR)).to be_true
      expect(game.player.knowledge.crossable?(*DOOR)).to be_false
    end

    it "is not offered as a step or an open from the far side" do
      game, _ = rooms Species::Slime, at: {8, 3}, hero: {5, 1}
      game.floor.drive_spike DOOR[0], DOOR[1], Direction::West, Item.new(ItemKind::Spike)

      legal = game.legal
      expect(legal.any?(Roguelike::Action::Open)).to be_false
      expect(legal.any? do |action|
        action.is_a?(Roguelike::Action::Move) && action.dir == Direction::West
      end).to be_false
    end

    it "opens for a goblin on the spiked side, and the spike drops" do
      game, _ = rooms at: {3, 1}, hero: {8, 3}
      game.floor.drive_spike DOOR[0], DOOR[1], Direction::West, Item.new(ItemKind::Spike)

      game.wait

      expect(game.floor.terrain(*DOOR)).to eq Terrain::OpenDoor
      expect(game.floor.spiked?(*DOOR)).to be_false
    end
  end

  describe "saving" do
    it "round-trips a spiked door" do
      game, _ = rooms
      spiked game

      again = Game.from_json game.to_json

      expect(again.floor.spiked?(*DOOR)).to be_true
      expect(again.floor.spike(*DOOR).try &.side).to eq Direction::West
      expect(again.floor).to eq game.floor

      # The spec's own items and creature are given ids on the first load, so
      # the second load is the one that has to change nothing.
      expect(Game.from_json(again.to_json).to_json).to eq again.to_json
    end

    it "remembers the spike it saw" do
      game, _ = rooms
      spiked game

      again = Knowledge.from_json game.player.knowledge.to_json

      expect(again[*DOOR].try &.spiked?).to be_true
      expect(again).to eq game.player.knowledge
    end

    it "round-trips a door a band found barred" do
      game, creature = rooms
      spiked game
      20.times { game.wait }

      again = Knowledge.from_json knowledge(game, creature).to_json

      expect(again.barred?(*DOOR)).to be_true
    end

    it "writes nothing about spikes when there are none" do
      game, _ = rooms

      text = game.to_json

      expect(text).not_to contain %("spikes")
      expect(text).not_to contain "barred"
      expect(text).not_to contain "spiked"
      expect(Floor.from_json(game.floor.to_json)).to eq game.floor
    end
  end
end
