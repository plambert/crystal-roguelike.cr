require "../spec_helper"

Spectator.describe "what a monster leaves behind" do
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Rng = Roguelike::Rng
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  SEED = 20260912_u64

  # One lit room with the character in the middle and a creature beside them.
  ROOM = [
    "#######",
    "#.....#",
    "#..g..#",
    "#..<..#",
    "#.....#",
    "#######",
  ]

  # Where the creature stands, north of the character.
  BESIDE = {3, 2}

  # A game with one goblin carrying *held*.
  def holding(held : Array(Item) = [] of Item) : {Game, Monster}
    floor = Playing.daylight Floor.parse("room", ROOM)
    creature = floor.monster(*BESIDE)
    raise "the room has lost its goblin" unless creature
    creature.carry held

    player = Player.new floor.id, *Game.entrance(floor), hit_points: 500
    {Game.new(World.new(SEED, {floor.id => floor}), player), creature}
  end

  # Swings north until the creature is off the floor.
  def kill(game : Game) : Nil
    200.times do
      break unless game.floor.monster(*BESIDE)

      game.step Direction::North
    end
  end

  describe "killing it" do
    it "puts what it carried on the square it died on" do
      game, _ = holding [Item.new(Kind::ShortSword), Item.new(Kind::Cap)]

      kill game

      pile = game.floor.items(*BESIDE).map &.kind
      expect(pile).to contain Kind::ShortSword
      expect(pile).to contain Kind::Cap
    end

    it "leaves a torch it was carrying still burning" do
      game, _ = holding [Item.new(Kind::Torch, lit: true)]

      kill game

      torch = game.floor.items(*BESIDE).find &.kind.torch?
      expect(torch.try &.lit?).to be_true
    end

    it "leaves nothing on the square when it carried nothing" do
      game, _ = holding

      kill game

      expect(game.floor.items(*BESIDE).empty?).to be_true
    end

    it "takes what it carried off it" do
      game, creature = holding [Item.new(Kind::Dagger)]

      kill game

      expect(creature.carrying.empty?).to be_true
    end

    it "lets the character pick it up" do
      game, _ = holding [Item.new(Kind::ShortSword)]

      kill game
      game.step Direction::North
      taken = game.pick_up_all

      expect(taken).to eq 1
      expect(game.player.inventory.entries.map &.[1].kind).to contain Kind::ShortSword
    end

    it "lets the character pick up the gold it was carrying" do
      game, _ = holding [Item.new(Kind::Gold, count: 17)]

      kill game
      game.step Direction::North
      game.pick_up_all

      expect(game.player.gold).to eq 17
    end
  end

  describe "a light it is carrying" do
    it "throws light while it is alive" do
      lit, _ = holding [Item.new(Kind::Torch, lit: true)]
      dark, _ = holding [Item.new(Kind::Torch)]

      expect(lit.lights.size).to eq 1
      expect(dark.lights.empty?).to be_true
    end

    it "lights the square it is standing on" do
      game, _ = holding [Item.new(Kind::Torch, lit: true)]
      game.floor.ambient = 0

      expect(game.sight.light(*BESIDE)).to be > 0
    end

    it "goes on lighting the square after it dies" do
      game, _ = holding [Item.new(Kind::Torch, lit: true)]
      game.floor.ambient = 0

      kill game

      expect(game.lights.size).to eq 1
      expect(game.sight.light(*BESIDE)).to be > 0
    end
  end

  describe "Game#equip" do
    # Each creature draws on a stream named by where it stands, so the order
    # they are walked in says nothing about what they get.
    it "gives each creature the same loot from the same seed" do
      first = Game.start Rng.new(SEED)
      second = Game.start Rng.new(SEED)

      first.floor.each_monster do |column, row, creature|
        other = second.floor.monster column, row
        expect(other.try &.carrying).to eq creature.carrying
      end
    end

    it "gives a creature on another square something else" do
      floor = Floor.parse "room", ROOM
      moved = Floor.parse "room", ROOM
      moved.walk BESIDE, {1, 1}

      [floor, moved].each do |held|
        game = Game.new World.new(SEED, {held.id => held}),
          Player.new(held.id, *Game.entrance(held))
        game.equip Rng.new(SEED)
      end

      here = floor.monster(*BESIDE).try &.carrying
      there = moved.monster(1, 1).try &.carrying

      expect(here).not_to eq there
    end

    it "gives every creature on the shipped floor a draw it could make" do
      game = Game.start Rng.new(SEED)

      game.floor.each_monster do |_column, _row, creature|
        allowed = Roguelike::Loot.kinds creature.species

        creature.carrying.each do |item|
          expect(allowed.includes? item.kind).to be_true
        end
      end
    end
  end

  describe "serialization" do
    it "carries what a monster holds through" do
      game, _ = holding [Item.new(Kind::Torch, lit: true), Item.new(Kind::Gold, count: 9)]

      again = Game.from_json game.to_json
      held = again.floor.monster(*BESIDE).try &.carrying

      expect(held.try &.size).to eq 2
      expect(held.try &.any? &.lit?).to be_true
    end
  end
end
