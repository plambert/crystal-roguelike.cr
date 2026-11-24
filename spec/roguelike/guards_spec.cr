require "../spec_helper"

Spectator.describe "golems guarding their posts" do
  alias Awareness = Roguelike::Awareness
  alias Creature = Roguelike::Kind
  alias Direction = Roguelike::Direction
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Terrain = Roguelike::Terrain
  alias World = Roguelike::World

  SEED = 20261124_u64

  # A long lit corridor. The character starts at its west end.
  CORRIDOR = [
    "#" * 40,
    "#<" + "." * 37 + "#",
    "#" * 40,
  ]

  # Two rooms joined by one shut door at 6,2.
  ROOMS = [
    "#############",
    "#.....#.....#",
    "#.<...+.....#",
    "#.....#.....#",
    "#############",
  ]

  DOOR = {6, 2}

  # A corridor with a bend. A creature in the north arm has rock on the
  # straight line to a character in the room to the south-west.
  BEND = [
    "#######",
    "###.###",
    "###.###",
    "#.....#",
    "#<....#",
    "#######",
  ]

  # A game on *map* with a creature of *kind* at *at* and the character at
  # *hero*.
  #
  # The character is hard to kill, walks a turn a step, and carries twenty
  # rocks to throw.
  def guarded(map : Array(String), kind : Creature, at : {Int32, Int32},
              hero : {Int32, Int32}, hit_points : Int32? = nil) : {Game, Monster}
    floor = Playing.daylight Floor.parse("guarded", map)
    creature = Monster.new kind, at[0], at[1], "guard",
      hit_points: hit_points, max_hit_points: hit_points
    floor.place creature

    player = Playing.dressed Player.new(floor.id, hero[0], hero[1], hit_points: 5000)
    player.inventory.add Item.new(ItemKind::Rock, count: 20)
    {Game.new(World.new(SEED, {floor.id => floor}), player), creature}
  end

  def awareness(game : Game, creature : Monster) : Awareness
    game.floor.awareness creature
  end

  def rocks(game : Game) : Char
    game.player.inventory.each { |letter, item| return letter if item.kind.rock? }
    raise "the character carries no rocks"
  end

  def walk(game : Game, direction : Direction, steps : Int32) : Nil
    steps.times { game.step direction }
  end

  # Tells the band *creature* belongs to the whole floor and where the
  # character stands, and sets it hunting.
  def hunting(game : Game, creature : Monster) : Nil
    band = game.floor.band(creature.band) || raise "the floor has lost the band"
    known = band.knowledge game.floor.id
    game.floor.each { |column, row, _tile| known.see game.floor, column, row }
    known.saw Knowledge::PLAYER, game.player.x, game.player.y, game.turn
    band.awareness = Awareness::Hunting
  end

  describe "a golem's facts" do
    it "paths, batters doors, guards and does not heal" do
      {Creature::StoneGolem, Creature::IronGolem}.each do |kind|
        expect(kind.paths?).to be_true
        expect(kind.batters?).to be_true
        expect(kind.guards?).to be_true
        expect(kind.heals?).to be_false
        expect(kind.leash).to eq Roguelike::Kinds::LEASH
      end
    end

    it "is slower than a slime" do
      expect(Creature::StoneGolem.speed).to be < Creature::WhiteSlime.speed
      expect(Creature::IronGolem.speed).to be < Creature::StoneGolem.speed
    end

    it "gives only the iron golem a weakness" do
      expect(Creature::IronGolem.weakness).to eq Roguelike::Effect::Strike
      Creature.values.each do |kind|
        expect(kind.weakness).to be_nil unless kind.iron_golem?
      end
    end

    it "takes the square it was placed on as its post" do
      golem = Monster.new Creature::StoneGolem, 4, 7, "guard"
      orc = Monster.new Creature::Orc, 4, 7, "band"

      expect(golem.home).to eq({4, 7})
      expect(golem.home?).to be_true
      expect(orc.home).to be_nil
    end
  end

  describe "waking" do
    it "sleeps while the character walks up to two squares off" do
      game, golem = guarded CORRIDOR, Creature::StoneGolem, {12, 1}, {1, 1}

      walk game, Direction::East, 9

      expect(game.player.x).to eq 10
      expect(awareness game, golem).to eq Awareness::Asleep
    end

    it "wakes when the character steps beside it" do
      game, golem = guarded CORRIDOR, Creature::StoneGolem, {12, 1}, {1, 1}

      walk game, Direction::East, 10

      expect(awareness game, golem).to eq Awareness::Hunting
      expect(game.log.lines).to contain "The stone golem notices you."
    end

    it "wakes when the character steps beside it on the diagonal" do
      game, golem = guarded ROOMS, Creature::StoneGolem, {4, 1}, {2, 3}

      game.step Direction::NorthEast

      expect(awareness game, golem).to eq Awareness::Hunting
    end

    it "sleeps through a rock landing beside it" do
      game, golem = guarded ROOMS, Creature::StoneGolem, {4, 1}, {1, 3}

      game.throw rocks(game), {5, 2}

      expect(awareness game, golem).to eq Awareness::Asleep
    end
  end

  describe "a golem woken by a shot" do
    it "launches itself at the character" do
      game, golem = guarded CORRIDOR, Creature::StoneGolem, {9, 1}, {1, 1}

      game.throw rocks(game), golem.at

      expect(awareness(game, golem).fighting?).to be_true
      expect(game.log.lines).to contain "The stone golem launches itself at you with surprising speed."
      expect(game.log.lines).not_to contain "The stone golem notices you."
      expect(golem.pace.surge).to eq Game::LAUNCH_SURGE
      expect(golem.pace.speed).to be > 200
    end

    # At its own pace it walks a square in about two turns.
    it "covers five squares in three turns" do
      game, golem = guarded CORRIDOR, Creature::StoneGolem, {9, 1}, {1, 1}

      game.throw rocks(game), golem.at
      2.times { game.wait }

      expect(golem.x).to be <= 4
    end

    it "slows to its own pace once the surge is spent" do
      game, golem = guarded CORRIDOR, Creature::StoneGolem, {9, 1}, {1, 1}

      game.throw rocks(game), golem.at
      (Game::LAUNCH_TICKS + 1).times { game.wait }

      expect(golem.pace.surge).to eq 0
      expect(golem.pace.speed).to eq Creature::StoneGolem.speed
    end

    it "does not launch when struck in melee" do
      game, golem = guarded CORRIDOR, Creature::StoneGolem, {3, 1}, {1, 1}

      game.attack golem

      expect(awareness game, golem).to eq Awareness::Hunting
      expect(golem.pace.surge).to eq 0
    end
  end

  describe "the leash" do
    it "follows the character no further than the leash and walks home" do
      game, golem = guarded CORRIDOR, Creature::StoneGolem, {30, 1}, {29, 1}
      home = golem.home || raise "the golem has no post"
      game.wait
      expect(awareness game, golem).to eq Awareness::Hunting

      farthest = golem.x
      turned = false
      26.times do
        game.step Direction::West
        farthest = Math.min farthest, golem.x
        turned ||= awareness(game, golem).returning?
      end

      expect(turned).to be_true
      expect(farthest).to be >= home[0] - Roguelike::Kinds::LEASH - 1
      expect(golem.x).to be > home[0] - Roguelike::Kinds::LEASH
    end

    it "pays a shot no heed on the way home" do
      game, golem = guarded CORRIDOR, Creature::StoneGolem, {30, 1}, {29, 1}
      game.wait
      26.times do
        break if awareness(game, golem).returning?

        game.step Direction::West
      end

      game.throw rocks(game), golem.at

      expect(awareness game, golem).to eq Awareness::Returning
      expect(golem.pace.surge).to eq 0
    end

    it "sleeps once it is home, as hurt as it came back" do
      game, golem = guarded CORRIDOR, Creature::StoneGolem, {30, 1}, {29, 1}, hit_points: 40
      game.wait
      golem.hurt 10
      26.times do
        break if awareness(game, golem).returning?

        game.step Direction::West
      end
      60.times { game.wait }

      expect(golem.home?).to be_true
      expect(awareness game, golem).to eq Awareness::Asleep
      expect(golem.hit_points).to eq 30

      100.times { game.wait }

      expect(golem.hit_points).to eq 30
    end

    it "lets a character in heavy armor get away" do
      game, golem = guarded CORRIDOR, Creature::IronGolem, {30, 1}, {29, 1}
      mail = Item.new ItemKind::ChainMail
      letter = game.player.inventory.add(mail) || raise "pack full"
      game.player.equipment.put Roguelike::Slot::Body, letter
      game.wait

      start = game.player.hit_points
      20.times { game.step Direction::West }

      expect(Roguelike::Pursuit.gap(golem.at, game.player.at)).to be > 3
      expect(game.player.hit_points).to be >= start - 30
    end
  end

  describe "a shut door" do
    it "breaks down under two to four blows" do
      game, golem = guarded ROOMS, Creature::StoneGolem, {7, 2}, {2, 2}
      hunting game, golem

      blows = 0
      30.times do
        break if game.floor.terrain(*DOOR).broken_door?

        before = game.log.lines.size
        game.wait
        blows += game.log.lines[before..].count &.includes?("the door")
      end

      expect(game.floor.terrain(*DOOR).broken_door?).to be_true
      expect(game.log.lines).to contain "The door breaks!"
      expect(blows + 1).to be >= 2
      expect(blows + 1).to be <= 4
    end
  end

  describe "a wand of striking" do
    # Zaps a wand of striking at *kind* twenty times. Answers how many bolts
    # hit and the damage of each.
    def zapped(kind : Creature) : {Int32, Array(Int32)}
      game, golem = guarded CORRIDOR, kind, {6, 1}, {1, 1}, hit_points: 10_000
      wand = game.player.inventory.add(Item.new ItemKind::StrikingWand, charges: 40) || raise "pack full"
      hit = 0
      damage = [] of Int32
      20.times do
        before = game.log.lines.size
        game.zap wand, golem.at
        game.log.lines[before..].each do |line|
          found = /The bolt hits the .* for (\d+)\./.match line
          next unless found

          hit += 1
          damage << found[1].to_i
        end
      end

      {hit, damage}
    end

    it "hits an iron golem far more often and far harder" do
      iron_hits, iron = zapped Creature::IronGolem
      stone_hits, stone = zapped Creature::StoneGolem

      expect(iron_hits).to be >= 10
      expect(stone_hits).to be <= 8
      expect(iron.min).to be >= 6
      expect(stone.max? || 0).to be <= 8
    end
  end

  describe "a slime" do
    it "waits where a corner blocks its line to the character" do
      game, slime = guarded BEND, Creature::WhiteSlime, {3, 1}, {1, 4}
      hunting game, slime

      5.times { game.wait }

      expect(slime.at).to eq({3, 1})
    end
  end

  describe "where a golem is placed" do
    # Floors 8 and 10 of three runs, each cut into chambers and passages.
    def floors(& : Floor, Roguelike::Chambers ->) : Nil
      3.times do |run|
        {8, 10}.each do |depth|
          ground = Roguelike::Generator.floor Roguelike::Rng.new(SEED + run), World.id(depth), depth
          known = Knowledge.new ground.id
          ground.each { |column, row, tile| known.touch ground, column, row unless tile.terrain.rock? }
          yield ground, Roguelike::Chambers.of(known, ground.columns, ground.rows)
        end
      end
    end

    it "stands on its post in a doorway or a corridor rather than in a room" do
      count = 0
      floors do |ground, cut|
        ground.each_monster do |column, row, creature|
          next unless creature.kind.guards?

          count += 1
          expect(cut.at(column, row)).to be_nil
          expect(creature.home?).to be_true
        end
      end

      expect(count).to be > 50
    end
  end

  describe "an old save" do
    it "gives a golem with no post the square it stands on" do
      golem = Monster.new Creature::IronGolem, 3, 4, "guard"
      written = JSON.parse(golem.to_json).as_h
      written.delete "home"
      loaded = Monster.from_json written.to_json

      expect(loaded.home).to eq({3, 4})
    end

    it "writes no post for a creature that guards nothing" do
      orc = Monster.new Creature::Orc, 3, 4, "band"

      expect(JSON.parse(orc.to_json).as_h.has_key?("home")).to be_false
    end

    it "loads a band walking home" do
      band = Roguelike::Band.new "guard", awareness: Awareness::Returning

      expect(Roguelike::Band.from_json(band.to_json).awareness).to eq Awareness::Returning
    end
  end
end
