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
  alias Slot = Roguelike::Slot
  alias Costs = Roguelike::Costs
  alias Action = Roguelike::Action
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

  describe "a spike" do
    it "takes half a turn to drive" do
      game, _ = rooms Species::Slime, at: {8, 3}
      before = game.player.pace.energy

      spiked game

      expect(Costs::SPIKE).to eq Costs::TURN // 2
      expect(game.player.pace.energy - before).to eq Costs::TURN - Costs::SPIKE
    end
  end

  # A game on `ROOMS` with the door spiked from the west and the character
  # east of it with a short sword. Nothing else is on the floor.
  def barred(armed : Bool = true) : Game
    floor = Playing.daylight Floor.parse("rooms", ROOMS)
    floor.drive_spike DOOR[0], DOOR[1], Direction::West, Item.new(ItemKind::Spike)

    player = Player.new floor.id, 5, 1, hit_points: 500
    if armed
      letter = player.inventory.add Item.new(ItemKind::ShortSword)
      player.equipment.put Slot::Melee, letter if letter
    end

    game = Game.new World.new(SEED, {floor.id => floor}), player
    game.enroll
    game
  end

  # Swings at the door until it breaks. Answers how many swings it took.
  def broken(game : Game) : Int32
    swings = 1
    game.perform Action::Break.new(Direction::West)
    until game.floor.terrain(*DOOR).broken_door?
      raise "the door will not break" if swings > 30

      game.perform Action::Move.new(Direction::West)
      swings += 1
    end

    swings
  end

  describe "breaking a door" do
    it "swings once and makes the door the target" do
      game = barred

      expect(game.break_down Direction::West).to eq Step::Struck
      expect(game.door_target).to eq DOOR
      expect(game.floor.door_health(*DOOR)).to be < Floor::WOODEN_DOOR
      expect(game.turn).to eq 1
    end

    it "swings again on the next step into the door" do
      game = barred
      game.break_down Direction::West
      left = game.floor.door_health(*DOOR)

      expect(game.step Direction::West).to eq Step::Struck
      expect(game.floor.door_health(*DOOR)).to be < left
    end

    it "breaks into a doorway the character walks through" do
      game = barred

      broken game

      expect(game.floor.terrain(*DOOR)).to eq Terrain::BrokenDoor
      expect(game.door_target).to be_nil
      expect(game.floor.battered).to be_empty
      expect(game.log.lines.last).to eq "The door breaks!"
      expect(game.player.knowledge.barred?(*DOOR)).to be_false

      expect(game.step Direction::West).to eq Step::Moved
      expect(game.player.at).to eq DOOR
    end

    it "drops the spike on the side it was driven from" do
      game = barred

      broken game

      expect(game.floor.spiked?(*DOOR)).to be_false
      expect(game.floor.items(3, 1).map(&.kind)).to eq [ItemKind::Spike]
    end

    it "lets a goblin walk through the doorway" do
      game = barred
      broken game

      goblin = Monster.new Species::Goblin, 1, 1, "band-two"
      game.floor.place goblin
      game.enroll
      hunting game, goblin
      8.times { game.wait }

      expect(goblin.x).to be >= DOOR[0]
    end

    it "cannot be closed or spiked once broken" do
      game = barred
      broken game
      game.player.inventory.add Item.new(ItemKind::Spike, count: 2)

      expect(game.close Direction::West).to be_false
      expect(game.closeable).to be_empty
      expect(game.appliable.none? &.aimed?).to be_true
    end

    it "refuses bare hands, and takes no turn" do
      game = barred armed: false

      expect(game.break_down Direction::West).to eq Step::Blocked
      expect(game.turn).to eq 0
      expect(game.door_target).to be_nil
      expect(game.log.lines.last).to eq Game::BARE_DOOR
      expect(game.forcible? Direction::West).to be_false
    end

    it "refuses a door that opens" do
      game, _ = rooms Species::Slime, at: {8, 3}
      letter = game.player.inventory.add Item.new(ItemKind::ShortSword)
      game.player.equipment.put Slot::Melee, letter if letter

      expect(game.break_down Direction::East).to eq Step::Blocked
      expect(game.door_target).to be_nil
    end

    it "is offered to a bot while the door is stuck" do
      game = barred

      expect(game.legal.any? do |action|
        action.is_a?(Action::Break) && action.dir == Direction::West
      end).to be_true
    end

    it "gives up the target when a creature attacks" do
      game = barred
      game.break_down Direction::West

      orc = Monster.new Species::Orc, 6, 1, "band-two"
      game.floor.place orc
      game.enroll
      hunting game, orc
      until game.door_target.nil? || game.turn > 20
        game.wait
      end

      expect(game.door_target).to be_nil
    end

    it "gives up the target when the character walks away" do
      game = barred
      game.break_down Direction::West

      game.perform Action::Move.new(Direction::East)

      expect(game.door_target).to be_nil
    end

    it "tells a band near the door where the character is with one swing" do
      game = barred
      goblin = Monster.new Species::Goblin, 2, 3, "band-two"
      game.floor.place goblin
      game.enroll

      game.break_down Direction::West

      band = game.floor.band "band-two"
      expect(band.try &.awake?).to be_true
      expect(knowledge(game, goblin).sighting(Knowledge::PLAYER).try &.at).to eq game.player.at
    end

    it "round-trips a half broken door and the target" do
      game = barred
      game.break_down Direction::West

      again = Game.from_json game.to_json

      expect(again.door_target).to eq DOOR
      expect(again.floor.door_health(*DOOR)).to eq game.floor.door_health(*DOOR)
      expect(again.floor).to eq game.floor
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
