require "../spec_helper"

Spectator.describe "what a blow costs" do
  alias Costs = Roguelike::Costs
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Kinds = Roguelike::Kinds
  alias Monster = Roguelike::Monster
  alias Pace = Roguelike::Pace
  alias Player = Roguelike::Player
  alias Slot = Roguelike::Slot
  alias Species = Roguelike::Species

  HALL = ["##########",
          "#........#",
          "#..<.....#",
          "#........#",
          "##########"]

  # Enough hit points that nothing in a spec ends the run.
  PLENTY = 100_000

  # A hall with the character holding *weapon*, or nothing, next to a
  # creature of *species* that nothing in a spec kills.
  def duel(weapon : Kind?, species : Species = Species::Slime) : Game
    floor = Roguelike::Floor.parse "hall", HALL.join('\n')
    floor.ambient = 1

    player = Player.new "hall", 3, 2, hit_points: PLENTY
    if weapon
      letter = player.inventory.add Item.new(weapon, blessing_known: true)
      player.equipment.put(Slot::Melee, letter || raise("pack full"))
    end

    game = Game.new Roguelike::World.new(20260930_u64, {"hall" => floor}), player
    game.floor.place Monster.new(species, 4, 2, "band", hit_points: PLENTY)
    game
  end

  def target(game : Game) : Monster
    game.floor.monster(4, 2) || raise "no creature"
  end

  # How many times the character swings in *ticks* ticks.
  def swings_in(game : Game, ticks : Int32) : Int32
    count = 0
    start = game.turn
    while game.turn - start < ticks
      game.attack target(game)
      count += 1
    end
    count
  end

  # How many times the creature on the floor swings at the character while
  # the character waits *ticks* ticks.
  def strikes_in(game : Game, ticks : Int32) : Int32
    target(game).tap do |creature|
      band = game.floor.band(creature.band) || raise("no band")
      band.awareness = Roguelike::Awareness::Hunting
      knowledge = band.knowledge game.floor.id
      game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
      knowledge.saw Roguelike::Knowledge::PLAYER, 3, 2, game.turn
    end

    start = game.turn
    while game.turn - start < ticks
      game.wait
    end

    game.events.count { |event| event.is_a?(Roguelike::Event::Attack) && event.attacker }
  end

  describe "the table" do
    it "makes a dagger quicker than a short sword and a short sword quicker than a spear" do
      expect(Kind::Dagger.swing).to be < Kind::ShortSword.swing
      expect(Kind::ShortSword.swing).to be < Kind::Spear.swing
    end

    it "keeps a normal turn for a short sword and for throwing" do
      expect(Kind::ShortSword.swing).to eq Costs::TURN
      expect(Kind::Dart.swing).to eq Costs::TURN
      expect(Kind::Rock.swing).to eq Costs::TURN
      expect(Kind::Sling.swing).to eq Costs::TURN
    end

    it "makes a bow slower than a sling" do
      expect(Kind::Bow.swing).to be > Kind::Sling.swing
    end

    it "costs bare hands less than a turn" do
      expect(Costs.swing(nil)).to eq 80
    end

    it "swings a wand like a fist" do
      expect(Costs.swing(Item.new(Kind::LightWand))).to eq Costs::BARE
    end

    # A heavier weapon hits harder per blow and less than proportionally
    # harder per unit of energy.
    it "raises damage per energy with damage per blow, by less" do
      melee = [Kind::Dagger, Kind::ShortSword, Kind::LongSword]
      per_blow = melee.map &.damage.average
      per_energy = melee.map { |kind| kind.damage.average * 100 / kind.swing }

      expect(per_energy).to eq per_energy.sort
      expect(per_energy.last / per_energy.first).to be < per_blow.last / per_blow.first
    end

    it "words a cost" do
      expect(Costs.pace_word 75).to eq "quick"
      expect(Costs.pace_word 100).to eq "normal"
      expect(Costs.pace_word 120).to eq "slow"
    end
  end

  describe "the character's swing" do
    it "gives a dagger more swings than a spear over the same ticks" do
      dagger = swings_in duel(Kind::Dagger), 60
      spear = swings_in duel(Kind::Spear), 60

      expect(dagger).to be_within(1).of(80)
      expect(spear).to be_within(1).of(48)
      expect(dagger).to be > spear
    end

    it "gives bare hands a swing every eighty energy" do
      expect(swings_in duel(nil), 100).to be_within(1).of(125)
    end

    it "charges the same on a hit as on a miss" do
      game = duel Kind::LongSword
      hits = 0
      misses = 0

      200.times do
        break if hits >= 3 && misses >= 3

        before = game.player.pace.energy
        turn = game.turn
        blow = game.attack target(game)
        gained = Pace::TICK * (game.turn - turn)

        expect(game.player.pace.energy - before).to eq gained - Kind::LongSword.swing
        if blow.hit?
          hits += 1
        else
          misses += 1
        end
      end

      expect(hits).to be >= 3
      expect(misses).to be >= 3
    end
  end

  describe "a shot and a throw" do
    let(game) do
      floor = Roguelike::Floor.parse "hall", HALL.join('\n')
      floor.ambient = 1
      Game.new Roguelike::World.new(20260930_u64, {"hall" => floor}),
        Player.new("hall", 3, 2, hit_points: PLENTY)
    end

    def equip(game : Game, kinds : Array({Kind, Slot, Int32})) : Nil
      kinds.each do |kind, slot, count|
        letter = game.player.inventory.add Item.new(kind, count: count, blessing_known: true)
        game.player.equipment.put(slot, letter || raise("pack full"))
      end
    end

    it "charges a bow's cost for an arrow" do
      equip game, [{Kind::Bow, Slot::Ranged, 1}, {Kind::Arrow, Slot::Quiver, 5}]
      before = game.player.pace.energy
      turn = game.turn

      game.fire({8, 2})

      expect(game.player.pace.energy - before).to eq Pace::TICK * (game.turn - turn) - 120
    end

    it "charges a sling's cost for a stone" do
      equip game, [{Kind::Sling, Slot::Ranged, 1}, {Kind::Stone, Slot::Quiver, 5}]
      before = game.player.pace.energy
      turn = game.turn

      game.fire({8, 2})

      expect(game.player.pace.energy - before).to eq Pace::TICK * (game.turn - turn) - 100
    end

    it "charges a thrown dagger the dagger's cost" do
      letter = game.player.inventory.add(Item.new(Kind::Dagger)) || raise("pack full")
      before = game.player.pace.energy
      turn = game.turn

      game.throw letter, {8, 2}

      expect(game.player.pace.energy - before).to eq Pace::TICK * (game.turn - turn) - 75
    end
  end

  describe "a monster's natural attack" do
    around_each do |example|
      Kinds.override = 100
      example.run
    ensure
      Kinds.override = nil
    end

    it "costs what its species says" do
      expect(Species::Goblin.swing).to eq Costs::TURN
      expect(Species::Orc.swing).to eq 120
    end

    it "gives an orc fewer swings than a goblin over the same ticks" do
      goblin = strikes_in duel(nil, Species::Goblin), 120
      orc = strikes_in duel(nil, Species::Orc), 120

      expect(goblin).to be_within(2).of(120)
      expect(orc).to be_within(2).of(100)
    end
  end
end
