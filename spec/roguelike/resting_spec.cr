require "../spec_helper"
require "../support/recording"

Spectator.describe "resting" do
  alias Action = Roguelike::Action
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # A hall with the character near the west end.
  HALL = ["######################",
          "#....................#",
          "#..<.................#",
          "#....................#",
          "######################"]

  # A game on `HALL` with the character *down* hit points.
  #
  # *lit* lights every square. A dark hall is how a spec puts a creature on
  # the floor that the character cannot see.
  def hall(down : Int32 = 6, lit : Bool = true) : Game
    floor = Floor.parse "hall", HALL.join('\n')
    floor.ambient = 1 if lit

    game = Game.new World.new(Playing::SEED, {"hall" => floor}),
      Player.new("hall", 3, 2)
    game.enrol
    game.player.hurt down

    game
  end

  # A hall split by a wall, with the way round it along the bottom.
  #
  # A creature east of the wall is out of sight from the west of it. It has
  # to walk south, round the end of the wall, and back north to be seen.
  SPLIT = ["############",
           "#.....#....#",
           "#..<..#....#",
           "#.....#....#",
           "#..........#",
           "############"]

  # A game on `SPLIT` with the character *down* hit points.
  def split(down : Int32 = 6) : Game
    floor = Playing.daylight Floor.parse("split", SPLIT.join('\n'))

    game = Game.new World.new(Playing::SEED, {"split" => floor}),
      Player.new("split", 3, 2)
    game.enrol
    game.player.hurt down

    game
  end

  # Puts a creature of *species* on the floor of *game* at *at*.
  def creature(game : Game, at : {Int32, Int32},
               species : Species = Species::Goblin) : Monster
    found = Monster.new species, at[0], at[1], "band-one"
    game.floor.place found

    found
  end

  # Tells the band *found* belongs to that it has walked this floor and that
  # the character is where they are standing now.
  #
  # A creature left alone never notices a character it cannot see. This is
  # the state it is in after seeing them and losing sight of them, which is
  # the state that sends it walking towards them.
  def hunting(game : Game, found : Monster) : Nil
    band = game.floor.band found.band
    raise "the floor has lost the band" unless band

    knowledge = band.knowledge game.floor.id
    game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
    knowledge.saw Roguelike::Knowledge::PLAYER, game.player.x, game.player.y, game.turn
    band.awareness = Roguelike::Awareness::Hunting
  end

  describe "a rest that runs its course" do
    it "puts every hit point back" do
      game = hall 6

      game.rest

      expect(game.player.hit_points).to eq game.player.max_hit_points
    end

    it "says that the character is healed" do
      game = hall 6

      expect(game.rest.halt).to eq Halt::Healed
    end

    it "takes one turn of the run for each turn of rest" do
      game = hall 6
      before = game.turn

      rest = game.rest

      expect(rest.turns).to be > 0
      expect(game.turn).to eq before + rest.turns
    end

    it "writes nothing to the log" do
      game = hall 6
      before = game.log.size

      game.rest

      expect(game.log.size).to eq before
    end
  end

  describe "a rest that cannot start" do
    it "is refused at full health" do
      game = hall 0
      rest = game.resting

      expect(rest.halt).to eq Halt::Healed
      expect(rest.turns).to eq 0
    end

    it "is refused with a creature in sight" do
      game = hall 6
      creature game, {10, 2}

      rest = game.resting

      expect(rest.halt).to eq Halt::InSight
      expect(rest.turns).to eq 0
    end

    it "takes no turn when it is refused" do
      game = hall 6
      creature game, {10, 2}
      before = game.turn

      game.rest

      expect(game.turn).to eq before
    end

    # The character cannot see a creature in the dark. A rule that read the
    # floor rather than their own sight would tell the person something their
    # character does not know.
    it "is not refused by a creature the character cannot see" do
      game = hall 6, lit: false
      creature game, {10, 2}

      expect(game.resting.halt).to be_nil
    end
  end

  describe "a rest that is stopped" do
    # The creature walks round the wall while the character rests, and the
    # turn it comes into sight is the turn the rest stops.
    it "stops when a creature comes into sight" do
      game = split 6
      hunting game, creature(game, {9, 2})

      rest = game.rest

      expect(rest.halt).to eq Halt::Creature
      expect(game.monsters_in_sight).not_to be_empty
    end

    # A creature beside the character in the dark swings at them. The blow
    # takes hit points off, and the blow and the miss before it each write a
    # line. Either one stops the rest.
    it "stops when a creature the character cannot see reaches them" do
      game = hall 6, lit: false
      hunting game, creature(game, {4, 2})

      rest = game.rest

      expect(rest.turns).to be < 20
      expect([Halt::Hurt, Halt::Told, Halt::Over]).to contain rest.halt
    end

    it "stops when a line is written" do
      game = hall 6
      game.player.pace.hurry 3

      rest = game.rest

      expect(rest.halt).to eq Halt::Told
      expect(game.log.last?).to eq "You slow down again."
    end
  end

  describe "the record of a rest" do
    # A rest is a series of waits, and it is logged as the waits it expands
    # into. A rest that reached `Game#wait` directly would leave nothing in
    # the log and the run would not play back.
    it "writes one wait to the replay log for each turn" do
      where = (Recording.directory / "rest-#{Random.rand UInt32}.jsonl").to_s
      turns = 0

      Recording.recording where do
        game = hall 6
        game.player.name = "rester"
        turns = game.rest.turns
        game
      end

      waits = File.read_lines(where).count &.includes?(%("t":"wait"))

      expect(turns).to be > 0
      expect(waits).to eq turns
    end

    it "plays the recorded rest back" do
      where = (Recording.directory / "back-#{Random.rand UInt32}.jsonl").to_s

      Recording.recording where do
        game = hall 6
        game.player.name = "rester"
        game.rest
        game
      end

      expect(Roguelike::Replay::Verifier.check(where).trouble).to be_nil
    end

    it "reports each turn as an event" do
      game = hall 6
      rest = game.resting

      game.linger rest

      expect(game.events.compact_map(&.as?(Event::Waited)).size).to eq 1
    end

    it "reports a hit point put back as an event" do
      game = hall 6
      rest = game.resting
      gained = 0

      while game.linger rest
        gained += game.events.compact_map(&.as?(Event::Healed)).sum &.amount
      end

      gained += game.events.compact_map(&.as?(Event::Healed)).sum &.amount

      expect(gained).to eq 6
    end
  end
end
