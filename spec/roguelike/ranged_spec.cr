require "../spec_helper"

Spectator.describe "monsters that shoot" do
  alias Action = Roguelike::Pursuit::Action
  alias Awareness = Roguelike::Awareness
  alias Creature = Roguelike::Kind
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Knowledge = Roguelike::Knowledge
  alias Loot = Roguelike::Loot
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Pursuit = Roguelike::Pursuit
  alias Rng = Roguelike::Rng
  alias Snapshot = Roguelike::Pursuit::Snapshot
  alias World = Roguelike::World

  SEED = 20260930_u64

  # A long lit hall. The character stands at the west end.
  HALL = [
    "##############",
    "#............#",
    "#............#",
    "#............#",
    "##############",
  ]

  # Where the character stands.
  HERE = {1, 2}

  # Enough hit points that no spec here is about dying.
  PLENTY = 5_000

  # A game on *lines* with the character at *here* and *creatures* awake
  # and hunting them.
  #
  # *lit* false leaves the floor dark, so the character sees nothing past
  # their own square.
  def hall(creatures : Array(Monster), lines : Array(String) = HALL,
           here : {Int32, Int32} = HERE, lit : Bool = true) : Game
    floor = Floor.parse "hall", lines
    floor = Playing.daylight floor if lit

    creatures.each { |creature| floor.place creature }
    player = Player.new floor.id, *here, hit_points: PLENTY
    game = Game.new World.new(SEED, {floor.id => floor}), player
    creatures.each { |creature| hunting game, creature }
    game
  end

  # Wakes the band *creature* belongs to and tells it the floor and where
  # the character stands.
  def hunting(game : Game, creature : Monster) : Nil
    band = game.floor.band(creature.band) || raise "the floor has lost the band"
    knowledge = band.knowledge game.floor.id
    game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
    knowledge.saw Knowledge::PLAYER, game.player.x, game.player.y, game.turn
    band.awareness = Awareness::Hunting
  end

  # An orc archer at *at* with a bow and *arrows* arrows.
  def archer(at : {Int32, Int32}, arrows : Int32 = 5, band : String = "archers") : Monster
    creature = Monster.new Creature::OrcArcher, at[0], at[1], band, hit_points: PLENTY
    creature.outfit [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: arrows)]
    creature
  end

  # A goblin scout at *at* with a sling and *stones* stones.
  def scout(at : {Int32, Int32}, stones : Int32 = 5) : Monster
    creature = Monster.new Creature::GoblinScout, at[0], at[1], "scouts", hit_points: PLENTY
    creature.outfit [Item.new(Kind::Sling), Item.new(Kind::Stone, count: stones)]
    creature
  end

  # Every shot the last action saw.
  def shots(game : Game) : Array(Event::Shot)
    game.events.compact_map &.as?(Event::Shot)
  end

  # Waits *turns* turns and answers every shot fired at the character.
  def waited(game : Game, turns : Int32) : Array(Event::Shot)
    found = [] of Event::Shot
    turns.times do
      game.events.clear
      game.wait
      found.concat shots(game)
    end
    found
  end

  # How many pieces of *kind* lie on the floor.
  def lying(game : Game, kind : Kind) : Int32
    total = 0
    game.floor.each_pile do |_column, _row, pile|
      pile.each { |item| total += item.count if item.kind == kind }
    end
    total
  end

  # Where *creature* stands now, after the floor has moved it.
  def now(game : Game, creature : Monster) : {Int32, Int32}
    found = nil.as({Int32, Int32}?)
    game.floor.each_monster { |column, row, held| found = {column, row} if held.same? creature }
    found || raise "the creature is off the floor"
  end

  describe "the kinds" do
    it "gives a goblin scout a sling and 1d4+1 stones" do
      expect(Creature::GoblinScout.ranged_weapon).to eq Kind::Sling
      expect(Creature::GoblinScout.quiver.to_s).to eq "1d4+1"
    end

    it "gives an orc archer a bow and 3d6 arrows" do
      expect(Creature::OrcArcher.ranged_weapon).to eq Kind::Bow
      expect(Creature::OrcArcher.quiver.to_s).to eq "3d6"
    end
  end

  describe "what they carry" do
    it "rolls a sling and between two and eight stones for a scout" do
      rng = Rng.new(SEED).derive "scouts"

      200.times do
        carried = Loot.for Creature::GoblinScout, rng, 1
        stones = carried.select(&.kind.stone?)

        expect(carried.count &.kind.sling?).to eq 1
        expect(stones.size).to eq 1
        expect(stones.first.count).to be_between(2, 8).inclusive
      end
    end

    it "rolls a bow and between three and eighteen arrows for an archer" do
      rng = Rng.new(SEED).derive "archers"

      200.times do
        carried = Loot.for Creature::OrcArcher, rng, 4
        arrows = carried.select(&.kind.arrow?)

        expect(carried.count &.kind.bow?).to eq 1
        expect(arrows.first.count).to be_between(3, 18).inclusive
      end
    end

    it "fletches +1 arrows only as deep as the table allows" do
      shallow = Rng.new(SEED).derive "shallow"
      deep = Rng.new(SEED).derive "deep"

      pluses = {1 => 0, 5 => 0}
      1000.times do
        pluses[1] += 1 if Loot.for(Creature::OrcArcher, shallow, 1).any? { |item| item.kind.arrow? && item.enchantment == 1 }
        pluses[5] += 1 if Loot.for(Creature::OrcArcher, deep, 5).any? { |item| item.kind.arrow? && item.enchantment == 1 }
      end

      expect(pluses[1]).to eq 0
      expect(pluses[5]).to be_close 300, 60
    end

    it "leaves what a kind with no ranged weapon carries as it was" do
      rng = Rng.new(SEED).derive "warriors"

      200.times do
        carried = Loot.for Creature::GoblinWarrior, rng, 2
        expect(carried.none? &.kind.item_class.ranged_weapon?).to be_true
        expect(carried.none? &.kind.item_class.ammunition?).to be_true
      end
    end
  end

  describe "deciding" do
    # What a creature at *at* with *reach* decides about a character at
    # *quarry* in the hall, when a shot would get there or not.
    def decide(at : {Int32, Int32}, quarry : {Int32, Int32} = HERE,
               reach : Int32 = 16, clear : Bool = true) : Action
      floor = Playing.daylight Floor.parse("hall", HALL)
      knowledge = Knowledge.new floor.id
      floor.each { |column, row, _tile| knowledge.see floor, column, row }

      Pursuit.decide Snapshot.new(at: at, knowledge: knowledge, quarry: quarry,
        blocked: Set{quarry}, reach: reach, clear: clear)
    end

    it "shoots along a clear line from three to six squares" do
      (3..6).each do |gap|
        action = decide({HERE[0] + gap, HERE[1]})

        expect(action.intent.shoot?).to be_true
        expect(action.target).to eq HERE
      end
    end

    it "walks nearer from farther than six squares" do
      action = decide({HERE[0] + 9, HERE[1]})

      expect(action.intent.step?).to be_true
      expect(action.direction.try &.dx).to eq -1
    end

    it "does not shoot along a line that is not clear" do
      action = decide({HERE[0] + 5, HERE[1]}, clear: false)

      expect(action.intent.shoot?).to be_false
    end

    it "backs away from two squares when it has room" do
      at = {HERE[0] + 2, HERE[1]}
      action = decide(at)
      direction = action.direction || raise "no step"
      stepped = direction.from at[0], at[1]

      expect(action.intent.step?).to be_true
      expect(Pursuit.gap stepped, HERE).to eq 3
    end

    it "swings when it is cornered beside the character" do
      action = decide({12, 2}, quarry: {11, 2})

      expect(action.intent.strike?).to be_true
    end

    it "fights as any other creature does with nothing to shoot" do
      action = decide({HERE[0] + 5, HERE[1]}, reach: 0)

      expect(action.intent.step?).to be_true
    end
  end

  describe "an orc archer" do
    it "shoots from range and stops when it runs out of arrows" do
      creature = archer({7, 2}, arrows: 3)
      game = hall [creature]

      fired = waited game, 40

      expect(fired.size).to eq 3
      expect(creature.ammunition).to be_nil
      expect(creature.ranged_weapon).not_to be_nil
      expect(Pursuit.gap now(game, creature), game.player.at).to eq 1
    end

    it "closes to melee once its arrows are gone" do
      creature = archer({7, 2}, arrows: 1)
      game = hall [creature]

      waited game, 40
      struck = game.log.lines.count &.includes?("The orc archer hits you")
      missed = game.log.lines.count &.includes?("The orc archer misses you")

      expect(struck + missed).to be > 0
    end

    it "leaves every arrow it shot on the floor near the character" do
      creature = archer({7, 2}, arrows: 12)
      game = hall [creature]

      waited game, 60

      expect(lying game, Kind::Arrow).to eq 12
      expect(game.log.lines.any? &.includes?("The arrow misses you.")).to be_true
      game.floor.each_pile do |column, row, pile|
        next unless pile.any? &.kind.arrow?

        expect(Pursuit.gap({column, row}, game.player.at)).to be <= Game::OVERSHOOT
      end
    end

    it "does not shoot through another creature" do
      creature = archer({8, 2})
      blocker = Monster.new Creature::WhiteSlime, 4, 2, "slimes", hit_points: PLENTY
      game = hall [creature]
      game.floor.place blocker

      game.wait

      expect(shots game).to be_empty
    end

    it "does not shoot through a wall" do
      pillar = [
        "##############",
        "#............#",
        "#....#.......#",
        "#............#",
        "##############",
      ]
      creature = archer({8, 2})
      game = hall [creature], pillar

      expect(game.clear_shot? creature, game.player.at, 16).to be_false
      game.wait
      expect(shots game).to be_empty
    end
  end

  describe "a goblin scout" do
    it "backs away from a character two squares off and keeps its distance" do
      creature = scout({3, 2}, stones: 8)
      game = hall [creature]

      6.times do
        game.wait
        expect(Pursuit.gap now(game, creature), game.player.at).to be >= 3
      end
    end
  end

  describe "what the character is told" do
    it "names a shooter they can see and the way the shot came from" do
      game = hall [archer({6, 2}, arrows: 1)]

      game.wait

      expect(game.log.lines.any? &.includes?("The orc archer shoots an arrow at you from the east.")).to be_true
      expect(shots(game).first.shooter).not_to be_nil
    end

    it "calls a shooter they cannot see something" do
      game = hall [archer({6, 2}, arrows: 1)], lit: false

      game.wait

      expect(game.log.lines.any? &.includes?("Something shoots an arrow at you from the east.")).to be_true
      expect(shots(game).first.shooter).to be_nil
    end
  end

  describe "a save file" do
    it "keeps what a creature has left to shoot" do
      creature = archer({8, 2}, arrows: 7)
      game = hall [creature]
      game.enroll

      again = Game.from_json game.to_json
      held = again.floor.monster(8, 2) || raise "the archer is gone"

      expect(held.ammunition.try &.count).to eq 7
      expect(held.shooting_reach).to eq Kind::Bow.reach
      expect(again.to_json).to eq game.to_json
    end

    it "loads a creature saved before it carried anything to shoot" do
      creature = Monster.new Creature::OrcArcher, 8, 2, "archers"
      loaded = Monster.from_json creature.to_json

      expect(loaded.shooting_reach).to eq 0
    end
  end
end
