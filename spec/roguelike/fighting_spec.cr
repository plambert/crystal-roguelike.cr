require "../spec_helper"

Spectator.describe "fighting" do
  alias Advancement = Roguelike::Advancement
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Monster = Roguelike::Monster
  alias Outcome = Roguelike::Outcome
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias Step = Roguelike::Step
  alias World = Roguelike::World

  # The seed every example here fights on. A failure names a run somebody can
  # start.
  SEED = 20260912_u64

  # One lit room with the character in the middle.
  #
  # Every square beside the character is open, and the corners are two
  # squares away, so a spec can put a creature either beside the character or
  # out of reach.
  ROOM = [
    "#######",
    "#.....#",
    "#.....#",
    "#..<..#",
    "#.....#",
    "#.....#",
    "#######",
  ]

  # Where the character stands.
  HERE = {3, 3}

  # The square north of the character.
  BESIDE = {3, 2}

  # A game with one creature in it.
  #
  # *hit_points* is the creature's, and *health* and *experience* are the
  # character's. Each defaults to what the species or the character would
  # have.
  def arena(species : Species = Species::Slime,
            hit_points : Int32? = nil,
            at : {Int32, Int32} = BESIDE,
            health : Int32? = nil,
            experience : Int32 = 0) : {Game, Monster}
    floor = Playing.daylight Floor.parse("arena", ROOM)
    creature = Monster.new species, at[0], at[1], "band-one",
      hit_points: hit_points
    floor.place creature

    player = Player.new floor.id, *HERE, experience: experience,
      hit_points: health
    game = Game.new World.new(SEED, {floor.id => floor}), player

    {game, creature}
  end

  # Steps north until *stop* answers true, or until the swings run out.
  #
  # A swing is rolled, so a spec cannot say how many it takes. The count is
  # high enough that a fight decides inside it and low enough that a spec
  # that never decides still finishes.
  SWINGS = 200

  def fight(game : Game, &stop : -> Bool) : Int32
    SWINGS.times do |taken|
      return taken if stop.call

      game.step Direction::North
    end

    SWINGS
  end

  describe "walking into a creature" do
    it "swings at it and stays put" do
      game, _ = arena

      expect(game.step Direction::North).to eq Step::Struck
      expect(game.player.at).to eq HERE
    end

    it "takes a turn whether it lands or not" do
      game, _ = arena

      game.step Direction::North

      expect(game.turn).to eq 1
    end

    it "says what the swing did" do
      game, _ = arena

      game.step Direction::North

      said = game.log.lines.any? do |line|
        line.starts_with?("You hit the slime") || line == "You miss the slime."
      end

      expect(said).to be_true
    end

    it "takes hit points off when it lands" do
      game, creature = arena
      fight(game) { creature.hit_points < Species::Slime.hit_points }

      expect(creature.hit_points).to be < Species::Slime.hit_points
    end
  end

  describe "killing a creature" do
    it "takes it off the floor" do
      game, _ = arena hit_points: 1
      fight(game) { game.floor.monster(*BESIDE).nil? }

      expect(game.floor.monster(*BESIDE)).to be_nil
      expect(game.log.lines).to contain "You kill the slime."
    end

    it "awards the species' experience" do
      game, _ = arena hit_points: 1
      fight(game) { game.floor.monster(*BESIDE).nil? }

      expect(game.player.experience).to eq Species::Slime.experience
    end

    it "raises the level when the kill crosses the threshold" do
      game, _ = arena hit_points: 1,
        experience: Advancement.threshold(2) - Species::Slime.experience
      fight(game) { game.floor.monster(*BESIDE).nil? }

      expect(game.player.level).to eq 2
      expect(game.log.lines).to contain "Welcome to level 2."
    end

    it "leaves the level alone when it does not" do
      game, _ = arena hit_points: 1
      fight(game) { game.floor.monster(*BESIDE).nil? }

      expect(game.player.level).to eq 1
      expect(game.log.lines.none? &.starts_with?("Welcome to level")).to be_true
    end

    # A dead creature does not get the turn the killing blow took.
    it "is not swung at by what it killed" do
      game, _ = arena hit_points: 1
      fight(game) { game.floor.monster(*BESIDE).nil? }

      said = game.log.lines
      killed = said.index "You kill the slime."
      expect(killed).not_to be_nil
      expect(said[(killed || 0)..].none? &.starts_with?("The slime")).to be_true
    end
  end

  describe "a creature's own turn" do
    it "swings back at a character beside it" do
      game, _ = arena
      fight(game) { game.log.lines.any? &.starts_with?("The slime") }

      expect(game.log.lines.any? &.starts_with?("The slime")).to be_true
    end

    # A creature out of reach walks toward the character rather than
    # swinging from where it stands.
    it "does not swing from two squares away" do
      game, creature = arena at: {1, 1}
      away = creature.at

      game.step Direction::East

      swung = game.log.lines.any? do |line|
        line.starts_with?("The slime hits") || line.starts_with?("The slime misses")
      end

      expect(game.player.hit_points).to eq game.player.max_hit_points
      expect(creature.at).not_to eq away
      expect(swung).to be_false
    end

    # Any action that takes a turn gives a creature beside the character its
    # own, not only a swing. The character steps east and back again, and the
    # creature is beside them at both ends of that.
    it "takes its turn after a step as well as after a swing" do
      game, _ = arena
      before = game.player.hit_points

      30.times do
        break if game.player.hit_points < before

        game.step Direction::East
        game.step Direction::West
      end

      expect(game.player.hit_points).to be < before
      swung = game.log.lines.any? do |line|
        line.starts_with?("You hit") || line.starts_with?("You miss")
      end

      expect(swung).to be_false
    end
  end

  describe "the character dying" do
    it "ends the run" do
      game, _ = arena Species::Orc, health: 1
      fight(game) { game.over? }

      expect(game.outcome).to eq Outcome::Died
      expect(game.player.alive?).to be_false
    end

    it "says so" do
      game, _ = arena Species::Orc, health: 1
      fight(game) { game.over? }

      expect(game.log.lines.last).to eq "You die..."
    end
  end

  describe "the rolls" do
    it "counts every swing" do
      game, _ = arena

      game.step Direction::North

      # One swing out and one back.
      expect(game.blows).to eq 2
    end

    it "rolls the same fight twice from the same seed" do
      first, _ = arena
      second, _ = arena

      5.times do
        first.step Direction::North
        second.step Direction::North
      end

      expect(first.log.lines).to eq second.log.lines
      expect(first.player.hit_points).to eq second.player.hit_points
    end

    it "carries the count through serialization" do
      game, _ = arena
      3.times { game.step Direction::North }

      again = Game.from_json game.to_json

      expect(again.blows).to eq game.blows
      expect(again.player.hit_points).to eq game.player.hit_points
    end

    # A saved fight goes on rolling where it left off. The count names the
    # stream, so a reloaded game draws the numbers the first one would have.
    it "goes on where a saved game left off" do
      game, _ = arena
      3.times { game.step Direction::North }

      again = Game.from_json game.to_json
      again.step Direction::North
      game.step Direction::North

      expect(again.log.lines).to eq game.log.lines
    end
  end
end
