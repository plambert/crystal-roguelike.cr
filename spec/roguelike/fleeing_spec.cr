require "../spec_helper"

Spectator.describe "hurt creatures running" do
  alias Awareness = Roguelike::Awareness
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Kind = Roguelike::Kind
  alias Knowledge = Roguelike::Knowledge
  alias Lighting = Roguelike::Lighting
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias Terrain = Roguelike::Terrain
  alias Trial = Roguelike::Trial
  alias World = Roguelike::World

  # A long room. The character stands at its west end.
  HALL = [
    "#####################",
    "#...................#",
    "#...................#",
    "#...................#",
    "#####################",
  ]

  # A dead end one square wide.
  DEAD_END = [
    "#####",
    "#...#",
    "#####",
  ]

  # A room with a doorway in the middle of a wall.
  DOORWAY = [
    "###########",
    "#....'....#",
    "###########",
  ]

  # A game on *lines* with a band-one creature of *kind* at *at* holding
  # *hit_points*, and the character at *hero*.
  #
  # The band has seen the whole floor and last saw the character where they
  # stand, so the spec is about running and not about noticing. A floor is
  # dark unless *daylight* says it is not.
  def hunted(lines : Array(String), kind : Kind, at : {Int32, Int32},
             hit_points : Int32, hero : {Int32, Int32},
             daylight : Bool = true) : {Game, Monster}
    floor = Floor.parse "fleeing", lines
    floor.ambient = 1 if daylight
    creature = Monster.new kind, at[0], at[1], "band-one", hit_points: hit_points
    floor.place creature

    player = Player.new floor.id, hero[0], hero[1], hit_points: 5000
    game = Game.new World.new(20260930_u64, {floor.id => floor}), player

    band = floor.band "band-one"
    raise "the floor has lost the band" unless band

    knowledge = band.knowledge floor.id
    floor.each { |column, row, _tile| knowledge.see floor, column, row }
    knowledge.saw Knowledge::PLAYER, player.x, player.y, game.turn
    band.awareness = Awareness::Hunting

    {game, creature}
  end

  def pass(game : Game, turns : Int32) : Nil
    turns.times { game.wait }
  end

  describe "a goblin warrior with 9 hit points" do
    it "runs below a quarter of them" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {5, 2}, 2, {1, 2}

      pass game, 4

      expect(goblin.fleeing?).to be_true
      expect(goblin.x).to be > 5
    end

    it "says so when the character can see it turn" do
      game, _goblin = hunted HALL, Kind::GoblinWarrior, {5, 2}, 2, {1, 2}

      game.wait

      expect(game.log.lines).to contain "The goblin warrior flees!"
    end

    it "says nothing when the character cannot see it turn" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {5, 2}, 2, {1, 2}, daylight: false

      game.wait

      expect(goblin.fleeing?).to be_true
      expect(game.log.lines).not_to contain "The goblin warrior flees!"
    end

    it "does not run at a quarter" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {5, 2}, 3, {1, 2}

      game.wait

      expect(goblin.fleeing?).to be_false
    end

    it "keeps running between a quarter and a half" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {9, 2}, 2, {1, 2}
      game.wait
      goblin.heal 2

      game.wait

      expect(goblin.hit_points).to eq 4
      expect(goblin.fleeing?).to be_true
    end

    it "turns back above a half" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {9, 2}, 2, {1, 2}
      game.wait
      goblin.heal 3

      game.wait

      expect(goblin.hit_points).to eq 5
      expect(goblin.fleeing?).to be false
    end

    it "runs, recovers and comes back to the character" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {5, 2}, 2, {1, 2}

      pass game, 12
      furthest = goblin.x
      expect(goblin.fleeing?).to be_true

      pass game, 40
      expect(goblin.fleeing?).to be_false

      knowledge = game.floor.band("band-one").try &.knowledge(game.floor.id)
      knowledge.try &.saw(Knowledge::PLAYER, game.player.x, game.player.y, game.turn)
      game.floor.band("band-one").try &.awareness = Awareness::Hunting
      pass game, 10

      expect(goblin.x).to be < furthest
    end
  end

  describe "the square it runs to" do
    # Three squares are one step further from the character than the goblin
    # is: the ones to the east, north east and south east. East is the one
    # `Direction` names first, so a lit east square shows the light decided.
    # A glowing square lights the nine around it.
    it "is the darker one" do
      lines = HALL.dup
      lines[3] = "#..........*........#"
      game, goblin = hunted lines, Kind::GoblinWarrior, {10, 2}, 2, {1, 2}, daylight: false

      game.wait

      expect(goblin.at).to eq({11, 1})
    end

    it "is not the lit one whichever side the light is on" do
      lines = HALL.dup
      lines[1] = "#..........*........#"
      game, goblin = hunted lines, Kind::GoblinWarrior, {10, 2}, 2, {1, 2}, daylight: false

      game.wait

      light = Lighting.over game.floor, game.lights
      expect(goblin.x).to eq 11
      expect(light.level(*goblin.at)).to eq 0
    end

    it "is the same one when the light is not there" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {10, 2}, 2, {1, 2}, daylight: false

      game.wait

      expect(goblin.at).to eq({11, 2})
    end

    it "is nearer the rest of the band when the light is the same" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {10, 2}, 2, {1, 2}
      mate = Monster.new Kind::GoblinWarrior, 14, 1, "band-one"
      game.floor.place mate

      game.wait

      expect(goblin.at).to eq({11, 1})
    end
  end

  describe "a goblin warrior with nowhere to run" do
    it "fights" do
      game, goblin = hunted DEAD_END, Kind::GoblinWarrior, {3, 1}, 2, {2, 1}

      pass game, 4

      expect(goblin.fleeing?).to be_true
      expect(goblin.at).to eq({3, 1})
      swung = game.log.lines.select { |line| line =~ /The goblin warrior (hits|misses) you/ }
      expect(swung).not_to be_empty
    end
  end

  describe "a slime" do
    it "never runs" do
      game, slime = hunted HALL, Kind::WhiteSlime, {5, 2}, 1, {1, 2}

      pass game, 3

      expect(slime.fleeing?).to be_false
      expect(slime.x).to be < 5
    end

    it "is the only species that does not" do
      Kind.each { |kind| expect(kind.flees?).to eq(!kind.species.slime?) }
    end
  end

  describe "a goblin warrior running through a doorway" do
    it "shuts the door behind it" do
      game, _goblin = hunted DOORWAY, Kind::GoblinWarrior, {5, 1}, 2, {2, 1}

      pass game, 3

      expect(game.floor.terrain(5, 1)).to eq Terrain::ClosedDoor
      expect(game.log.lines).to contain "The goblin warrior shuts the door."
    end

    it "leaves the door open while the character is in the way" do
      game, goblin = hunted DOORWAY, Kind::GoblinWarrior, {6, 1}, 2, {5, 1}

      pass game, 3

      expect(goblin.x).to be > 6
      expect(game.floor.terrain(5, 1)).to eq Terrain::OpenDoor
    end
  end

  describe "hit points coming back" do
    it "is one every ten turns, to every creature" do
      game, slime = hunted HALL, Kind::WhiteSlime, {19, 1}, 2, {1, 2}
      slime.blind 1000

      pass game, 9
      expect(slime.hit_points).to eq 2

      game.wait
      expect(slime.hit_points).to eq 3

      pass game, 10
      expect(slime.hit_points).to eq 4
    end

    it "stops at full" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {19, 1}, 8, {1, 2}

      pass game, 30

      expect(goblin.hit_points).to eq goblin.max_hit_points
    end
  end

  describe "a save file" do
    it "keeps a creature running" do
      _game, goblin = hunted HALL, Kind::GoblinWarrior, {5, 2}, 2, {1, 2}
      goblin.flee

      expect(Monster.from_json(goblin.to_json).fleeing?).to be_true
    end

    it "keeps a game with a running creature" do
      game, goblin = hunted HALL, Kind::GoblinWarrior, {5, 2}, 2, {1, 2}
      pass game, 3

      again = Game.from_json game.to_json

      found = again.floor.monster(goblin.x, goblin.y)
      expect(found).not_to be_nil
      expect(found.try &.fleeing?).to be_true
    end

    it "loads an older one with every creature standing its ground" do
      _game, goblin = hunted HALL, Kind::GoblinWarrior, {5, 2}, 2, {1, 2}
      goblin.flee
      found = JSON.parse(goblin.to_json).as_h
      found.delete "fleeing"

      expect(Monster.from_json(found.to_json).fleeing?).to be_false
    end
  end

  describe "one seed" do
    it "plays out the same way twice" do
      first, one = hunted HALL, Kind::GoblinWarrior, {5, 2}, 2, {1, 2}
      second, two = hunted HALL, Kind::GoblinWarrior, {5, 2}, 2, {1, 2}

      pass first, 60
      pass second, 60

      expect({one.at, one.hit_points, one.fleeing?}).to eq({two.at, two.hit_points, two.fleeing?})
    end

    it "gives a trial run the same result twice" do
      expect(Trial.one(5000_u64, 400)).to eq Trial.one(5000_u64, 400)
    end
  end
end
