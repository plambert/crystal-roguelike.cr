require "../spec_helper"
require "../support/recording"

Spectator.describe "exploring and travelling" do
  alias Action = Roguelike::Action
  alias Descent = Roguelike::Descent
  alias Explore = Roguelike::Explore
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Item = Roguelike::Item
  alias Monster = Roguelike::Monster
  alias Species = Roguelike::Species
  alias Verifier = Roguelike::Replay::Verifier

  # The seed every example here runs on. A failure names a run somebody can
  # start.
  SEED = 20261004_u64

  # A dark room with a shut door in its west wall at 5,3. The door is one
  # step from the start and nothing past it has been seen, so it is nearer
  # than anything in the room left to see.
  DARK_ROOM = [
    "#######################################",
    "####.#................................#",
    "####.#................................#",
    "####.+................................#",
    "######................................#",
    "######................................#",
    "#######################################",
  ]

  # Where the character starts in `DARK_ROOM`, just inside the door.
  INSIDE = {6, 3}

  # A short corridor running north into a long one running east. Nothing of
  # the east corridor is in sight from the staircase.
  MEETING = [
    "#########################",
    "#.......................#",
    "########.################",
    "########.################",
    "########<################",
    "#########################",
  ]

  # Where the creature in `MEETING` stands, fifteen squares down the east
  # corridor from the junction.
  FAR = {23, 1}

  # One lit room, every square of it in sight from the staircase.
  HALL = [
    "##########",
    "#........#",
    "#<.......#",
    "#........#",
    "##########",
  ]

  # A room and a corridor east of it behind a shut door.
  DOORED = [
    "##############",
    "#....#########",
    "#<...+.......#",
    "#....#########",
    "##############",
  ]

  # A lit room with a corridor out of its east side that bends south out of
  # sight. The way from the staircase to the bend keeps to the middle row.
  SIDE_ROOM = [
    "########################",
    "#.....##################",
    "#<...................###",
    "#.....##############.###",
    "####################.###",
    "####################...#",
    "########################",
  ]

  # A square of `SIDE_ROOM` off the way to the bend.
  ASIDE = {4, 3}

  # The end of the corridor in `SIDE_ROOM`.
  BEND_END = {22, 5}

  # A lit room with a sealed pocket in its east end.
  POCKET = [
    "##########",
    "#.....#..#",
    "#<....#..#",
    "#.....#..#",
    "##########",
  ]

  # A game on *lines*, the character on the up staircase or at *at*. The
  # floor is lit unless *dark*. A dark floor gives the character a lit
  # candle.
  def played(lines : Array(String), at : {Int32, Int32}? = nil,
             dark : Bool = false) : Game
    floor = Floor.parse "here", lines
    floor.ambient = 1 unless dark
    player = Roguelike::Player.new "here", *(at || Game.entrance(floor)), hit_points: 40
    player.inventory.add Item.new(Roguelike::ItemKind::Candle, lit: true) if dark

    Game.new Roguelike::World.new(SEED, {"here" => floor}), player
  end

  # Every square of *game*'s floor written into what the character knows.
  def knowing_all(game : Game) : Nil
    ground = game.floor
    ground.rows.times do |row|
      ground.columns.times { |column| game.player.knowledge.see ground, column, row }
    end
  end

  describe "explore" do
    it "sweeps a room before it leaves it" do
      game = played DARK_ROOM, at: INSIDE, dark: true
      room = ->(spot : {Int32, Int32}) { (6..37).includes?(spot[0]) && (1..5).includes?(spot[1]) }

      # The door is nearer than anything in the room left to see, so it is
      # the room that keeps the character in.
      game.look
      ground = game.floor
      chambers = game.knowledge.chambers ground.columns, ground.rows
      descent = Descent.toward game.knowledge, INSIDE, 400, doors: true
      nearest = Explore.nearest descent, chambers.frontier
      expect(nearest.try { |spot| room.call spot }).to be_false

      left = nil.as({Int32, Int32}?)
      30.times do
        walk = game.exploring
        loop do
          going = game.stride walk
          left = game.player.at unless room.call game.player.at
          break if left || !going
        end
        break if left || walk.halt.try &.explored?
      end

      expect(left).to eq({5, 3})
      (1..5).each do |row|
        (6..37).each do |column|
          expect(game.knowledge.seen?(column, row)).to be_true, "#{column},#{row}"
        end
      end
    end

    it "stops when a creature comes into view, and says so" do
      game = played MEETING
      game.floor.place Monster.new(Species::Goblin, *FAR, "band-one")

      went = game.explore

      expect(went.halt).to eq Halt::Creature
      expect(went.steps).to be > 0
      expect(game.monsters_in_sight.map &.species).to eq [Species::Goblin]
      expect(game.log.last?).to eq "You stop. A goblin warrior comes into view."
    end

    it "walks over something lying in sight without stopping" do
      game = played MEETING
      game.floor.drop 8, 2, Item.new(Roguelike::ItemKind::Dagger)
      game.enroll

      went = game.explore

      expect(went.halt).not_to eq Halt::Item
      expect(went.halt).not_to eq Halt::Told
      expect(game.player.at).not_to eq({8, 2})
      expect(game.floor.items(8, 2).size).to eq 1
    end

    it "picks up gold on the way without stopping" do
      game = played MEETING
      game.floor.drop 8, 2, Item.new(Roguelike::ItemKind::Gold, count: 7)
      game.enroll

      went = game.explore

      expect(went.halt).not_to eq Halt::Item
      expect(went.halt).not_to eq Halt::Told
      expect(game.player.gold).to eq 7
      expect(game.player.at).not_to eq({8, 2})
      expect(game.log.lines).to contain "You pick up 7 gold pieces."
    end

    it "stops when an item not seen before comes into sight, and says so" do
      game = played MEETING
      game.floor.drop *FAR, Item.new(Roguelike::ItemKind::Dagger)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Item
      expect(game.sight.includes?(*FAR)).to be_true
      expect(game.log.last?).to eq "A dagger comes into sight."
    end

    it "does not stop for gold coming into sight" do
      game = played MEETING
      game.floor.drop *FAR, Item.new(Roguelike::ItemKind::Gold, count: 12)
      game.enroll

      went = game.explore

      expect(went.halt).not_to eq Halt::Item
      expect(game.log.lines).not_to contain "12 gold pieces come into sight."
    end

    it "does not stop for a torch coming into sight" do
      game = played MEETING
      game.floor.drop *FAR, Item.new(Roguelike::ItemKind::Torch)
      game.enroll

      went = game.explore

      expect(went.halt).not_to eq Halt::Item
      expect(game.log.lines).not_to contain "A torch comes into sight."
    end

    it "leaves a torch out of the items it names" do
      game = played MEETING
      game.floor.drop *FAR, Item.new(Roguelike::ItemKind::Dagger)
      game.floor.drop 22, 1, Item.new(Roguelike::ItemKind::Torch)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Item
      expect(game.log.last?).to eq "A dagger comes into sight."
    end

    it "names two items that come into sight together, nearest first" do
      game = played MEETING
      game.floor.drop *FAR, Item.new(Roguelike::ItemKind::Dagger)
      game.floor.drop 22, 1, Item.new(Roguelike::ItemKind::LongSword)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Item
      expect(game.log.last?).to eq "A long sword and a dagger come into sight."
    end

    it "does not stop again for an item it has stopped for" do
      game = played MEETING
      game.floor.drop *FAR, Item.new(Roguelike::ItemKind::Dagger)
      game.enroll
      game.explore

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.floor.items(*FAR).size).to eq 1
    end

    it "stops for the same item while a replay log is being written" do
      where = (Recording.directory / "sighted-#{Random.rand UInt32}.jsonl").to_s
      game = played MEETING
      game.floor.drop *FAR, Item.new(Roguelike::ItemKind::Dagger)
      game.enroll
      game.player.name = Recording::PLAYER

      went = Recording.recording where do
        game.explore
        game
      end

      expect(went.log.last?).to eq "A dagger comes into sight."
      expect(Verifier.check(where).ok?).to be_true
    end

    it "keeps what it has seen through a save" do
      game = played MEETING
      dagger = Item.new Roguelike::ItemKind::Dagger
      game.floor.drop *FAR, dagger
      game.enroll
      game.explore

      again = Game.from_json game.to_json
      went = again.explore

      expect(again.sighted).to eq game.sighted
      expect(again.sighted).to contain dagger.id
      expect(went.halt).not_to eq Halt::Item
    end

    it "says there is nothing left to see where every square is known" do
      game = played HALL
      before = game.turn

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(went.steps).to eq 0
      expect(game.turn).to eq before
      expect(game.log.last?).to eq "There is nothing left to see on this floor."
    end

    it "says the same for one action, and takes no turn" do
      game = played HALL
      game.look

      expect(game.perform(Action::Explore.new).allowed).to be_true
      expect(game.turn).to eq 0
      expect(game.log.last?).to eq "There is nothing left to see on this floor."
    end

    it "is offered while there is anything left to see" do
      game = played MEETING
      game.look

      expect(game.legal.map &.class).to contain Action::Explore
    end

    it "is not offered once there is nothing left to see" do
      game = played HALL
      game.look

      expect(game.legal.map &.class).not_to contain Action::Explore
    end

    it "opens a shut door in its way" do
      game = played DOORED
      game.look

      went = game.explore

      expect(game.floor.terrain(5, 2).open_door?).to be_true
      expect(went.steps).to be > 0
    end

    it "walks to gold in sight off its way and takes it" do
      game = played SIDE_ROOM
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Gold, count: 7)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.player.gold).to eq 7
      expect(game.floor.items(*ASIDE)).to be_empty
      expect(game.knowledge.seen?(*BEND_END)).to be_true
    end

    it "takes the nearer of two piles first" do
      game = played SIDE_ROOM
      game.floor.drop 5, 1, Item.new(Roguelike::ItemKind::Gold, count: 9)
      game.floor.drop 3, 3, Item.new(Roguelike::ItemKind::Gold, count: 3)
      game.enroll

      game.explore
      taken = game.log.lines.select &.starts_with?("You pick up")

      expect(taken).to eq ["You pick up 3 gold pieces.", "You pick up 9 gold pieces."]
      expect(game.player.gold).to eq 12
    end

    it "goes on when gold it remembers is gone" do
      game = played SIDE_ROOM
      coins = Item.new Roguelike::ItemKind::Gold, count: 5
      game.floor.drop *BEND_END, coins
      knowing_all game
      game.floor.take *BEND_END, coins

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(went.steps).to be > 0
      expect(game.player.gold).to eq 0
      expect(Explore.gold game.knowledge).to be_empty
      expect(game.log.last?).to eq "There is nothing left to see on this floor."
    end

    it "leaves gold it cannot reach" do
      game = played POCKET
      game.floor.drop 8, 2, Item.new(Roguelike::ItemKind::Gold, count: 4)
      knowing_all game
      game.look

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(went.steps).to eq 0
      expect(game.turn).to eq 0
      expect(game.legal.map &.class).not_to contain Action::Explore
    end

    it "is offered while gold it can reach is remembered" do
      game = played SIDE_ROOM
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Gold, count: 2)
      knowing_all game
      game.look

      expect(game.legal.map &.class).to contain Action::Explore
    end

    it "sees the whole of a dug floor" do
      rng = Roguelike::Rng.new SEED
      game = Game.start rng, Roguelike::Generator.floor(rng, Roguelike::World.id(1), 1, 64, 32)
      game.floor.monsters.clear
      ground = game.floor
      halt = nil

      400.times do
        halt = game.explore.halt
        break if halt.explored? || game.over?
      end

      expect(halt).to eq Halt::Explored
      expect(game.knowledge.chambers(ground.columns, ground.rows).frontier?).to be_false
    end
  end

  describe "travel" do
    it "reaches the square chosen" do
      game = played HALL
      goal = {8, 3}

      went = game.travel goal

      expect(went.halt).to eq Halt::Arrived
      expect(game.player.at).to eq goal
      expect(game.turn).to eq went.steps
      expect(game.log.last?).to eq "You arrive."
    end

    it "opens a shut door on the way" do
      game = played DOORED
      knowing_all game

      went = game.travel({12, 2})

      expect(went.halt).to eq Halt::Arrived
      expect(game.player.at).to eq({12, 2})
      expect(game.floor.terrain(5, 2).open_door?).to be_true
    end

    it "stops when an item not seen before comes into sight" do
      game = played MEETING
      game.floor.drop *FAR, Item.new(Roguelike::ItemKind::Dagger)
      game.enroll

      went = game.travel({8, 1})

      expect(went.halt).to eq Halt::Item
      expect(game.log.last?).to eq "A dagger comes into sight."
    end

    it "takes one step for one action" do
      game = played HALL
      game.look

      verdict = game.perform Action::Travel.new({8, 2})

      expect(verdict.step).to eq Roguelike::Step::Moved
      expect(game.player.at).to eq({2, 2})
      expect(game.turn).to eq 1
    end

    it "takes no turn on the square chosen" do
      game = played HALL
      game.look

      game.perform Action::Travel.new(game.player.at)

      expect(game.turn).to eq 0
      expect(game.log.last?).to eq "You are already there."
    end

    it "does not turn aside for gold" do
      game = played SIDE_ROOM
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Gold, count: 7)
      game.enroll

      went = game.travel({20, 2})

      expect(went.halt).to eq Halt::Arrived
      expect(went.steps).to eq 19
      expect(game.player.gold).to eq 0
      expect(game.floor.items(*ASIDE).size).to eq 1
    end

    it "says when it knows no way there" do
      game = played ["#######", "#<#...#", "#######"]
      knowing_all game

      went = game.travel({4, 1})

      expect(went.halt).to eq Halt::Blocked
      expect(went.steps).to eq 0
      expect(game.log.last?).to eq "You know no way there."
    end

    it "writes one action a step" do
      game = played HALL
      goal = {8, 1}

      expect(Action.from_json(Action::Travel.new(goal).to_json).as(Action::Travel).target)
        .to eq goal
      expect(Action::Travel.new(goal).to_json).to eq %({"t":"travel","target":[8,1]})
      expect(Action::Explore.new.to_json).to eq %({"t":"explore"})
      expect(game.travel(goal).steps).to eq 7
    end
  end

  describe "a recorded run" do
    it "holds explore and travel actions, and verifies" do
      where = (Recording.directory / "explore-#{Random.rand UInt32}.jsonl").to_s

      # The creatures are taken off so that nothing stands in the way back.
      Recording.recording where do
        game = Game.dug Roguelike::Rng.new(Recording::SEED)
        game.player.name = Recording::PLAYER
        game.floor.monsters.clear
        game.look
        start = game.player.at

        6.times do
          break if game.over?
          game.explore
        end
        game.travel start unless game.over?
        game
      end

      read = Recording.read where
      verbs = read.records.compact_map { |record| record.as?(Roguelike::Replay::Act).try &.action.class }

      expect(verbs).to contain Action::Explore
      expect(verbs).to contain Action::Travel
      expect(Verifier.check(where).ok?).to be_true
    end
  end
end
