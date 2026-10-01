require "../spec_helper"

Spectator.describe "floors of the dungeon" do
  alias Game = Roguelike::Game
  alias Generator = Roguelike::Generator
  alias Item = Roguelike::Item
  alias ItemClass = Roguelike::ItemClass
  alias ItemKind = Roguelike::ItemKind
  alias Loot = Roguelike::Loot
  alias Outcome = Roguelike::Outcome
  alias Rng = Roguelike::Rng
  alias Species = Roguelike::Species
  alias Spawns = Roguelike::Spawns
  alias Terrain = Roguelike::Terrain
  alias World = Roguelike::World

  SEED = 20260930_u64

  # How many floors or items an example about a table rolls.
  FLOORS =   12
  ROLLS  = 4000

  # The square *terrain* is on, on the floor the character stands on.
  def spot(game : Game, terrain : Terrain) : {Int32, Int32}
    found = game.floor.find terrain
    raise "#{game.floor.id} has no #{terrain}" unless found

    found
  end

  # Takes *game* down *floors* staircases.
  def down(game : Game, floors : Int32 = 1) : Game
    floors.times do
      game.player.move_to spot(game, Terrain::StairsDown)
      raise "no staircase down on #{game.floor.id}" unless game.descend
    end
    game
  end

  # Takes *game* up one staircase.
  def up(game : Game) : Game
    game.player.move_to spot(game, Terrain::StairsUp)
    raise "no staircase up on #{game.floor.id}" unless game.ascend
    game
  end

  describe World do
    it "names a floor by its depth" do
      expect(World.id 3).to eq "floor-3"
      expect(World.depth "floor-3").to eq 3
    end

    it "counts the floor of an older save as floor 1" do
      expect(World.depth World::LEGACY).to eq 1
    end

    it "gives a floor outside the numbering no depth" do
      expect(World.depth "proving-ground").to be_nil
    end
  end

  describe "Game.dug" do
    it "starts on floor 1" do
      game = Game.dug Rng.new(SEED)

      expect(game.floor.id).to eq "floor-1"
      expect(game.depth).to eq 1
      expect(game.world.size).to eq 1
    end
  end

  describe "Game#descend" do
    it "puts the character on the up staircase of the floor below" do
      game = down Game.dug(Rng.new SEED)

      expect(game.floor.id).to eq "floor-2"
      expect(game.depth).to eq 2
      expect(game.standing_on).to eq Terrain::StairsUp
      expect(game.outcome.playing?).to be_true
    end

    it "keeps the floor above" do
      game = down Game.dug(Rng.new SEED)

      expect(game.world.has? "floor-1").to be_true
      expect(game.world.size).to eq 2
    end

    it "says where the character went" do
      game = down Game.dug(Rng.new SEED)
      climbed = game.events.select(Roguelike::Event::Climbed)

      expect(climbed.map &.floor).to eq ["floor-2"]
    end

    it "digs a floor once and finds it again after that" do
      game = down Game.dug(Rng.new SEED)
      below = game.floor
      marker = Item.new ItemKind::Dagger, enchantment: 1
      below.drop game.player.x, game.player.y, marker

      down up(game)

      expect(game.floor).to be below
      expect(game.here).to contain marker
    end

    it "wins the run from a floor outside the numbering" do
      game = Game.start Rng.new(SEED)
      game.player.move_to spot(game, Terrain::StairsDown)
      game.descend

      expect(game.outcome.won?).to be_true
    end
  end

  describe "Game#ascend" do
    it "puts the character on the down staircase of the floor above" do
      game = up down(Game.dug(Rng.new SEED))

      expect(game.floor.id).to eq "floor-1"
      expect(game.standing_on).to eq Terrain::StairsDown
      expect(game.outcome.playing?).to be_true
    end

    it "leaves the dungeon from floor 1" do
      game = up Game.dug(Rng.new SEED)

      expect(game.outcome.left?).to be_true
    end
  end

  # The generator names every stream after the floor, and the floor's name
  # holds its depth, so the order floors are dug in changes nothing.
  describe "Game#dig" do
    it "digs the same floor whichever floors came first" do
      first = Game.dug Rng.new(SEED)
      third = first.dig 3

      again = Game.dug Rng.new(SEED)
      again.dig 2
      after = again.dig 3

      expect(after).to eq third
    end

    it "digs a different floor at each depth" do
      game = Game.dug Rng.new(SEED)

      expect(game.dig(2).to_map).not_to eq game.dig(3).to_map
    end
  end

  describe Spawns do
    it "puts white and blue slimes and goblin scouts on floor 1, and nothing else" do
      expect(Spawns.weights(1).keys.to_set)
        .to eq Set{Roguelike::Kind::WhiteSlime, Roguelike::Kind::BlueSlime, Roguelike::Kind::GoblinScout}
    end

    it "puts no orc above floor 3" do
      (1..2).each do |depth|
        expect(Spawns.weights(depth).keys.map(&.species)).not_to contain Species::Orc
      end
    end

    it "makes orcs commoner from floor 4" do
      orcs = (3..4).map { |depth| Spawns.weights(depth, Species::Orc).values.sum }

      expect(orcs[1]).to be > orcs[0]
    end

    it "digs floor 1 with those kinds only" do
      allowed = Spawns.weights(1).keys

      FLOORS.times do |index|
        floor = Generator.floor Rng.new(SEED + index), World.id(1), 1

        floor.each_monster do |_column, _row, creature|
          expect(allowed).to contain creature.kind
        end
      end
    end

    it "fills a deeper floor at least as full" do
      (1...5).each do |depth|
        expect(Spawns.density(depth + 1).inhabited).to be >= Spawns.density(depth).inhabited
      end
    end
  end

  describe Loot do
    it "holds a long sword back from floor 1" do
      expect(Loot.allowed? ItemKind::LongSword, 1).to be_false
      expect(Loot.allowed? ItemKind::LongSword, 2).to be_true
    end

    it "holds a kind back as long as its class is held back" do
      expect(Loot.from ItemKind::LightWand).to eq 2
      expect(Loot.from ItemKind::StrikingWand).to eq 3
    end

    it "hands nothing held back or above +1 out on floor 1" do
      rng = Rng.new SEED

      ROLLS.times do
        item = Roguelike::Items.random rng, 1

        expect(Loot.allowed? item.kind, 1).to be_true
        expect(item.enchantment).to be <= 1
      end
    end

    it "arms nothing on floor 1 with what is held back" do
      rng = Rng.new SEED

      ROLLS.times do
        Loot.for(Species::Goblin, rng, 1).each do |item|
          expect(Loot.allowed? item.kind, 1).to be_true
          expect(item.enchantment).to be <= 1
        end
      end
    end
  end

  describe "the amulet" do
    it "lies in the chamber under the last floor" do
      chamber = Generator.chamber
      found = [] of Item
      chamber.each_pile { |_column, _row, pile| found.concat pile }

      expect(found.map &.kind).to eq [ItemKind::Amulet]
      expect(chamber.find Terrain::StairsUp).not_to be_nil
      expect(chamber.find Terrain::StairsDown).to be_nil
    end

    it "is under floor 5" do
      game = down Game.dug(Rng.new SEED), World::DEEPEST

      expect(game.floor.id).to eq World.id(World::VAULT)
      expect(game.deepest).to eq World::VAULT
    end

    it "wins the run when it is picked up" do
      game = down Game.dug(Rng.new SEED), World::DEEPEST
      amulet = nil
      game.floor.each_pile do |column, row, pile|
        amulet = {column, row} if pile.any? &.kind.amulet?
      end
      raise "no amulet" unless amulet

      game.player.move_to amulet
      game.pick_up game.here.first

      expect(game.outcome).to eq Outcome::Won
    end

    it "is named without an article on the floor, in the hand and in the pack" do
      game = down Game.dug(Rng.new SEED), World::DEEPEST
      name = "The Mighty Amulet of MacGuffin"
      game.floor.each_pile do |column, row, pile|
        game.player.move_to({column, row}) if pile.any? &.kind.amulet?
      end

      expect(game.name game.here.first).to eq name

      game.pick_up game.here.first
      expect(game.log.last?).to eq "The Mighty Amulet of MacGuffin is yours. The dungeon has nothing left to keep you."
      letter, _ = game.player.inventory.entries.find! &.[1].kind.amulet?
      expect(game.name_under letter).to eq name
    end

    it "lies in the chamber plain and uncursed" do
      amulet = nil
      Generator.chamber.each_pile { |_c, _r, pile| amulet = pile.first }

      expect(amulet.try &.blessing).to eq Roguelike::Blessing::Uncursed
      expect(amulet.try &.enchantment).to eq 0
      expect(amulet.try &.condition).to eq Roguelike::Condition::Plain
    end
  end

  describe "the rule under the map" do
    it "names a floor by its depth" do
      expect(Roguelike::Ui::Play.floor_name Generator.chamber(World.id 2)).to eq "Floor 2"
    end

    it "names the chamber the amulet is in" do
      expect(Roguelike::Ui::Play.floor_name Generator.chamber).to eq "The amulet chamber"
    end

    it "names nothing for a floor outside the numbering" do
      expect(Roguelike::Ui::Play.floor_name Roguelike::Floors.proving_ground).to be_nil
    end
  end

  describe "the screen" do
    it "names the floor under the map and shows the depth beside the level" do
      run = Playing.open Game.dug(Rng.new SEED)

      expect(run.text).to contain "Floor 1"
      expect(run.text).to contain "D1 Lv 1"
    end

    it "follows the character down a staircase" do
      game = Game.dug Rng.new(SEED)
      run = Playing.open game
      game.player.move_to spot(game, Terrain::StairsDown)
      run.press ">"

      expect(run.text).to contain "Floor 2"
      expect(run.text).to contain "D2 Lv 1"
    end
  end

  describe "a save" do
    it "comes back with three floors" do
      game = down Game.dug(Rng.new SEED), 2
      again = Game.from_json game.to_json

      expect(again.world.size).to eq 3
      expect(again.floor.id).to eq "floor-3"
      expect(again.to_json).to eq game.to_json
      %w[floor-1 floor-2 floor-3].each do |id|
        expect(again.world[id]).to eq game.world[id]
      end
    end

    it "goes on from a single floor written before there were several" do
      old = Generator.floor Rng.new(SEED), World::LEGACY, 1
      game = Game.from_json Game.start(Rng.new(SEED), old).to_json

      expect(game.depth).to eq 1

      down game
      expect(game.floor.id).to eq "floor-2"

      up game
      expect(game.floor.id).to eq World::LEGACY
    end
  end
end
