require "../spec_helper"

Spectator.describe "the creature last fought" do
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Naming = Roguelike::Ui::Naming
  alias Palette = Roguelike::Ui::Palette
  alias Player = Roguelike::Player
  alias Regard = Roguelike::Regard
  alias Size = Roguelike::Size
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # The seed every example here fights on. A failure names a run somebody can
  # start.
  SEED = 20260913_u64

  # One lit room with the character in the middle, and a sealed square under
  # it.
  #
  # A creature in the sealed square can neither walk to the character nor
  # swing at them, so an example about how long the bar holds is not also an
  # example about what a woken creature does next.
  ROOM = [
    "###########",
    "#.........#",
    "#....<....#",
    "#.........#",
    "###########",
    "####.######",
    "###########",
  ]

  # Where the character stands.
  HERE = {5, 2}

  # The square north of the character.
  BESIDE = {5, 1}

  # The sealed square.
  SEALED = {4, 5}

  # A dark corridor with a lit torch at the far end.
  #
  # The torch throws six squares, so the east end is lit and the west end is
  # dark. A creature standing in the dark part of it shows against the light
  # behind it and is made out as a shape.
  CORRIDOR = ["#" * 25, "#" + "." * 23 + "#", "#" * 25]

  # Where the character stands in the corridor, and where the torch lies.
  WEST_END  = {1, 1}
  TORCH_LIT = {20, 1}

  # A game with one creature in it.
  #
  # *hit_points* is the creature's. The room is lit unless *light* says
  # otherwise.
  def arena(species : Species = Species::Goblin,
            hit_points : Int32? = nil,
            at : {Int32, Int32} = BESIDE) : {Game, Monster}
    floor = Playing.daylight Floor.parse("arena", ROOM)
    creature = Monster.new species, at[0], at[1], "band-one",
      hit_points: hit_points
    floor.place creature

    player = Player.new floor.id, *HERE
    {Game.new(World.new(SEED, {floor.id => floor}), player), creature}
  end

  # A game with one creature standing between the character and a torch.
  def backlit(at : {Int32, Int32} = {5, 1}) : {Game, Monster}
    floor = Floor.parse "corridor", CORRIDOR
    floor.drop TORCH_LIT[0], TORCH_LIT[1], Playing.torch

    creature = Monster.new Species::Goblin, at[0], at[1], "band-one"
    floor.place creature

    player = Player.new floor.id, *WEST_END
    {Game.new(World.new(SEED, {floor.id => floor}), player), creature}
  end

  # The creature the bar is about, or a failure saying there is none.
  def fought(game : Game) : Monster
    found = game.fought
    raise "no creature is being fought" unless found

    found
  end

  describe "what raises it" do
    it "is raised by the character swinging" do
      game, creature = arena
      game.attack creature

      expect(fought(game).same? creature).to be_true
    end

    # A miss is a blow aimed at something, which is dealing with it. A person
    # who has just missed wants to know how much is left in what they missed.
    it "is raised by a swing that misses" do
      game, creature = arena hit_points: 40
      20.times { game.attack creature }

      expect(game.log.lines.any? &.starts_with?("You miss")).to be_true
      expect(fought(game).same? creature).to be_true
    end

    it "is raised by the creature swinging" do
      game, creature = arena
      swung = false

      20.times do
        game.wait
        swung = game.log.lines.any? do |line|
          line.starts_with?("The #{creature.label} hits you") ||
            line.starts_with?("The #{creature.label} misses you")
        end
        break if swung
      end

      expect(swung).to be_true
      expect(fought(game).same? creature).to be_true
    end

    # A shot is a blow aimed at a distance. An arrow, a thrown rock and a
    # bolt from a wand all land on the creature the same way a sword does,
    # and a person shooting wants the same reading as a person swinging.
    it "is raised by a shot" do
      game, _creature = arena at: SEALED
      game.player.inventory.add Item.new Kind::Bow
      game.player.inventory.add Item.new Kind::Arrow, count: 12
      game.wield 'a'
      game.wield 'b'

      # Placed after the readying, which takes two turns. A creature put down
      # before them would have walked somewhere else by the time the shot
      # goes.
      target = Monster.new Species::Orc, 8, 2, "band-two"
      game.floor.place target
      game.fire target.at

      expect(fought(game).same? target).to be_true
    end
  end

  describe "what it reads" do
    it "reads the creature's hit points" do
      game, creature = arena hit_points: 4
      game.attack creature

      expect(fought(game).hit_points).to eq creature.hit_points
      expect(fought(game).max_hit_points).to eq Species::Goblin.hit_points
    end

    it "names a creature the character can see by its species" do
      game, creature = arena
      game.attack creature

      expect(game.fought_regard).to eq Regard::Everything
      expect(Naming.creature creature, game.fought_regard).to eq "goblin"
    end

    it "names a creature that is only a shape by its size" do
      game, creature = backlit
      game.attack creature

      expect(game.fought_regard).to eq Regard::Shape
      expect(Naming.creature creature, game.fought_regard)
        .to eq Species::Goblin.size.short
    end

    # A creature seen in the light is the same creature once it steps into
    # the dark, so the closer look is kept.
    it "keeps the closer of two looks at the same creature" do
      game, creature = arena
      game.attack creature
      game.floor.ambient = 0
      game.attack creature

      expect(game.regard_of creature).to eq Regard::Nothing
      expect(game.fought_regard).to eq Regard::Everything
    end

    it "forgets what was made out when the fight moves to another creature" do
      game, creature = backlit
      other = Monster.new Species::Orc, 6, 1, "band-two"
      game.floor.place other

      game.attack creature
      game.attack other

      expect(fought(game).same? other).to be_true
      expect(game.fought_regard).to eq Regard::Shape
    end
  end

  describe "when it goes away" do
    it "goes when the creature dies" do
      game, creature = arena hit_points: 1
      while creature.alive?
        game.attack creature
      end

      expect(game.fought).to be_nil
    end

    it "holds while the fight is recent" do
      game, creature = arena at: SEALED
      game.attack creature
      (Game::FIGHT_LASTS - 2).times { game.wait }

      expect(game.turn - game.fought_turn).to eq Game::FIGHT_LASTS - 1
      expect(fought(game).same? creature).to be_true
    end

    it "goes after the timeout" do
      game, creature = arena at: SEALED
      game.attack creature
      (Game::FIGHT_LASTS - 1).times { game.wait }

      expect(game.turn - game.fought_turn).to eq Game::FIGHT_LASTS
      expect(game.fought).to be_nil
    end

    it "starts the count again on every exchange" do
      game, creature = arena at: SEALED, hit_points: 40
      game.attack creature
      (Game::FIGHT_LASTS - 2).times { game.wait }
      game.attack creature
      (Game::FIGHT_LASTS - 2).times { game.wait }

      expect(fought(game).same? creature).to be_true
    end

    # A creature that walks into the dark is still the one the character has
    # been hitting, and how hurt it was is worth reading.
    it "holds while the creature is out of sight" do
      game, creature = arena at: SEALED
      game.attack creature

      expect(game.regard_of creature).to eq Regard::Nothing
      expect(fought(game).same? creature).to be_true
    end
  end

  describe "through a save" do
    it "finds the creature again" do
      game, creature = arena hit_points: 4
      game.attack creature
      loaded = Game.from_json game.to_json
      found = loaded.fought

      expect(found).not_to be_nil
      expect(found.try &.at).to eq creature.at
      expect(found.try &.hit_points).to eq creature.hit_points
      expect(loaded.fought_turn).to eq game.fought_turn
      expect(loaded.fought_regard).to eq game.fought_regard
    end

    # The creature is named by the square it stands on rather than written
    # out again, so the save holds one copy of it and no more.
    it "writes the square rather than the creature" do
      game, creature = arena
      game.attack creature
      written = JSON.parse game.to_json

      expect(written["fought_at"].as_a.map &.as_i).to eq [creature.x, creature.y]
    end

    it "loads a save written before the field existed" do
      game, creature = arena
      game.attack creature
      written = JSON.parse(game.to_json).as_h
      written.delete "fought_at"
      written.delete "fought_turn"
      written.delete "fought_regard"

      loaded = Game.from_json written.to_json
      expect(loaded.fought).to be_nil
      expect(loaded.fought_regard).to eq Regard::Nothing
    end
  end

  describe "the bar in the sidebar" do
    # A run on *game*, drawn in a window of *rows*.
    def playing(game : Game, rows : Int32 = 40) : Playing::Run
      Playing.open game, 80, rows
    end

    it "is hidden while there is no fight" do
      game, _creature = arena
      run = playing game

      expect(run.play.character.fight.hidden?).to be_true
    end

    it "shows the creature's name and count" do
      game, creature = arena hit_points: 4
      run = playing game
      game.attack creature
      run.play.refresh

      expect(run.play.character.fight.hidden?).to be_false
      expect(run.play.character.threat.reading)
        .to eq "goblin #{creature.hit_points}/#{creature.max_hit_points}"
    end

    it "draws the bar against the creature's hit points" do
      game, creature = arena hit_points: 4
      run = playing game
      game.attack creature
      run.play.refresh

      expect(run.play.character.threat.value).to eq creature.hit_points
      expect(run.play.character.threat.most).to eq creature.max_hit_points
    end

    it "labels the bar apart from the character's own" do
      game, _creature = arena
      run = playing game

      expect(run.play.character.threat.label)
        .to eq Roguelike::Ui::CharacterPane::THREAT_LABEL
      expect(run.play.character.health.label).to eq "HP"
    end

    # The bar is the last thing the pane gives up, and the character's own
    # bars are never given up at all.
    it "gives the row up on a screen with no room for it" do
      game, creature = arena
      run = playing game
      game.attack creature
      run.play.refresh

      expect(run.play.character.fight.hidden?).to be_false

      run.resize 80, 18
      expect(run.play.character.fight.hidden?).to be_true
      expect(run.play.character.health.hidden?).to be_false
      expect(run.play.character.learning.hidden?).to be_false
    end
  end

  describe "the colours" do
    # The bar runs the other way from the character's own. A creature at full
    # strength is red and one about to fall is yellow.
    it "is red at full and yellow at empty" do
      expect(Palette.meter Palette::THREAT, 100).to eq Palette::RED
      expect(Palette.meter Palette::THREAT, 0).to eq Palette::YELLOW
    end

    it "shades between the two" do
      quarter = Palette.meter Palette::THREAT, 25

      expect(quarter).not_to eq Palette::RED
      expect(quarter).not_to eq Palette::YELLOW
      expect(quarter.channels[0]).to be > Palette::YELLOW.channels[0]
    end

    it "runs the other way from the character's own bar" do
      expect(Palette.meter Palette::HEALTH, 100).to eq Palette::GREEN
      expect(Palette.meter Palette::THREAT, 100).to eq Palette::RED
    end
  end
end
