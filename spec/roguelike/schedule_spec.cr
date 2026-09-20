require "../spec_helper"

Spectator.describe "the tick loop" do
  alias Direction = Roguelike::Direction
  alias Species = Roguelike::Species
  alias Monster = Roguelike::Monster
  alias Pace = Roguelike::Pace

  # A lit hall, twenty across, with the character in the middle of the left
  # end and room to walk east.
  HALL = ["######################",
          "#....................#",
          "#....................#",
          "#..<.................#",
          "#....................#",
          "#....................#",
          "######################"]

  def bare : Roguelike::Game
    floor = Roguelike::Floor.parse "hall", HALL.join('\n')
    floor.ambient = 1

    Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"hall" => floor}),
      Roguelike::Player.new("hall", 3, 3)
  end

  # Puts a creature of *species* at *x*, *y* and answers it.
  def creature(game : Roguelike::Game, species : Species,
               x : Int32, y : Int32) : Monster
    found = Monster.new species, x, y, "band-#{x}-#{y}"
    game.floor.place found
    found
  end

  # Tells the band *creature* belongs to that it has walked this floor and
  # that the character is where they stand now.
  def rouse(game : Roguelike::Game, creature : Monster) : Nil
    band = game.floor.band creature.band
    raise "the floor has lost the band" unless band

    knowledge = band.knowledge game.floor.id
    game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
    knowledge.saw Roguelike::Knowledge::PLAYER, game.player.x, game.player.y, game.turn
    band.awareness = Roguelike::Awareness::Hunting
  end

  # Passes *turns* turns without the character going anywhere. They step east
  # and back again, which takes a turn each way.
  def mark_time(game : Roguelike::Game, turns : Int32) : Nil
    turns.times do |taken|
      game.step taken.even? ? Direction::East : Direction::West
    end
  end

  describe "one action of the character" do
    it "takes one turn" do
      game = bare
      before = game.turn

      game.step Direction::East

      expect(game.turn).to eq before + 1
    end

    it "takes ten turns over ten steps" do
      game = bare
      10.times { game.step Direction::East }

      expect(game.turn).to eq 10
    end

    # The character pays for the action before the world catches up, so they
    # are ready again when the loop stops.
    it "leaves the character ready to act" do
      game = bare
      game.step Direction::East

      expect(game.player.pace.ready?).to be_true
    end
  end

  describe "a creature at the character's speed" do
    it "acts once for each action of the character" do
      game = bare
      goblin = creature game, Species::Goblin, 16, 3
      rouse game, goblin
      start = goblin.at

      game.step Direction::West

      expect(goblin.at).not_to eq start
    end

    # The character steps east and back again, which takes a turn each way
    # and leaves them where they started. A creature at their speed closes
    # one square a turn.
    it "closes one square for each turn of the character" do
      game = bare
      goblin = creature game, Species::Goblin, 18, 3
      rouse game, goblin

      mark_time game, 10

      expect(goblin.x).to eq 8
    end
  end

  describe "a creature that is asleep" do
    # A band that slept for fifty turns would otherwise wake with fifty
    # actions in hand and cross the room in one turn of the character's.
    it "banks nothing while it sleeps" do
      game = bare
      slime = creature game, Species::Slime, 18, 3
      50.times { game.step Direction::West }

      expect(slime.pace.energy).to eq Pace::TICK
    end

    it "acts on the turn it wakes" do
      game = bare
      goblin = creature game, Species::Goblin, 16, 3
      start = goblin.at
      rouse game, goblin

      game.step Direction::East

      expect(goblin.at).not_to eq start
    end
  end

  describe "written out" do
    it "carries the energy through a save" do
      game = bare
      game.step Direction::East
      game.player.pace.spend 40

      read = Roguelike::Game.from_json game.to_json

      expect(read.player.pace.energy).to eq game.player.pace.energy
    end

    # The base belongs to the species, so a creature loaded from a save is as
    # fast as its kind however it was written.
    it "takes a creature's speed from its species" do
      game = bare
      creature game, Species::Slime, 10, 3

      read = Roguelike::Game.from_json game.to_json
      loaded = read.floor.monster 10, 3

      expect(loaded.try &.pace.base).to eq Species::Slime.speed
    end
  end
end
