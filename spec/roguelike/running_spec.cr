require "../spec_helper"

Spectator.describe "running" do
  alias Direction = Roguelike::Direction
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Species = Roguelike::Species

  # The seed every example here runs on. A failure names a run somebody can
  # start.
  SEED = 20260913_u64

  EAST = Direction::East

  # A corridor running east from a staircase, with a passage going north at
  # column 8 and an alcove of two squares above it.
  SIDE = [
    "###############",
    "########..#####",
    "#<............#",
    "###############",
  ]

  # Where the character starts in `SIDE`.
  START = {1, 2}

  # A short corridor running north into a long one running east.
  #
  # Nothing of the east corridor is in sight until the character reaches the
  # junction at 8,1. A creature at 23,1 is fifteen squares from there, which
  # is past what a goblin notices even in daylight, so it comes into sight
  # without saying anything and without moving.
  MEETING = [
    "#########################",
    "#.......................#",
    "########.################",
    "########.################",
    "########<################",
    "#########################",
  ]

  # Where the east corridor meets the north one.
  JUNCTION = {8, 1}

  # Where the creature in `MEETING` stands.
  FAR = {23, 1}

  # A corridor running east into a room through an open door at column 5.
  ROOM = [
    "#############",
    "######......#",
    "#<...'......#",
    "######......#",
    "#############",
  ]

  # A dark hall. The character carries a torch, so what is down it comes into
  # sight a few squares at a time as they walk.
  DARK = [
    "################",
    "#<.............#",
    "################",
  ]

  # Where the dagger lies in `DARK`. It is out of sight from the staircase and
  # in sight several steps before the character reaches it.
  LATER = {10, 1}

  # The east end of `DARK`.
  FAR_END = {14, 1}

  # A room with the character in the middle of the west wall.
  HALL = [
    "##########",
    "#........#",
    "#<.......#",
    "#........#",
    "##########",
  ]

  # A game on *lines* with the character at *at*, or on the up staircase.
  def walking(lines : Array(String) = SIDE,
              at : {Int32, Int32}? = nil) : Game
    floor = Playing.daylight Roguelike::Floor.parse("run", lines)
    spot = at || Game.entrance(floor)

    Game.new Roguelike::World.new(SEED, {"run" => floor}),
      Roguelike::Player.new("run", *spot, hit_points: 40)
  end

  # A game on `DARK` with the character carrying a lit torch.
  def carrying_a_torch : Game
    floor = Roguelike::Floor.parse("run", DARK)
    player = Roguelike::Player.new("run", *Game.entrance(floor),
      hit_points: 40)
    player.inventory.add Playing.torch

    Game.new Roguelike::World.new(SEED, {"run" => floor}), player
  end

  # Walks *game* east the way `Ui::Play` does, with a look before the walk
  # and another between one step and the next.
  #
  # `Game#run` never looks, so the character's map is whatever it was when the
  # walk started. `Ui::Play` looks after every step. A spec about what the
  # character has seen has to look the same way.
  def run_watching(game : Game) : Roguelike::Running
    game.look
    walk = game.running EAST
    while game.stride walk
      game.look
    end

    walk.running
  end

  describe "Game#run" do
    it "stops where a corridor branches" do
      game = walking
      went = game.run EAST

      expect(went.halt).to eq Halt::Branch
      expect(game.player.at).to eq({8, 2})
      expect(went.steps).to eq 7
    end

    it "stops on the door into a room" do
      game = walking ROOM
      went = game.run EAST

      expect(went.halt).to eq Halt::Doorway
      expect(game.player.at).to eq({5, 2})
      expect(game.standing_on.open_door?).to be_true
    end

    it "stops when a creature comes into sight" do
      game = walking MEETING
      game.floor.place Monster.new(Species::Goblin, *FAR, "band-one")

      expect(game.monsters_in_sight).to be_empty
      went = game.run Direction::North

      expect(went.halt).to eq Halt::Creature
      expect(game.player.at).to eq JUNCTION
      expect(game.monsters_in_sight.map &.species).to eq [Species::Goblin]
    end

    # The junction is the same square the creature is seen from, so this is
    # what the same walk does with nothing standing there.
    it "stops at that junction for the junction when nothing is in sight" do
      went = walking(MEETING).run Direction::North

      expect(went.halt).to eq Halt::Branch
      expect(went.steps).to eq 3
    end

    # A creature announces itself on the turn it notices the character, and
    # that message is what stops the walk.
    it "stops on the message a creature makes when it notices" do
      game = walking
      game.floor.place Monster.new(Species::Goblin, 9, 1, "band-one")

      went = game.run EAST

      expect(went.halt).to eq Halt::Told
      expect(game.player.at).to eq({5, 2})
      expect(game.log.last?).to eq "The goblin notices you."
    end

    it "stops where something is said" do
      game = walking
      game.floor.drop 4, 2, Item.new(Kind::LongSword)

      went = game.run EAST

      expect(went.halt).to eq Halt::Told
      expect(game.player.at).to eq({4, 2})
      expect(game.log.last?).to contain "long sword"
    end

    # A walk never attacks. Swinging is a decision and a walk makes none.
    it "stops in front of a creature rather than swinging at it" do
      game = walking
      game.floor.place Monster.new(Species::Goblin, 2, 2, "band-one",
        hit_points: 30)

      went = game.run EAST

      expect(went.halt).to eq Halt::Blocked
      expect(went.steps).to eq 0
      expect(game.player.at).to eq START
      expect(game.floor.monster(2, 2).try &.hit_points).to eq 30
      expect(game.log.last?).to eq "The goblin is in the way."
    end

    it "stops at the end of a corridor" do
      game = walking ["######", "#<...#", "######"]

      went = game.run EAST

      expect(went.halt).to eq Halt::Blocked
      expect(game.player.at).to eq({4, 1})
      expect(went.steps).to eq 3
    end

    it "takes no step into a wall, and says why" do
      game = walking
      went = game.run Direction::North

      expect(went.steps).to eq 0
      expect(went.moved?).to be_false
      expect(game.player.at).to eq START
      expect(game.log.last?).to eq "The granite blocks your way."
    end

    # A walk makes no decisions. Opening a door and swinging at a creature are
    # both decisions, so a walk stops in front of either.
    it "stops in front of a shut door rather than opening it" do
      game = walking ["########", "#<....+#", "########"]

      went = game.run EAST

      expect(went.halt).to eq Halt::Blocked
      expect(game.player.at).to eq({5, 1})
      expect(game.floor.terrain 6, 1).to eq Roguelike::Terrain::ClosedDoor
    end

    it "crosses an empty room without stopping in the middle of it" do
      game = walking HALL

      went = game.run EAST

      expect(went.halt).to eq Halt::Blocked
      expect(game.player.at).to eq({8, 2})
    end

    it "spends a turn on every step" do
      game = walking
      before = game.turn

      went = game.run EAST

      expect(game.turn).to eq before + went.steps
    end

    it "takes no turn when it takes no step" do
      game = walking
      before = game.turn

      game.run Direction::North

      expect(game.turn).to eq before
    end

    # A creature already in sight when the walk starts does not stop it. A walk
    # could not be started at all otherwise.
    it "walks past a creature that was in sight before the first step" do
      game = walking
      game.floor.place Monster.new(Species::Slime, 12, 2, "band-one")

      expect(game.monsters_in_sight).not_to be_empty
      went = game.run EAST

      expect(went.halt).not_to eq Halt::Creature
      expect(went.steps).to be > 0
    end

    # The orc stands beside the line the character walks along rather than on
    # it, so it reaches them without standing in their way. A creature the walk
    # is walking into stops the walk without a blow.
    it "stops when the character is hurt" do
      game = walking HALL
      game.floor.place Monster.new(Species::Orc, 2, 1, "band-one",
        hit_points: 200)
      full = game.player.hit_points
      reasons = [] of Halt

      8.times do
        reasons << game.run(EAST).halt
        break if game.player.hit_points < full
      end

      expect(game.player.hit_points).to be < full
      expect(reasons.last).to eq Halt::Hurt
    end

    # A killing blow changes the hit points as well, and the walk names the
    # end of the run rather than the wound.
    it "stops because the run ended when a blow kills the character" do
      game = walking HALL
      game.floor.place Monster.new(Species::Orc, 2, 1, "band-one",
        hit_points: 200)
      game.player.hurt game.player.hit_points - 1
      reasons = [] of Halt

      8.times do
        reasons << game.run(EAST).halt
        break if game.over?
      end

      expect(game.over?).to be_true
      expect(reasons.last).to eq Halt::Over
    end

    # The dagger is out of sight when the walk starts. The character sees it
    # several steps before they reach it, so it is on their map by the time
    # they stand on it and it is not news.
    it "does not stop for an item first seen during the walk" do
      game = carrying_a_torch
      game.floor.drop LATER[0], LATER[1], Item.new(Kind::Dagger)

      went = run_watching game

      expect(game.knowledge[LATER].try &.item).not_to be_nil
      expect(game.player.at).to eq FAR_END
      expect(went.halt).to eq Halt::Blocked
      expect(game.log.lines).to contain "You see a dagger here."
    end

    # `MessageLog#add` drops a line identical to the one before it. Two
    # daggers a square apart write the same sentence, so the log grows by
    # nothing on the second one and what the character remembers is the only
    # thing left to stop the walk.
    it "stops for a second item that writes the line the first wrote" do
      game = walking
      game.floor.drop 4, 2, Item.new(Kind::Dagger)
      game.look
      game.floor.drop 5, 2, Item.new(Kind::Dagger)

      went = game.run EAST

      expect(went.halt).to eq Halt::Told
      expect(game.player.at).to eq({5, 2})
    end

    it "walks the same way twice from the same seed" do
      first = walking
      again = walking

      expect(again.run(EAST).halt).to eq first.run(EAST).halt
      expect(again.player.at).to eq first.player.at
    end
  end

  # Two rooms joined by a corridor, with an open door at each end of it and
  # one passage going north from the middle.
  #
  # Nothing stands on it and nothing lies on it, so a walk over it stops for
  # the shape of the floor and for nothing else.
  GROUND = [
    "#####################",
    "#.....#####.###.....#",
    "#.....'.......'.....#",
    "#.....#########.....#",
    "#####################",
  ]

  # The letter each halt is drawn as in the fixture.
  LETTERS = {
    Halt::Blocked  => 'b',
    Halt::Creature => 'c',
    Halt::Hurt     => 'h',
    Halt::Told     => 't',
    Halt::Doorway  => 'd',
    Halt::Branch   => 'j',
    Halt::Over     => 'o',
    Halt::Spent    => 's',
  }

  # What a walk *direction* from every square of `GROUND` does, drawn as two
  # maps: why each walk stopped, and how far it went in base thirty-six.
  def drawn(direction : Direction) : String
    shape = Roguelike::Floor.parse "ground", GROUND
    halts = [] of String
    steps = [] of String

    shape.rows.times do |row|
      why = String::Builder.new
      far = String::Builder.new

      shape.columns.times do |column|
        unless shape.passable? column, row
          why << '#'
          far << '#'
          next
        end

        went = walking(GROUND, at: {column, row}).run direction
        why << LETTERS[went.halt]
        far << went.steps.to_s(36)
      end

      halts << why.to_s
      steps << far.to_s
    end

    "#{direction.label}\n#{halts.join '\n'}\n\n#{steps.join '\n'}"
  end

  describe "drawn" do
    # A map of where a walk stops from every square of a floor, so a change to
    # any of the rules shows as a diff of two maps rather than as one failed
    # expectation.
    it "stops where it stopped last time" do
      cardinals = Direction.values.reject &.diagonal?
      maps = cardinals.map { |direction| drawn direction }.join "\n\n"

      expect(maps).to eq Fixture.expected("running/ground.txt", maps)
    end
  end

  describe "Running" do
    it "says whether the character moved" do
      expect(Roguelike::Running.new(0, Halt::Blocked).moved?).to be_false
      expect(Roguelike::Running.new(3, Halt::Branch).moved?).to be_true
    end
  end

  describe "Game::FURTHEST" do
    # A walk in one direction reaches the edge of a floor on its own, so this
    # is a guard rather than a rule anybody meets. The room is longer than
    # the guard allows.
    it "stops a walk that would otherwise go on" do
      long = ["#" * (Game::FURTHEST + 6)]
      long << "#<" + ("." * (Game::FURTHEST + 3)) + "#"
      long << "#" * (Game::FURTHEST + 6)

      went = walking(long).run EAST

      expect(went.halt).to eq Halt::Spent
      expect(went.steps).to eq Game::FURTHEST
    end
  end
end
