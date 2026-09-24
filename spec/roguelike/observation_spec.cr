require "../spec_helper"

Spectator.describe Roguelike::Observation do
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Lore = Roguelike::Lore
  alias Monster = Roguelike::Monster
  alias Observation = Roguelike::Observation
  alias Player = Roguelike::Player
  alias Regard = Roguelike::Regard
  alias Rng = Roguelike::Rng
  alias Size = Roguelike::Size
  alias Species = Roguelike::Species
  alias Terrain = Roguelike::Terrain
  alias World = Roguelike::World

  # The seed every example here runs on. A failure names a run somebody can
  # start.
  SEED = 20260924_u64

  # A game on *lines*, with the character on the up staircase.
  #
  # *light* lights every square, for an example that is not about light.
  # *items* go in the pack and *creatures* on the floor before the run is
  # built, so that both are enrolled and have an id.
  def played(lines : Array(String),
             light : Bool = true,
             items : Array(Item) = [] of Item,
             creatures : Array(Monster) = [] of Monster) : Game
    floor = Floor.parse "room", lines
    floor.ambient = 1 if light
    creatures.each { |creature| floor.place creature }

    player = Player.new floor.id, *Game.entrance(floor)
    items.each { |item| player.inventory.add item }

    Game.new World.new(SEED, {floor.id => floor}), player,
      lore: Lore.roll(Rng.new SEED)
  end

  # Two rooms with a wall between them. The character starts in the left one.
  ROOMS = [
    "#########",
    "#...#...#",
    "#.<.#...#",
    "#...#...#",
    "#########",
  ]

  describe "a creature the character cannot see" do
    it "is left out for one behind a wall" do
      hidden = Monster.new Species::Goblin, 6, 2, "band-one"
      game = played ROOMS, creatures: [hidden]

      expect(Observation.of(game).monsters).to be_empty
    end

    it "is kept for one in the same room" do
      near = Monster.new Species::Goblin, 1, 1, "band-one"
      game = played ROOMS, creatures: [near]
      found = Observation.of(game).monsters

      expect(found.size).to eq 1
      expect(found.first.id).to eq near.id
      expect(found.first.pos).to eq({1, 1})
    end

    it "writes nothing about one behind a wall into the JSON" do
      hidden = Monster.new Species::Slime, 6, 2, "band-one"
      game = played ROOMS, creatures: [hidden]

      expect(Observation.of(game).to_json.includes? "slime").to be_false
    end
  end

  describe "a creature the character can see" do
    it "gives its species, how hurt it is and what it is doing" do
      near = Monster.new Species::Goblin, 1, 1, "band-one"
      game = played ROOMS, creatures: [near]
      found = Observation.of(game).monsters.first

      expect(found.regard).to eq Regard::Everything
      expect(found.species).to eq Species::Goblin
      expect(found.name).to eq "goblin"
      expect(found.condition).to eq Observation::Health::Unhurt
      expect(found.awareness).to eq Roguelike::Awareness::Asleep
    end

    it "gives a condition rather than hit points" do
      near = Monster.new Species::Goblin, 1, 1, "band-one"
      near.hurt near.max_hit_points - 1
      game = played ROOMS, creatures: [near]
      found = Observation.of(game).monsters.first

      expect(found.condition).to eq Observation::Health::NearDeath
      expect(found.to_json.includes? "hit_points").to be_false
    end
  end

  # A dark corridor with a lit torch at the east end.
  #
  # The torch throws six squares, so the east end is lit and the west end is
  # dark. A creature standing in the dark part of it shows against the light
  # behind it and is made out as a shape.
  CORRIDOR = ["#" * 24, "#<" + "." * 21 + "#", "#" * 24]

  # Where the torch lies, and where the creature stands.
  TORCH_LIT = {20, 1}
  SHAPE_AT  = {7, 1}

  # A game in the dark corridor with one creature standing in the dark.
  def corridor(species : Species = Species::Goblin) : {Game, Monster}
    creature = Monster.new species, SHAPE_AT[0], SHAPE_AT[1], "band-one"
    game = played CORRIDOR, light: false, creatures: [creature]
    game.floor.drop TORCH_LIT[0], TORCH_LIT[1],
      Item.new(Kind::Torch, lit: true)

    {game, creature}
  end

  describe "a creature made out only as a shape" do
    it "gives its size and not its species" do
      game, creature = corridor
      found = Observation.of(game).monsters.first

      expect(found.id).to eq creature.id
      expect(found.regard).to eq Regard::Shape
      expect(found.size).to eq Size::Small
      expect(found.species).to be_nil
      expect(found.name).to eq "a small shape"
    end

    it "gives no condition and nothing about what it is doing" do
      game, _ = corridor
      found = Observation.of(game).monsters.first

      expect(found.condition).to be_nil
      expect(found.awareness).to be_nil
    end

    it "writes nothing about its species into the JSON" do
      game, _ = corridor Species::Slime

      expect(Observation.of(game).to_json.includes? "slime").to be_false
    end

    it "gives a bigger creature a bigger shape" do
      game, _ = corridor Species::Slime
      found = Observation.of(game).monsters.first

      expect(found.size).to eq Size::Medium
    end
  end

  describe "an unidentified item in the pack" do
    it "gives its appearance and not its kind" do
      game = played ROOMS, items: [Item.new(Kind::HealingPotion)]
      found = Observation.of(game).inventory.first

      expect(game.lore.appearance Kind::HealingPotion).not_to be_nil
      expect(found.identified?).to be_false
      expect(found.kind).to be_nil
      expect(found.appearance).to eq game.lore.appearance(Kind::HealingPotion)
      expect(found.item_class).to eq Roguelike::ItemClass::Potion
    end

    it "writes nothing about its kind into the JSON" do
      game = played ROOMS, items: [Item.new(Kind::HealingPotion)]

      expect(Observation.of(game).to_json.includes? "healing").to be_false
    end

    it "gives its kind once the character has found it out" do
      game = played ROOMS, items: [Item.new(Kind::HealingPotion)]
      game.lore.learn Kind::HealingPotion
      found = Observation.of(game).inventory.first

      expect(found.identified?).to be_true
      expect(found.kind).to eq Kind::HealingPotion
      expect(found.appearance).to be_nil
    end
  end

  describe "an item in the pack" do
    it "gives the letter it is under and the slot holding it" do
      game = played ROOMS, items: [Item.new(Kind::ShortSword)]
      game.wield 'a'
      found = Observation.of(game).inventory.first

      expect(found.letter).to eq "a"
      expect(found.slot).to eq Roguelike::Slot::Melee
      expect(found.kind).to eq Kind::ShortSword
    end

    it "gives its blessing once the character knows it" do
      item = Item.new Kind::ShortSword, blessing: Roguelike::Blessing::Cursed
      game = played ROOMS, items: [item]

      expect(Observation.of(game).inventory.first.blessing).to be_nil

      item.reveal_blessing
      expect(Observation.of(game).inventory.first.blessing)
        .to eq Roguelike::Blessing::Cursed
    end

    it "counts everything under one letter" do
      game = played ROOMS, items: [Item.new(Kind::Arrow, count: 3)]
      found = Observation.of(game).inventory.first

      expect(found.count).to eq 3
    end
  end

  # One long lit room. The far end is past `Regards::READING`, so an item
  # lying there is made out as its kind and no more.
  HALL = ["#" * 20, "#<" + "." * 17 + "#", "#" * 20]

  # Where an item lies too far off to read.
  FAR = {18, 1}

  describe "an item lying in view" do
    it "gives its kind and not its appearance from across the room" do
      game = played HALL
      game.floor.drop FAR[0], FAR[1], Item.new(Kind::HealingPotion)
      found = Observation.of(game).items.first

      expect(found.pos).to eq FAR
      expect(found.regard).to eq Regard::Kind
      expect(found.kind).to be_nil
      expect(found.appearance).to be_nil
      expect(found.name).to eq "a potion"
    end

    it "gives its appearance from a square the character can read it on" do
      game = played HALL
      game.floor.drop 3, 1, Item.new(Kind::HealingPotion)
      found = Observation.of(game).items.first

      expect(found.regard).to eq Regard::Everything
      expect(found.appearance).to eq game.lore.appearance(Kind::HealingPotion)
    end

    it "names a thing that is what it looks like from any distance" do
      game = played HALL
      game.floor.drop FAR[0], FAR[1], Item.new(Kind::Spear)
      found = Observation.of(game).items.first

      expect(found.regard).to eq Regard::Kind
      expect(found.kind).to eq Kind::Spear
      expect(found.enchantment).to be_nil
      expect(found.name).to eq "a spear"
    end

    it "is left out for a square the character cannot see" do
      game = played ROOMS
      game.floor.drop 6, 2, Item.new(Kind::HealingPotion)

      expect(Observation.of(game).items).to be_empty
    end
  end

  describe "an item the character remembers" do
    # A torch throws six squares. Walking eight squares past a potion puts it
    # in the dark, so it leaves sight and stays on the map.
    it "gives the turn it was last seen on" do
      game = played CORRIDOR, light: false, items: [Item.new(Kind::Torch, lit: true)]
      game.floor.drop 3, 1, Item.new(Kind::HealingPotion)

      seen_on = 0
      12.times do
        game.step Direction::East
        game.look
        found = Observation.of game
        seen_on = game.turn if found.items.any? { |item| item.pos == {3, 1} }
      end

      found = Observation.of(game)
      recalled = found.remembered_items.find { |item| item.pos == {3, 1} }

      expect(seen_on).to be > 0
      expect(found.items.map &.pos).not_to contain({3, 1})
      expect(recalled).not_to be_nil
      expect(recalled.try &.last_seen_turn).to eq seen_on
    end

    it "is left out while it is in view" do
      game = played HALL
      game.floor.drop 3, 1, Item.new(Kind::HealingPotion)
      game.look
      found = Observation.of game

      expect(found.items.size).to eq 1
      expect(found.remembered_items).to be_empty
    end
  end

  # A floor drawn only with terrains the map pane draws with the same
  # character the game writes them with.
  #
  # The pane draws all three rocks as `#` and both floors as `.`, and tells
  # them apart by colour. The observation keeps the terrain, so a floor with
  # sandstone, shale or dirt in it would differ from the pane by design.
  MAZE = [
    "##########",
    "#.<..#...#",
    "#....+...#",
    "#...##...#",
    "#........#",
    "##########",
  ]

  # The pane over *game*, drawn at the size of the floor.
  #
  # `Headless::Session#rows` trims the blanks off the end of every row, so
  # the rows the observation carries are trimmed the same way before they are
  # compared.
  def drawn(game : Game) : Array(String)
    pane = Roguelike::Ui::MapPane.new game.floor
    pane.sight = game.sight
    pane.knowledge = game.knowledge

    session = Headless.open pane.grid, game.floor.columns, game.floor.rows
    session.render
    session.rows
  end

  describe "the remembered map" do
    it "matches what the map pane draws before anything has moved" do
      game = played MAZE
      game.look
      found = Observation.of game

      expect(drawn(game).first).to eq "######"
      expect(found.map.rows.map &.rstrip).to eq drawn(game)
    end

    it "matches what the map pane draws after the character has walked" do
      game = played MAZE
      game.look
      3.times do
        game.step Direction::South
        game.look
      end
      found = Observation.of game

      expect(found.map.rows.map &.rstrip).to eq drawn(game)
    end

    it "leaves a square nobody has seen unknown" do
      game = played MAZE
      game.look
      found = Observation.of game

      expect(found.map.rows[2][7]).to eq Observation::UNKNOWN
      expect(found.map.rows[1][2]).to eq Terrain::StairsUp.mark
    end

    it "is the size of the floor" do
      game = played MAZE
      game.look
      found = Observation.of(game).map

      expect(found.width).to eq game.floor.columns
      expect(found.height).to eq game.floor.rows
      expect(found.rows.size).to eq game.floor.rows
      expect(found.rows.all? { |row| row.size == game.floor.columns }).to be_true
    end

    it "keeps a terrain the pane draws as another" do
      game = played ["###", "#,#", "#<#", "###"]
      game.look
      found = Observation.of(game).map

      expect(found.rows[1][1]).to eq Terrain::DirtFloor.mark
      expect(drawn(game)[1][1]).to eq '.'
    end
  end

  describe "the visible grid" do
    it "marks the squares the map pane draws live" do
      game = played MAZE
      found = Observation.of game
      pane = Roguelike::Ui::MapPane.new game.floor
      pane.sight = game.sight

      game.floor.rows.times do |row|
        game.floor.columns.times do |column|
          wanted = pane.seen?(column, row) ? Observation::SHOWN : Observation::HIDDEN
          expect(found.visible.rows[row][column]).to eq wanted
        end
      end
    end

    it "marks nothing but the character's own square while they are blind" do
      game = played MAZE
      game.player.blind 5
      found = Observation.of(game).visible

      lit = found.rows.sum &.count(Observation::SHOWN)
      expect(lit).to eq 1
      expect(found.rows[game.player.y][game.player.x]).to eq Observation::SHOWN
    end
  end

  describe "the player block" do
    it "gives what the sidebar gives" do
      game = played ROOMS
      found = Observation.of(game).player

      expect(found.pos).to eq game.player.at
      expect(found.hit_points).to eq game.player.hit_points
      expect(found.max_hit_points).to eq game.player.max_hit_points
      expect(found.level).to eq game.player.level
      expect(found.experience).to eq game.player.experience
      expect(found.armour_class).to eq game.player.armour_class
      expect(found.gold).to eq game.player.gold
    end

    it "names a status without saying how long it lasts" do
      game = played ROOMS
      game.player.blind 5
      game.player.pace.hurry 3
      found = Observation.of(game).player

      expect(found.statuses).to contain Observation::Status::Blind
      expect(found.statuses).to contain Observation::Status::Hurried
      expect(found.statuses).not_to contain Observation::Status::Dragging
      expect(Observation.of(game).to_json.includes? "turns_left").to be_false
    end
  end

  describe ".of" do
    # A snapshot that wrote to `Knowledge` would give a headless run and a
    # replay of the same actions two different hashes.
    it "leaves the run as it found it" do
      game = played MAZE
      game.look
      before = game.fingerprint

      Observation.of game

      expect(game.fingerprint).to eq before
    end

    # `Game#knowledge` puts an empty `Knowledge` in the character's table for
    # a floor they have not looked at, and the save holds it. The snapshot
    # reads `Player#knowledge?`, which stores nothing.
    it "puts no knowledge in a run nobody has looked at" do
      game = played MAZE
      before = game.fingerprint

      Observation.of game

      expect(game.fingerprint).to eq before
      expect(game.player.knowledge? game.floor.id).to be_nil
    end

    # `Game#look` is the one way anything gets into `Knowledge`. A caller
    # that does not call it reads a map one turn behind what the character
    # can see. The visible grid is not behind, because it comes from
    # `Game#sight`.
    it "takes a field of view the caller has already worked out" do
      game = played MAZE
      seen = game.look

      expect(Observation.of(game, seen).to_json).to eq Observation.of(game).to_json
    end

    it "reads the map the caller has looked at and no more" do
      game = played MAZE
      game.look
      3.times { game.step Direction::South }

      stale = Observation.of game
      game.look
      fresh = Observation.of game

      expect(stale.map.rows).not_to eq fresh.map.rows
      expect(stale.visible.rows).to eq fresh.visible.rows
    end
  end

  describe "#to_json" do
    it "reads back what it wrote" do
      near = Monster.new Species::Goblin, 1, 1, "band-one"
      game = played ROOMS, items: [Item.new(Kind::HealingPotion)],
        creatures: [near]
      game.floor.drop 1, 3, Item.new(Kind::Spear)
      found = Observation.of game

      expect(Observation.from_json(found.to_json).to_json).to eq found.to_json
    end

    it "gives the turn and the floor" do
      game = played ROOMS
      found = Observation.of game

      expect(found.turn).to eq game.turn
      expect(found.floor).to eq game.floor.id
    end
  end
end
