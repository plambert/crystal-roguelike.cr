require "../spec_helper"

Spectator.describe "factions" do
  alias Awareness = Roguelike::Awareness
  alias Band = Roguelike::Band
  alias Faction = Roguelike::Faction
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Kind = Roguelike::Kind
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  SEED = 20260930_u64

  # One lit room. The character starts on the staircase at the west end.
  HALL = [
    "####################",
    "#<.................#",
    "#..................#",
    "#..................#",
    "####################",
  ]

  # A lit corridor with the character on the staircase.
  CORRIDOR = [
    "#########",
    "#.....<.#",
    "#########",
  ]

  # Two rooms with no way between them. The character is in the west one.
  APART = [
    "####################",
    "#<..#..............#",
    "#...#..............#",
    "####################",
  ]

  # A game on *lines*, lit throughout, with *creatures* placed. Each is a
  # kind, a square and a band id.
  def game_on(lines : Array(String),
              creatures : Array({Kind, {Int32, Int32}, String})) : {Game, Array(Monster)}
    floor = Playing.daylight Floor.parse("factions", lines)
    placed = creatures.map do |kind, spot, band|
      Monster.new(kind, spot[0], spot[1], band).tap { |creature| floor.place creature }
    end

    player = Player.new floor.id, *Game.entrance(floor), hit_points: 5000
    game = Game.new World.new(SEED, {floor.id => floor}), player
    game.enroll

    {game, placed}
  end

  # How many swings *attacker* has aimed at *target* since the events were
  # last cleared.
  def swings(game : Game, attacker : Monster, target : Monster) : Int32
    game.events.count do |event|
      attack = event.as? Roguelike::Event::Attack
      !attack.nil? && attack.attacker == attacker.id && attack.target == target.id
    end
  end

  describe "who is hostile to whom" do
    it "sets goblins and orcs against each other" do
      expect(Faction::Goblin.hostile? Faction::Orc).to be_true
      expect(Faction::Orc.hostile? Faction::Goblin).to be_true
    end

    it "sets goblins and orcs against slimes" do
      expect(Faction::Goblin.hostile? Faction::Slime).to be_true
      expect(Faction::Slime.hostile? Faction::Orc).to be_true
    end

    it "sets slimes against other slimes" do
      expect(Faction::Slime.hostile? Faction::Slime).to be_true
    end

    it "keeps goblins with goblins and orcs with orcs" do
      expect(Faction::Goblin.hostile? Faction::Goblin).to be_false
      expect(Faction::Orc.hostile? Faction::Orc).to be_false
    end

    it "keeps an old save's dungeon faction out of every fight" do
      Faction.each do |other|
        expect(Faction::Dungeon.hostile? other).to be_false
      end
    end

    it "never sets a band against itself" do
      band = Band.new "slimes", Faction::Slime

      expect(band.hostile? band).to be_false
      expect(band.hostile? Band.new("others", Faction::Slime)).to be_true
    end

    it "names a faction for every kind of each species" do
      Kind.each do |kind|
        expected = case kind.species
                   in .slime?  then Faction::Slime
                   in .goblin? then Faction::Goblin
                   in .orc?    then Faction::Orc
                   end
        expect(kind.faction).to eq expected
      end
    end

    it "gives a placed band its first member's faction" do
      game, _placed = game_on HALL, [{Kind::Orc, {9, 2}, "orcs"}]

      expect(game.floor.band("orcs").try &.faction).to eq Faction::Orc
    end
  end

  describe "a goblin band and an orc band in one room" do
    it "fight each other" do
      game, placed = game_on HALL, [
        {Kind::GoblinWarrior, {12, 1}, "goblins"},
        {Kind::GoblinWarrior, {12, 3}, "goblins"},
        {Kind::Orc, {15, 1}, "orcs"},
        {Kind::Orc, {15, 3}, "orcs"},
      ]

      60.times { game.wait unless game.felled > 0 }

      expect(game.felled).to be > 0
      expect(placed.any? { |creature| !creature.alive? }).to be_true
      expect(game.player.hit_points).to eq 5000
    end

    it "tells the character about blows they can see" do
      game, _placed = game_on HALL, [
        {Kind::GoblinWarrior, {12, 2}, "goblins"},
        {Kind::Orc, {14, 2}, "orcs"},
      ]

      20.times { game.wait }

      told = game.log.lines.select &.includes?("the goblin warrior")
      expect(told.any? &.starts_with?("The orc ")).to be_true
    end
  end

  describe "a slime" do
    it "attacks a goblin beside it" do
      game, placed = game_on HALL, [
        {Kind::BlueSlime, {15, 2}, "slime"},
        {Kind::GoblinWarrior, {16, 2}, "goblin"},
      ]
      slime, goblin = placed

      5.times { game.wait }

      expect(swings(game, slime, goblin)).to be > 0
    end
  end

  describe "choosing a quarry" do
    it "prefers the character at an equal distance" do
      # The slime is blind, so it never wakes or moves.
      game, placed = game_on CORRIDOR, [
        {Kind::WhiteSlime, {2, 1}, "slime"},
        {Kind::GoblinWarrior, {4, 1}, "goblin"},
      ]
      placed[0].blind 1000

      game.wait

      expect(placed[1].x).to eq 5
    end

    it "takes the nearer hostile when it is nearer" do
      game, placed = game_on CORRIDOR, [
        {Kind::WhiteSlime, {3, 1}, "slime"},
        {Kind::GoblinWarrior, {4, 1}, "goblin"},
      ]
      placed[0].blind 1000

      game.wait

      expect(placed[1].x).to eq 4
      expect(swings(game, placed[1], placed[0])).to eq 1
    end
  end

  describe "a kill by a creature" do
    it "gives the character no experience and drops what the victim carried" do
      game, placed = game_on HALL, [
        {Kind::GoblinWarrior, {12, 2}, "goblin"},
        {Kind::Orc, {13, 2}, "orc"},
      ]
      goblin = placed[0]
      goblin.carry [Item.new(ItemKind::ShortSword)]
      goblin.hurt goblin.hit_points - 1
      at = goblin.at

      30.times { game.wait if goblin.alive? }

      expect(goblin.alive?).to be_false
      expect(game.felled).to eq 1
      expect(game.player.experience).to eq 0
      expect(game.floor.items(*at).map(&.kind)).to contain ItemKind::ShortSword
    end
  end

  describe "a fight out of sight" do
    it "tells the character nothing" do
      game, _placed = game_on APART, [
        {Kind::GoblinWarrior, {12, 1}, "goblins"},
        {Kind::Orc, {13, 1}, "orcs"},
      ]
      floor = game.floor
      {"goblins" => {13, 1}, "orcs" => {12, 1}}.each do |id, foe|
        band = floor.band id
        other = floor.monster(*foe)
        raise "the floor has lost a creature" unless band && other

        band.knowledge(floor.id).saw Knowledge.creature(other.id), *foe, game.turn
        band.awareness = Awareness::Hunting
      end

      40.times { game.wait unless game.felled > 0 }

      expect(game.felled).to eq 1
      expect(game.log.lines.none? &.includes?("goblin")).to be_true
    end
  end

  describe "a save" do
    it "keeps a goblin band's faction and the fight counters" do
      game, _placed = game_on HALL, [
        {Kind::GoblinWarrior, {12, 2}, "goblins"},
        {Kind::Orc, {14, 2}, "orcs"},
      ]
      10.times { game.wait }

      again = Game.from_json game.to_json

      expect(again.floor.band("goblins").try &.faction).to eq Faction::Goblin
      expect(again.brawls).to eq game.brawls
      expect(again.felled).to eq game.felled
      expect(again.to_json).to eq game.to_json
    end

    it "loads a band an old save calls dungeon" do
      band = Band.from_json %({"id":"old","faction":"dungeon","sharing":"inherited","memory":{},"awareness":"asleep"})

      expect(band.faction).to eq Faction::Dungeon
      expect(Band.from_json(band.to_json)).to eq band
    end
  end

  describe "one seed" do
    # One creature kills another in the first 400 turns from this seed.
    it "plays the same fights twice" do
      first = Roguelike::Trial.one 5016_u64, 400
      second = Roguelike::Trial.one 5016_u64, 400

      expect(first.felled).to eq 1
      expect(second).to eq first
    end
  end
end
