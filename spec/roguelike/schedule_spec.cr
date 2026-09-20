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

  describe "the speed of each species" do
    # Counted from the energy rather than from how far it walked. A creature
    # that puts a foot wrong still spent the action, and `Species#clumsiness`
    # means every species puts a foot wrong sometimes.
    def actions_taken(creature : Monster, ticks : Int32) : Int32
      earned = Pace::TICK + ticks * creature.pace.base
      (earned - creature.pace.energy) // Pace::TICK
    end

    # A creature walking at the character takes one action per tick at the
    # character's own speed.
    def chasing(species : Species, turns : Int32) : Int32
      game = bare
      found = creature game, species, 20, 3
      rouse game, found

      mark_time game, turns
      actions_taken found, turns
    end

    it "gives a goblin an action for every one of the character's" do
      expect(chasing Species::Goblin, 100).to eq 100
    end

    it "gives an orc ninety-five in a hundred" do
      expect(chasing Species::Orc, 100).to eq 95
    end

    it "gives a slime four for the character's five" do
      expect(chasing Species::Slime, 100).to eq 80
    end

    it "holds the ratio over a long chase" do
      expect(chasing Species::Slime, 1000).to eq 800
      expect(chasing Species::Orc, 1000).to eq 950
    end
  end

  describe "walking away from something" do
    # A long hall, so a chase has somewhere to run.
    LONG = ["#" * 62,
            "#" + "." * 60 + "#",
            "#" * 62]

    # How far behind *species* is after the character walks *turns* squares
    # away from it, starting three squares ahead of it.
    #
    # Three squares is inside every species' notice range, so the creature
    # goes on seeing the character rather than losing them and giving up.
    # What this measures is how much ground a creature turns its actions
    # into while the character spends every one of theirs walking.
    def gap_after(species : Species, turns : Int32) : Int32
      floor = Roguelike::Floor.parse "long", LONG.join('\n')
      floor.ambient = 1

      game = Roguelike::Game.new(
        Roguelike::World.new(Playing::SEED, {"long" => floor}),
        Roguelike::Player.new("long", 5, 1, hit_points: 500))

      found = creature game, species, 2, 1
      rouse game, found
      turns.times { game.step Direction::East }

      game.player.x - found.x
    end

    # A slime can be walked away from, an orc falls behind slowly, and a
    # goblin keeps up. Over forty turns from three squares back the gaps come
    # out at thirty, four and three.
    it "leaves a slime furthest behind and a goblin nearest" do
      slime = gap_after Species::Slime, 40
      orc = gap_after Species::Orc, 40
      goblin = gap_after Species::Goblin, 40

      expect(slime).to be > orc
      expect(orc).to be >= goblin
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
