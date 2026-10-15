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

  # Where an item lies in `MEETING`, near enough to the junction to be read
  # from where the east corridor first comes into sight.
  LYING = {15, 1}

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

  # A wide lit cavern with a corridor out of its floor that bends east out
  # of sight. A pillar south-east of the staircase hides the square behind
  # it.
  # Every other square of the cavern is in sight from the staircase.
  CAVERN = [
    "################################",
    "#..............................#",
    "#<.............................#",
    "#...#..........................#",
    "######.#########################",
    "######.#########################",
    "######.....#####################",
    "################################",
  ]

  # The far edge of `CAVERN`, too far from the staircase to read an item on.
  EDGE = {30, 1}

  # A lit room with a shut door in each end. The east door, beside the
  # staircase, opens on a corridor that turns south at once and then runs
  # east out of sight. The west door opens on a corridor that bends north.
  # From the turn the west door is nearer than the end of the long run.
  TWO_DOORS = [
    "######################",
    "#.##....##############",
    "#..+...<+.############",
    "####....#.############",
    "#########..........###",
    "##################.###",
    "##################...#",
    "######################",
  ]

  # The end of the east corridor in `TWO_DOORS`.
  EAST_END = {20, 6}

  # `TWO_DOORS` with the east corridor forking at the end of its long run.
  # One branch goes north and one goes south.
  FORKED = [
    "######################",
    "#.##....##########...#",
    "#..+...<+.########.###",
    "####....#.########.###",
    "#########..........###",
    "##################.###",
    "##################...#",
    "######################",
  ]

  # The ends of the two branches in `FORKED`.
  NORTH_END = {20, 1}
  SOUTH_END = {20, 6}

  # A long corridor with a dead end at each end. The specs below hide parts
  # of it to make pockets and open regions.
  DEAD_ENDS = [
    "########################################",
    "########################################",
    "##....................................##",
    "########################################",
    "########################################",
  ]

  # Where the character stands in `DEAD_ENDS`, four steps from the square
  # beside the west dead end.
  MIDDLE = {8, 2}

  # Every square explore on *game* takes the character to, until nothing is
  # left to see. A walk that stops for anything else is started again.
  def path(game : Game) : Array({Int32, Int32})
    stood = [game.player.at]
    10.times do
      walk = game.exploring
      while game.stride walk
        stood << game.player.at
      end
      stood << game.player.at
      break if walk.halt.try &.explored?
    end

    stood
  end

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

  # Every square of *game*'s floor written into what the character knows,
  # except those *hidden* holds for.
  def knowing_but(game : Game, &hidden : {Int32, Int32} -> Bool) : Nil
    ground = game.floor
    ground.rows.times do |row|
      ground.columns.times do |column|
        game.player.knowledge.see ground, column, row unless hidden.call({column, row})
      end
    end
  end

  # The square explore on *game* heads for.
  def heading(game : Game) : {Int32, Int32}?
    ground = game.floor
    Explore.route(game.knowledge, game.player.at, ground.columns, ground.rows).last?
  end

  # Gives *game*'s character a wielded bow and two arrows in the quiver.
  def archer(game : Game) : Nil
    game.player.inventory.add Item.new(Roguelike::ItemKind::Bow)
    game.player.inventory.add Item.new(Roguelike::ItemKind::Arrow, count: 2)
    game.wield 'a'
    game.wield 'b'
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
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Dagger)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Item
      expect(game.sight.includes?(*LYING)).to be_true
      expect(game.log.last?).to eq "A dagger comes into sight."
    end

    it "does not sight an item too far off to read" do
      game = played CAVERN
      dagger = Item.new Roguelike::ItemKind::Dagger
      game.floor.drop *EDGE, dagger
      game.enroll

      game.look

      expect(game.sight.includes?(*EDGE)).to be_true
      expect(game.sighted).not_to contain dagger.id
    end

    it "walks on past an item at the far edge of a lit cavern" do
      game = played CAVERN
      game.floor.drop *EDGE, Item.new(Roguelike::ItemKind::Dagger)
      game.enroll

      game.explore

      expect(game.knowledge.seen?(10, 6)).to be_true
    end

    it "stops for that item once near enough to read it, and names it" do
      game = played CAVERN
      dagger = Item.new Roguelike::ItemKind::Dagger
      game.floor.drop *EDGE, dagger
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Item
      expect(Roguelike::Route.apart(game.player.at, EDGE)).to eq Roguelike::Regards::READING
      expect(game.sighted).to contain dagger.id
      expect(game.log.last?).to eq "A dagger comes into sight."
    end

    it "does not stop for gold coming into sight" do
      game = played MEETING
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Gold, count: 12)
      game.enroll

      went = game.explore

      expect(went.halt).not_to eq Halt::Item
      expect(game.log.lines).not_to contain "12 gold pieces come into sight."
    end

    it "does not stop for a torch coming into sight" do
      game = played MEETING
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Torch)
      game.enroll

      went = game.explore

      expect(went.halt).not_to eq Halt::Item
      expect(game.log.lines).not_to contain "A torch comes into sight."
    end

    it "leaves a torch out of the items it names" do
      game = played MEETING
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Dagger)
      game.floor.drop 14, 1, Item.new(Roguelike::ItemKind::Torch)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Item
      expect(game.log.last?).to eq "A dagger comes into sight."
    end

    it "names two items that come into sight together, nearest first" do
      game = played MEETING
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Dagger)
      game.floor.drop 14, 1, Item.new(Roguelike::ItemKind::LongSword)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Item
      expect(game.log.last?).to eq "A long sword and a dagger come into sight."
    end

    it "does not stop again for an item it has stopped for" do
      game = played MEETING
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Dagger)
      game.enroll
      game.explore

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.floor.items(*LYING).size).to eq 1
    end

    it "stops for the same item while a replay log is being written" do
      where = (Recording.directory / "sighted-#{Random.rand UInt32}.jsonl").to_s
      game = played MEETING
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Dagger)
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
      game.floor.drop *LYING, dagger
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
      expect(Explore.wanted game.knowledge).to be_empty
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

    it "walks to arrows that match the quiver and puts them in it" do
      game = played SIDE_ROOM
      archer game
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Arrow, count: 5)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.player.quivered.try &.count).to eq 7
      expect(game.floor.items(*ASIDE)).to be_empty
      expect(game.knowledge.seen?(*BEND_END)).to be_true
    end

    it "goes on when the arrows it takes make the pack restack" do
      game = played SIDE_ROOM
      archer game
      blessed = Roguelike::Blessing::Blessed
      game.player.inventory.add Item.new(Roguelike::ItemKind::Stone, count: 2, blessing: blessed,
        blessing_known: true)
      game.player.inventory.add Item.new(Roguelike::ItemKind::Stone, blessing: blessed)
      game.player.inventory['d'].try &.reveal_blessing
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Arrow, count: 5)
      game.enroll

      went = game.explore

      expect(game.log.lines.join("\n")).to contain "You organize your pack more efficiently."
      expect(game.player.inventory.count 'c').to eq 3
      expect(went.halt).to eq Halt::Explored
      expect(game.knowledge.seen?(*BEND_END)).to be_true
    end

    it "walks to the kind an empty quiver remembers" do
      game = played SIDE_ROOM
      game.player.quiver_memory = Roguelike::Equipment::Remembered.new(Roguelike::ItemKind::Stone)
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Stone, count: 3)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.player.quivered.try &.count).to eq 3
      expect(game.player.quiver_memory).to be_nil
      expect(game.floor.items(*ASIDE)).to be_empty
    end

    it "leaves ammunition the quiver would not take" do
      game = played SIDE_ROOM
      archer game
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Arrow, count: 5, enchantment: 1)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.player.quivered.try &.count).to eq 2
      expect(game.floor.items(*ASIDE).size).to eq 1
    end

    it "takes a damaged one of the quiver's arrows on the way" do
      game = played SIDE_ROOM
      archer game
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Arrow,
        condition: Roguelike::Condition::Damaged)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.player.quivered.try &.count).to eq 2
      expect(game.player.inventory['c'].try &.condition).to eq Roguelike::Condition::Damaged
      expect(game.floor.items(*ASIDE)).to be_empty
      expect(game.knowledge.seen?(*BEND_END)).to be_true
    end

    it "walks to a potion that might join one in the pack and takes it" do
      game = played SIDE_ROOM
      game.player.inventory.add Item.new(Roguelike::ItemKind::HealingPotion)
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::HealingPotion)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.player.inventory.count 'a').to eq 2
      expect(game.floor.items(*ASIDE)).to be_empty
    end

    it "is offered while ammunition the quiver takes is remembered" do
      game = played SIDE_ROOM
      archer game
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Arrow, count: 5)
      knowing_all game
      game.look

      expect(game.legal.map &.class).to contain Action::Explore
    end

    it "follows a corridor to its end before it goes back for another door" do
      game = played TWO_DOORS

      stood = path game
      west = stood.index! { |spot| spot[0] < 4 }
      south = stood.index! { |spot| spot[1] == 6 }

      expect(stood).to contain({9, 3})
      expect(south).to be < west
      expect(game.knowledge.seen?(*EAST_END)).to be_true
      expect(game.knowledge.seen?(1, 1)).to be_true
    end

    it "follows both branches of a fork before it goes back for another door" do
      game = played FORKED

      stood = path game
      west = stood.index! { |spot| spot[0] < 4 }
      north = stood.index! { |spot| spot[0] >= 18 && spot[1] == 1 }
      south = stood.index! { |spot| spot[1] == 6 }

      expect(north).to be < west
      expect(south).to be < west
      expect(game.knowledge.seen?(*NORTH_END)).to be_true
      expect(game.knowledge.seen?(*SOUTH_END)).to be_true
      expect(game.knowledge.seen?(1, 1)).to be_true
    end

    it "leaves a corridor that holds nothing left to see" do
      game = played TWO_DOORS, at: {12, 4}
      ground = game.floor
      (8..21).each do |column|
        ground.rows.times { |row| game.player.knowledge.see ground, column, row }
      end

      stood = path game

      expect(stood.first).to eq({12, 4})
      expect(stood.size).to be > 2
      expect(game.knowledge.seen?(1, 1)).to be_true
      expect(game.knowledge.chambers(ground.columns, ground.rows).frontier?).to be_false
    end

    it "clears a dead end beside it before a large region whose edge is nearer" do
      game = played DEAD_ENDS, at: MIDDLE
      knowing_but(game) { |spot| spot[0] >= 10 || (spot[1] == 2 && {2, 3}.includes?(spot[0])) }
      ground = game.floor
      chambers = game.knowledge.chambers ground.columns, ground.rows

      expect(chambers.behind 4, 2).to eq 2
      expect(chambers.behind 9, 2).to eq Roguelike::Chambers::BEHIND
      expect(heading game).to eq({4, 2})
    end

    it "sees the dead end before it walks into the large region" do
      game = played DEAD_ENDS, at: MIDDLE, dark: true
      knowing_but(game) { |spot| spot[0] >= 10 || (spot[1] == 2 && {2, 3}.includes?(spot[0])) }

      stood = path game
      west = stood.index! { |spot| spot[0] <= 6 }
      east = stood.index! { |spot| spot[0] >= 10 }

      expect(west).to be < east
      expect(game.knowledge.seen?(2, 2)).to be_true
      expect(game.knowledge.seen?(37, 2)).to be_true
    end

    it "clears the smaller of two pockets first, though it is farther" do
      game = played DEAD_ENDS, at: MIDDLE
      knowing_but(game) { |spot| spot[1] == 2 && ({2, 3}.includes?(spot[0]) || (11..14).includes?(spot[0])) }
      ground = game.floor
      chambers = game.knowledge.chambers ground.columns, ground.rows

      expect(chambers.behind 4, 2).to eq 2
      expect(chambers.behind 10, 2).to eq 4
      expect(heading game).to eq({4, 2})
    end

    it "takes the nearer of two pockets the same size" do
      west = played DEAD_ENDS, at: {6, 2}
      east = played DEAD_ENDS, at: MIDDLE
      hidden = ->(spot : {Int32, Int32}) { spot[1] == 2 && {2, 3, 11, 12}.includes?(spot[0]) }
      knowing_but(west) { |spot| hidden.call spot }
      knowing_but(east) { |spot| hidden.call spot }

      expect(heading west).to eq({4, 2})
      expect(heading east).to eq({10, 2})
    end

    it "takes the nearer of two squares with a large region behind each" do
      game = played DEAD_ENDS, at: MIDDLE
      knowing_but(game) { |spot| spot[0] <= 3 || spot[0] >= 16 || spot[1] == 0 }
      ground = game.floor
      chambers = game.knowledge.chambers ground.columns, ground.rows

      expect(chambers.behind 4, 2).to eq Roguelike::Chambers::BEHIND
      expect(chambers.behind 15, 2).to eq Roguelike::Chambers::BEHIND
      expect(heading game).to eq({4, 2})
    end

    it "counts a pocket more than four steps off as large" do
      game = played DEAD_ENDS, at: {9, 2}
      knowing_but(game) { |spot| spot[0] >= 11 || (spot[1] == 2 && {2, 3}.includes?(spot[0])) }
      ground = game.floor
      chambers = game.knowledge.chambers ground.columns, ground.rows

      expect(Explore::REACH).to eq 4
      expect(chambers.behind 4, 2).to eq 2
      expect(heading game).to eq({10, 2})
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
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Dagger)
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

    it "does not turn aside for the quiver's arrows" do
      game = played SIDE_ROOM
      archer game
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Arrow, count: 5)
      game.enroll

      went = game.travel({20, 2})

      expect(went.halt).to eq Halt::Arrived
      expect(went.steps).to eq 19
      expect(game.player.quivered.try &.count).to eq 2
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

  describe "visit" do
    # A game on `MEETING` with a long sword and a dagger down the east
    # corridor, stopped by an explore that saw them.
    def stopped : Game
      game = played MEETING
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Dagger)
      game.floor.drop 14, 1, Item.new(Roguelike::ItemKind::LongSword)
      game.enroll
      game.explore
      game
    end

    it "walks to the square an explore stopped for" do
      game = played MEETING
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Dagger)
      game.enroll
      game.explore

      went = game.visit

      expect(went.try &.halt).to eq Halt::Arrived
      expect(game.player.at).to eq LYING
    end

    it "walks to each square in turn, nearest first" do
      game = stopped

      game.visit
      first = game.player.at
      game.visit

      expect(first).to eq({14, 1})
      expect(game.player.at).to eq LYING
      expect(game.visit).to be_nil
      expect(game.sightings).to be_empty
    end

    it "leaves out an item too far off to read" do
      game = played CAVERN
      game.floor.drop *EDGE, Item.new(Roguelike::ItemKind::Dagger)
      game.floor.drop 5, 3, Item.new(Roguelike::ItemKind::Mace)
      game.enroll

      went = game.explore

      expect(went.halt).to eq Halt::Item
      expect(game.log.last?).to eq "A mace comes into sight."
      expect(game.sight.includes?(*EDGE)).to be_true
      expect(game.sightings).to eq [{5, 3}]
    end

    it "has nothing to walk to after a stop for a creature" do
      game = played MEETING
      game.floor.place Monster.new(Species::Goblin, *FAR, "band-one")
      went = game.explore

      expect(went.halt).to eq Halt::Creature
      expect(game.visit).to be_nil
    end

    it "carries on after a step aside by hand" do
      game = stopped
      game.visit
      game.step Roguelike::Direction::West

      went = game.visit

      expect(went.try &.halt).to eq Halt::Arrived
      expect(game.player.at).to eq LYING
    end

    it "keeps the next square after the item on the first is picked up" do
      game = stopped
      game.visit
      game.perform Action::PickUp.new

      went = game.visit

      expect(game.player.inventory.items.map(&.[1].kind)).to contain Roguelike::ItemKind::LongSword
      expect(went.try &.halt).to eq Halt::Arrived
      expect(game.player.at).to eq LYING
    end

    it "adds an item that comes into sight on the way" do
      game = played MEETING
      game.floor.drop 9, 1, Item.new(Roguelike::ItemKind::Dagger)
      game.floor.drop 10, 1, Item.new(Roguelike::ItemKind::Mace)
      game.enroll
      game.explore
      expect(game.sightings).to eq [{9, 1}]

      stop = game.visit
      expect(stop.try &.halt).to eq Halt::Item
      expect(game.sightings).to eq [{9, 1}, {10, 1}]

      game.visit
      expect(game.player.at).to eq({9, 1})
      game.perform Action::PickUp.new
      went = game.visit

      expect(went.try &.halt).to eq Halt::Arrived
      expect(game.player.at).to eq({10, 1})
    end

    it "forgets what explore saw once a run starts" do
      game = stopped

      game.run Roguelike::Direction::West

      expect(game.sightings).to be_empty
    end

    it "keeps what explore saw through a single step" do
      game = stopped

      game.step Roguelike::Direction::West

      expect(game.sightings.size).to eq 2
    end

    it "passes over a square seen empty since" do
      game = stopped
      sword = game.floor.items(14, 1).first
      game.floor.take 14, 1, sword
      game.look

      game.visit

      expect(game.player.at).to eq LYING
      expect(game.visit).to be_nil
    end

    it "drops a square whose items are gone when it gets there" do
      game = stopped
      game.visit
      game.floor.take *LYING, game.floor.items(*LYING).first

      game.visit

      expect(game.player.at).to eq LYING
      expect(game.visit).to be_nil
      expect(game.sightings).to be_empty
    end

    it "forgets what explore saw once a travel starts" do
      game = stopped

      game.travel({8, 1})

      expect(game.sightings).to be_empty
      expect(game.visit).to be_nil
    end

    it "keeps the squares through a save" do
      game = stopped

      again = Game.from_json game.to_json

      expect(again.sightings).to eq game.sightings
      expect(again.sightings.size).to eq 2
    end

    it "writes one action a step, which a replay plays again" do
      where = (Recording.directory / "visit-#{Random.rand UInt32}.jsonl").to_s
      game = played MEETING
      game.floor.drop *LYING, Item.new(Roguelike::ItemKind::Dagger)
      game.floor.drop 14, 1, Item.new(Roguelike::ItemKind::LongSword)
      game.enroll
      game.player.name = Recording::PLAYER

      Recording.recording where do
        game.explore
        game.visit
        game.visit
        game
      end

      acts = Recording.read(where).records.compact_map &.as?(Roguelike::Replay::Act)
      visits = acts.compact_map &.action.as?(Action::Visit)

      expect(visits).not_to be_empty
      expect(visits.last.target).to eq LYING
      expect(Action::Visit.new(LYING).to_json).to eq %({"t":"visit","target":[15,1]})
      expect(Verifier.check(where).ok?).to be_true
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
