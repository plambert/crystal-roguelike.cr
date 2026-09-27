require "../spec_helper"

Spectator.describe "holding a field of view" do
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Rng = Roguelike::Rng
  alias Species = Roguelike::Species
  alias Terrain = Roguelike::Terrain
  alias World = Roguelike::World

  SEED = 20260927_u64

  # Two rooms with a shut door between them.
  PLAN = [
    "###########",
    "#....#....#",
    "#.<..+....#",
    "#....#....#",
    "###########",
  ]

  # A run on `PLAN`, dark unless *light* says otherwise.
  def played(light : Bool = false, items : Array(Item) = [] of Item) : Game
    floor = Floor.parse "rooms", PLAN
    floor.ambient = 1 if light

    player = Player.new floor.id, *Game.entrance(floor)
    items.each { |item| player.inventory.add item }

    Game.new World.new(SEED, {floor.id => floor}), player
  end

  # A lit torch, which makes the character a light source.
  def torch : Item
    Item.new Kind::Torch, lit: true
  end

  describe "asking twice" do
    it "gives the answer it gave before" do
      game = played light: true

      expect(game.sight.same? game.sight).to be_true
    end

    it "gives an answer that says the same thing" do
      game = played light: true
      before = game.sight.to_map game.floor

      expect(game.sight.to_map game.floor).to eq before
    end
  end

  describe "what makes it work the answer out again" do
    it "is the character moving" do
      game = played light: true
      held = game.sight
      game.step Direction::East

      expect(game.sight.same? held).to be_false
      expect(game.sight.origin).to eq game.player.at
    end

    it "is a door opening" do
      game = played light: true
      held = game.sight
      game.floor.set 5, 2, Terrain::OpenDoor

      expect(game.sight.same? held).to be_false
      expect(game.sight.includes? 7, 2).to be_true
    end

    it "is the ambient level changing" do
      game = played
      expect(game.sight.lit? 2, 2).to be_false

      game.floor.ambient = 1
      expect(game.sight.lit? 2, 2).to be_true
    end

    it "is a square starting to glow" do
      game = played
      held = game.sight
      game.floor.set_glow 2, 2, 4

      expect(game.sight.same? held).to be_false
      expect(game.sight.lit? 2, 2).to be_true
    end

    it "is a flame the character carries being lit" do
      held = Item.new Kind::Torch
      game = played items: [held]
      expect(game.sight.lit? game.player.x, game.player.y).to be_false

      held.kindle
      expect(game.sight.lit? game.player.x, game.player.y).to be_true
    end

    it "is a flame the character carries going out" do
      held = torch
      game = played items: [held]
      expect(game.sight.lit? game.player.x, game.player.y).to be_true

      held.douse
      expect(game.sight.lit? game.player.x, game.player.y).to be_false
    end

    it "is a flame lying on the floor being taken away" do
      game = played
      game.floor.drop 3, 2, torch
      expect(game.sight.lit? 3, 2).to be_true

      game.floor.clear_items 3, 2
      expect(game.sight.lit? 3, 2).to be_false
    end

    # The flame goes on lighting the square it left, because it is still
    # one square away. What changes is how much light that square has.
    it "is a creature carrying a flame walking" do
      game = played
      creature = Monster.new Species::Goblin, 6, 2, "band-one"
      creature.carrying << torch
      game.floor.place creature
      held = game.sight
      beside = game.sight.light 6, 2

      game.floor.walk({6, 2}, {8, 2})
      expect(game.sight.same? held).to be_false
      expect(game.sight.light 6, 2).to be < beside
      expect(game.sight.light 8, 2).to eq beside
    end
  end

  describe "a run read back" do
    # The answer is worked out from the run rather than stored beside it, so
    # a save holds none of it and neither does a fingerprint.
    it "works it out afresh and agrees with the run it came from" do
      game = played light: true
      before = game.sight.to_map game.floor

      again = Game.from_json game.to_json
      expect(again.sight.to_map again.floor).to eq before
      expect(again.fingerprint).to eq game.fingerprint
    end

    it "writes nothing about it into the JSON" do
      game = played light: true
      game.sight

      expect(game.to_json.includes? "seen_from").to be_false
      expect(game.to_json.includes? "version").to be_false
    end
  end

  describe "a character who cannot see" do
    it "holds the answer the same way" do
      game = played light: true
      game.player.blind 5

      expect(game.sight.same? game.sight).to be_true
      expect(game.sight.size).to eq 1
    end
  end
end
