require "../spec_helper"

Spectator.describe "the quiver remembering its ammunition" do
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Player = Roguelike::Player
  alias Remembered = Roguelike::Equipment::Remembered
  alias Slot = Roguelike::Slot
  alias World = Roguelike::World

  # One lit hall with the character at the west end.
  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  # How far east a shot goes before it hits the end wall.
  EAST = {10, 1}

  # A game with the character at the west end, holding *held*.
  def armed(held : Array(Item)) : Game
    floor = Playing.daylight Floor.parse("hall", HALL)
    player = Player.new floor.id, 1, 1, hit_points: 500
    game = Game.new World.new(Playing::SEED, {floor.id => floor}), player
    held.each { |item| player.inventory.add item }
    game
  end

  # A game whose quiver has just loosed its last arrow, with *lying* on the
  # square to the south.
  def emptied(lying : Array(Item) = [] of Item) : Game
    game = armed [Item.new(Kind::Bow), Item.new(Kind::Arrow)]
    game.wield 'a'
    game.wield 'b'
    game.fire EAST
    lying.each { |item| game.floor.drop 1, 2, item }
    game
  end

  describe "emptying the quiver" do
    it "remembers the kind after the last shot" do
      game = emptied

      expect(game.player.quivered).to be_nil
      expect(game.player.quiver_memory.try &.kind).to eq Kind::Arrow
    end

    it "remembers the kind after the last throw" do
      game = armed [Item.new(Kind::Stone)]
      game.wield 'a'
      game.throw 'a', EAST

      expect(game.player.quivered).to be_nil
      expect(game.player.quiver_memory.try &.kind).to eq Kind::Stone
    end

    it "remembers what tells two stacks apart" do
      game = armed [Item.new(Kind::Stone, enchantment: 1)]
      game.wield 'a'
      game.throw 'a', EAST

      expect(game.player.quiver_memory.try &.enchantment).to eq 1
    end

    it "remembers nothing while some are left" do
      game = armed [Item.new(Kind::Stone, count: 3)]
      game.wield 'a'
      game.throw 'a', EAST

      expect(game.player.quiver_memory).to be_nil
    end

    it "remembers nothing when a stack that was not quivered runs out" do
      game = armed [Item.new(Kind::Stone)]
      game.throw 'a', EAST

      expect(game.player.quiver_memory).to be_nil
    end
  end

  describe "walking over ammunition" do
    it "puts the remembered kind back in the quiver" do
      game = emptied [Item.new(Kind::Arrow, count: 4)]

      game.step Roguelike::Direction::South

      expect(game.player.quivered.try &.count).to eq 4
      expect(game.player.quiver_memory).to be_nil
      expect(game.here).to be_empty
      expect(game.log.lines.any? &.includes?("in your quiver")).to be_true
    end

    it "costs no turn of its own" do
      game = emptied [Item.new(Kind::Arrow, count: 4)]
      before = game.turn

      game.step Roguelike::Direction::South

      expect(game.turn).to eq before + 1
    end

    it "leaves another kind where it lies" do
      game = emptied [Item.new(Kind::Stone, count: 4)]

      game.step Roguelike::Direction::South

      expect(game.player.quivered).to be_nil
      expect(game.here.size).to eq 1
      expect(game.player.quiver_memory.try &.kind).to eq Kind::Arrow
    end

    it "leaves the same kind with a different enchantment" do
      game = emptied [Item.new(Kind::Arrow, count: 4, enchantment: 1)]

      game.step Roguelike::Direction::South

      expect(game.player.quivered).to be_nil
      expect(game.here.size).to eq 1
    end
  end

  describe "picking up with ," do
    it "readies the remembered kind" do
      game = emptied
      game.floor.drop 1, 1, Item.new(Kind::Arrow, count: 4)

      expect(game.pick_up(game.here.first)).to be_true
      expect(game.player.quivered.try &.kind).to eq Kind::Arrow
      expect(game.player.quiver_memory).to be_nil
    end

    it "leaves another kind in the pack" do
      game = emptied
      game.floor.drop 1, 1, Item.new(Kind::Stone, count: 4)

      expect(game.pick_up(game.here.first)).to be_true
      expect(game.player.quivered).to be_nil
      expect(game.player.quiver_memory.try &.kind).to eq Kind::Arrow
    end
  end

  describe "forgetting" do
    it "forgets when another kind of ammunition is wielded" do
      game = emptied [Item.new(Kind::Arrow, count: 4)]
      game.player.inventory.add Item.new(Kind::Stone, count: 3)
      game.wield 'b'

      expect(game.player.quivered.try &.kind).to eq Kind::Stone
      expect(game.player.quiver_memory).to be_nil

      game.step Roguelike::Direction::South

      expect(game.here.size).to eq 1
    end

    it "remembers the new kind once that runs out" do
      game = emptied
      game.player.inventory.add Item.new(Kind::Stone)
      game.wield 'b'
      game.throw 'b', EAST

      expect(game.player.quiver_memory.try &.kind).to eq Kind::Stone
    end

    it "forgets when the quiver is taken off and refuses to drop it first" do
      game = armed [Item.new(Kind::Arrow, count: 4)]
      game.wield 'a'

      expect(game.drop 'a').to be_false

      game.take_off Slot::Quiver
      game.drop 'a'

      expect(game.player.quiver_memory).to be_nil

      game.step Roguelike::Direction::East
      game.step Roguelike::Direction::West

      expect(game.player.inventory.empty?).to be_true
    end
  end

  describe "serialization" do
    it "keeps the memory through a save" do
      game = emptied
      again = Game.from_json game.to_json

      expect(again.player.quiver_memory).not_to be_nil
      expect(again.player.quiver_memory).to eq game.player.quiver_memory
    end

    # A save written before the quiver remembered anything has no field.
    it "loads a save without the field" do
      game = armed [Item.new(Kind::Arrow)]
      text = game.to_json

      expect(text).not_to contain "quiver_memory"
      expect(Game.from_json(text).player.quiver_memory).to be_nil
    end
  end

  describe Remembered do
    it "matches only what would share the quiver's letter" do
      memory = Remembered.of Item.new(Kind::Arrow, count: 7)

      expect(memory.matches? Item.new(Kind::Arrow, count: 2)).to be_true
      expect(memory.matches? Item.new(Kind::Arrow, enchantment: 1)).to be_false
      expect(memory.matches? Item.new(Kind::Stone)).to be_false
    end
  end
end
