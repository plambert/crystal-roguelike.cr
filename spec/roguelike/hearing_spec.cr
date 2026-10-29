require "../spec_helper"

Spectator.describe "hearing" do
  alias Awareness = Roguelike::Awareness
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Noise = Roguelike::Noise
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  SEED = 20261028_u64

  # A long dark hall over a sealed cell. Nothing can see in the dark, so
  # whatever wakes here has heard something.
  HALL = [
    "######################",
    "#....................#",
    "#....................#",
    "#....................#",
    "######################",
    "#....................#",
    "######################",
  ]

  # Where the character stands.
  HERE = {1, 2}

  # A dark run on `HALL` with *monsters* on the floor.
  def hall(monsters : Array(Monster)) : Game
    floor = Floor.parse "hall", HALL
    monsters.each { |creature| floor.place creature }

    player = Player.new floor.id, *HERE, hit_points: 500
    player.inventory.add Item.new(ItemKind::Rock, count: 5)

    game = Game.new World.new(SEED, {floor.id => floor}), player
    game.enroll
    game
  end

  # A goblin at *at*, asleep, in a band of its own.
  def goblin(at : {Int32, Int32}) : Monster
    Monster.new Species::Goblin, at[0], at[1], "band-#{at[0]}-#{at[1]}", hit_points: 200
  end

  # The band *creature* belongs to.
  def band(game : Game, creature : Monster)
    found = game.floor.band creature.band
    raise "no band for #{creature}" unless found

    found
  end

  # Where *creature*'s band believes the character is.
  def believed(game : Game, creature : Monster) : {Int32, Int32}?
    band(game, creature).knowledge(game.floor.id).sighting(Knowledge::PLAYER).try &.at
  end

  describe "a swing" do
    it "wakes a band within its reach and tells it where the character is" do
      target = goblin({2, 2})
      near = goblin({1 + Noise::BLOW, 2})
      game = hall [target, near]

      game.attack target

      expect(band(game, near).awake?).to be_true
      expect(believed(game, near)).to eq HERE
    end

    it "leaves a band past its reach asleep" do
      target = goblin({2, 2})
      far = goblin({2 + Noise::BLOW, 2})
      game = hall [target, far]

      game.attack target

      expect(band(game, far).awareness).to eq Awareness::Asleep
    end

    it "does not carry through a wall" do
      target = goblin({2, 2})
      cell = goblin({1, 5})
      game = hall [target, cell]

      game.attack target

      expect(band(game, cell).awareness).to eq Awareness::Asleep
    end
  end

  describe "waking" do
    it "stands still for the turn it stirs and searches after" do
      target = goblin({2, 2})
      near = goblin({7, 2})
      game = hall [target, near]

      game.attack target

      expect(near.at).to eq({7, 2})
      expect(band(game, near).awareness).to eq Awareness::Alert
    end

    it "is still stirring at the end of the turn it heard a fight" do
      orc = Monster.new Species::Orc, 8, 2, "band-orcs", hit_points: 500
      slime = Monster.new Species::Slime, 9, 2, "band-slimes", hit_points: 500
      other = Monster.new Species::Slime, 12, 2, "band-other", hit_points: 500
      game = hall [orc, slime, other]
      band(game, orc).awareness = Awareness::Hunting
      band(game, orc).knowledge(game.floor.id).saw Knowledge.creature(slime.id), 9, 2, game.turn

      game.wait

      expect(band(game, other).awareness).to eq Awareness::Stirring
      game.wait
      expect(band(game, other).awake?).to be_true
    end

    it "says a creature the character can see stirs" do
      floor = Playing.daylight Floor.parse("hall", HALL)
      target = goblin({2, 2})
      near = goblin({7, 2})
      near.blind 1000
      [target, near].each { |creature| floor.place creature }
      player = Player.new floor.id, *HERE, hit_points: 500
      game = Game.new World.new(SEED, {floor.id => floor}), player
      game.enroll

      game.attack target

      expect(game.log.lines).to contain "The #{near.label} stirs."
    end
  end

  describe "a thrown rock" do
    it "draws a band to where it landed rather than to the character" do
      near = goblin({12, 1})
      game = hall [near]
      spot = {10, 2}

      game.throw 'a', spot

      expect(band(game, near).awake?).to be_true
      expect(believed(game, near)).to eq spot
    end
  end

  describe "the noise reading" do
    it "rises to how far the sound carried and falls a square a turn" do
      target = goblin({2, 2})
      game = hall [target]

      game.attack target
      carried = game.noise

      expect(carried).to eq Noise::BLOW
      game.wait
      expect(game.noise).to eq carried - Noise::FADE
    end

    it "keeps the sounds of the last action until the next" do
      target = goblin({2, 2})
      game = hall [target]

      game.perform Roguelike::Action::Move.new(Roguelike::Direction::East)
      expect(game.echoes.size).to eq 1
      expect(game.echoes.first.at).to eq HERE

      game.perform Roguelike::Action::Wait.new
      expect(game.echoes).to be_empty
    end

    it "is zero for a character who has made no noise" do
      game = hall [] of Monster

      game.wait

      expect(game.noise).to eq 0
    end
  end

  describe "a sound out of sight" do
    it "is marked on the last square in sight toward it" do
      orc = Monster.new Species::Orc, 8, 2, "band-orcs", hit_points: 500
      slime = Monster.new Species::Slime, 9, 2, "band-slimes", hit_points: 500
      game = hall [orc, slime]
      band(game, orc).awareness = Awareness::Hunting
      band(game, orc).knowledge(game.floor.id).saw Knowledge.creature(slime.id), 9, 2, game.turn

      until game.overheard.present? || game.turn > 6
        game.perform Roguelike::Action::Wait.new
      end

      expect(game.overheard.first.mark).to eq({2, 2})
      expect(game.overheard.first.source).to eq Noise::Source::Blow
    end
  end

  describe "a fight out of sight" do
    it "is told to the character once while it goes on" do
      orc = Monster.new Species::Orc, 8, 2, "band-orcs", hit_points: 500
      slime = Monster.new Species::Slime, 9, 2, "band-slimes", hit_points: 500
      game = hall [orc, slime]
      band(game, orc).awareness = Awareness::Hunting
      band(game, orc).knowledge(game.floor.id).saw Knowledge.creature(slime.id), 9, 2, game.turn

      6.times { game.wait }

      heard = game.log.lines.count &.starts_with?("You hear fighting")
      expect(heard).to eq 1
    end
  end
end
