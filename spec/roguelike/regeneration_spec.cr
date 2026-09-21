require "../spec_helper"

Spectator.describe "hit points coming back on their own" do
  alias Direction = Roguelike::Direction
  alias Species = Roguelike::Species
  alias Monster = Roguelike::Monster
  alias Game = Roguelike::Game

  # A lit hall with the character in the middle of the west end.
  HALL = ["######################",
          "#....................#",
          "#..<.................#",
          "#....................#",
          "######################"]

  # Ticks a hit point takes at average constitution.
  RATE = Roguelike::Advancement::REGENERATION

  # A game with the character *down* hit points and *constitution*.
  def bare(down : Int32 = 0,
           constitution : Int32 = Roguelike::Attributes::AVERAGE) : Roguelike::Game
    floor = Roguelike::Floor.parse "hall", HALL.join('\n')
    floor.ambient = 1

    game = Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}),
      Roguelike::Player.new("hall", 3, 2,
        attributes: Roguelike::Attributes.new(constitution: constitution)))
    game.player.hurt down

    game
  end

  # Takes *turns* turns without the character going anywhere. They step east
  # and back again, so neither step is ever blocked.
  def mark_time(game : Roguelike::Game, turns : Int32) : Nil
    turns.times do |taken|
      game.step taken.even? ? Direction::East : Direction::West
    end
  end

  describe "while nothing has hurt the character" do
    it "puts nothing back inside the first ten turns" do
      game = bare 6
      before = game.player.hit_points

      mark_time game, Game::REST

      expect(game.player.hit_points).to eq before
    end

    it "puts one hit point back at the end of the first stretch" do
      game = bare 6
      before = game.player.hit_points

      mark_time game, RATE

      expect(game.player.hit_points).to eq before + 1
    end

    it "puts one back every twenty turns after that" do
      game = bare 6
      before = game.player.hit_points

      mark_time game, 3 * RATE

      expect(game.player.hit_points).to eq before + 3
    end

    it "says nothing about it" do
      game = bare 6
      mark_time game, RATE

      expect(game.log.lines.any? &.includes?("heal")).to be_false
      expect(game.log.lines.any? &.includes?("better")).to be_false
    end

    it "stops at full health" do
      game = bare 1
      mark_time game, 10 * RATE

      expect(game.player.hit_points).to eq game.player.max_hit_points
    end
  end

  describe "when something hurts the character" do
    # A creature standing beside the character, awake and swinging.
    def beset(down : Int32) : {Roguelike::Game, Monster}
      game = bare down
      spot = Direction::East.from game.player.x, game.player.y
      creature = Monster.new Species::Goblin, spot[0], spot[1], "band-beside"
      game.floor.place creature

      band = game.floor.band creature.band
      raise "the floor has lost the band" unless band
      band.awareness = Roguelike::Awareness::Hunting

      {game, creature}
    end

    it "puts the count back to nothing" do
      game = bare 6
      mark_time game, Game::REST
      game.player.hurt 1

      expect(game.player.rested).to eq 0
    end

    it "puts nothing back while it is being hit" do
      game, _creature = beset 6
      before = game.player.hit_points
      mark_time game, RATE

      expect(game.player.hit_points).to be <= before
    end

    it "starts the count again from the last wound" do
      game = bare 6
      mark_time game, RATE - 1
      game.player.hurt 1
      before = game.player.hit_points

      mark_time game, RATE - 1

      expect(game.player.hit_points).to eq before
    end
  end

  describe "constitution" do
    it "comes back sooner for a tough character" do
      tough = bare 6, constitution: 18
      weak = bare 6, constitution: 3

      expect(tough.player.regeneration).to be < RATE
      expect(weak.player.regeneration).to be > RATE
    end

    # Eight ticks a point at eighteen against thirty-two at three. The first
    # point waits for the first multiple of the rate past the ten ticks of
    # going unhurt, so forty turns is four points against one.
    it "puts back four points to a weak character's one" do
      tough = bare 6, constitution: 18
      weak = bare 6, constitution: 3
      started = {tough.player.hit_points, weak.player.hit_points}

      mark_time tough, 40
      mark_time weak, 40

      expect(tough.player.hit_points - started[0]).to eq 4
      expect(weak.player.hit_points - started[1]).to eq 1
    end

    it "leaves an average character where it was" do
      game = bare 6

      mark_time game, 40

      expect(game.player.regeneration).to eq RATE
    end

    # A modifier so high that the rate reached nothing would heal a point
    # every tick and then some.
    it "never comes back faster than the floor allows" do
      expect(Roguelike::Advancement.regeneration 100)
        .to eq Roguelike::Advancement::REGENERATION_LEAST
    end
  end

  describe "the count itself" do
    it "starts at nothing" do
      game = bare

      expect(game.player.rested).to eq 0
    end

    it "counts ticks rather than actions of the character" do
      game = bare 6
      game.player.pace.hurry 1000

      mark_time game, 3 * RATE

      expect(game.player.rested).to eq game.turn
    end

    it "goes through a save" do
      game = bare 6
      mark_time game, 5

      read = Roguelike::Game.from_json game.to_json

      expect(read.player.rested).to eq game.player.rested
    end
  end
end
