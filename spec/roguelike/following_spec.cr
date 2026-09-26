require "../spec_helper"

Spectator.describe "walking a route" do
  alias Direction = Roguelike::Direction
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Species = Roguelike::Species

  # The seed every example here runs on.
  SEED = 20260917_u64

  # A corridor running east from a staircase, with a passage going north at
  # column 8.
  SIDE = [
    "###############",
    "########.######",
    "#<............#",
    "###############",
  ]

  # A corridor running east into a room through an open door at column 5.
  ROOM = [
    "#############",
    "######......#",
    "#<...'......#",
    "######......#",
    "#############",
  ]

  # The same corridor and room, with the door shut.
  SHUT = [
    "#############",
    "######......#",
    "#<...+......#",
    "######......#",
    "#############",
  ]

  # A game on *lines* with the character on the up staircase.
  def walking(lines : Array(String) = SIDE) : Game
    floor = Playing.daylight Roguelike::Floor.parse("run", lines)

    Game.new Roguelike::World.new(SEED, {"run" => floor}),
      Roguelike::Player.new("run", *Game.entrance(floor), hit_points: 40)
  end

  # A game on *lines* with every square of the floor already remembered.
  #
  # A route crosses what the character remembers. A shut door blocks sight,
  # so a character who has never been through one knows nothing of the room
  # behind it and has no route into it.
  def knowing(lines : Array(String)) : Game
    game = walking lines
    floor = game.floor
    floor.each { |column, row, _tile| game.player.knowledge.see floor, column, row }

    game
  end

  # The route from where the character stands to *goal*, after a look.
  def route(game : Game, goal : {Int32, Int32}) : Array({Int32, Int32})
    game.look
    game.route_to goal
  end

  describe "Game#follow" do
    it "walks to the square it was given" do
      game = walking
      went = game.follow route(game, {12, 2})

      expect(game.player.at).to eq({12, 2})
      expect(went.halt).to eq Halt::Arrived
      expect(went.steps).to eq 11
    end

    it "takes one turn a square" do
      game = walking
      before = game.turn

      game.follow route(game, {12, 2})

      expect(game.turn).to eq before + 11
    end

    # `Game#run` stops on a junction and on a doorway. A route crosses both:
    # the person picked a square on the far side of them.
    it "crosses a junction without stopping" do
      game = walking
      game.follow route(game, {12, 2})

      expect(game.player.at).to eq({12, 2})
    end

    it "walks through a doorway without stopping" do
      game = walking ROOM
      went = game.follow route(game, {9, 2})

      expect(game.player.at).to eq({9, 2})
      expect(went.halt).to eq Halt::Arrived
    end

    # The character opens any door they can reach. The person picked a square
    # on the far side, so the walk opens the door and carries on.
    it "opens a shut door and walks on" do
      game = knowing SHUT
      went = game.follow route(game, {9, 2})

      expect(game.player.at).to eq({9, 2})
      expect(went.halt).to eq Halt::Arrived
      expect(game.floor.terrain 5, 2).to eq Roguelike::Terrain::OpenDoor
    end

    # Opening the door takes a turn of its own. The character walks through
    # on the turn after it.
    it "spends a turn on the door it opens" do
      game = knowing SHUT
      before = game.turn

      game.follow route(game, {9, 2})

      expect(game.turn).to eq before + 9
    end

    it "walks to a shut door the person picked" do
      game = walking SHUT
      went = game.follow route(game, {5, 2})

      expect(game.player.at).to eq({5, 2})
      expect(went.halt).to eq Halt::Arrived
    end

    it "stops when a creature says it has noticed the character" do
      game = walking
      game.floor.place Monster.new(Species::Goblin, 9, 1, "band-one")

      went = game.follow route(game, {12, 2})

      expect(went.halt).to eq Halt::Told
      expect(game.log.last?).to eq "The goblin notices you."
    end

    # A route is worked out over what the character remembers, and the floor
    # goes on changing after that. A route onto a square that has since been
    # shut stops against it.
    it "stops against something that has since blocked the way" do
      game = walking
      found = route game, {12, 2}
      game.floor.set 6, 2, Roguelike::Terrain::Granite

      went = game.follow found

      expect(went.halt).to eq Halt::Blocked
      expect(game.player.at).to eq({5, 2})
    end

    it "refuses a route that does not start where the character stands" do
      game = walking
      went = game.follow [{5, 2}, {6, 2}]

      expect(went.halt).to eq Halt::Blocked
      expect(went.steps).to eq 0
      expect(game.player.at).to eq({1, 2})
    end

    it "refuses a route of one square" do
      game = walking
      went = game.follow [game.player.at]

      expect(went.moved?).to be_false
    end
  end

  describe "what is lying on the way" do
    # A dagger the character has already looked at, three squares along.
    def littered : {Game, Item}
      game = walking
      dagger = Item.new Kind::Dagger
      game.floor.drop 4, 2, dagger
      game.look

      {game, dagger}
    end

    it "does not stop a route for an item already on the map" do
      game, _dagger = littered
      went = game.follow route(game, {12, 2})

      expect(game.player.at).to eq({12, 2})
      expect(went.halt).to eq Halt::Arrived
    end

    it "does not stop a walk for one either" do
      game, _dagger = littered
      went = game.run Direction::East

      expect(went.halt).to eq Halt::Branch
      expect(game.player.at).to eq({8, 2})
    end

    it "still says what is underfoot" do
      game, _dagger = littered
      game.follow route(game, {12, 2})

      expect(game.log.lines).to contain "You see a dagger here."
    end

    # The item was dropped after the character looked, so it is not on their
    # map and finding it is news.
    it "stops for an item that was not on the map" do
      game = walking
      game.look
      found = game.route_to({12, 2})
      game.floor.drop 4, 2, Item.new(Kind::Dagger)

      went = game.follow found

      expect(went.halt).to eq Halt::Told
      expect(game.player.at).to eq({4, 2})
    end

    # Two things underfoot at once, and only one of them was expected.
    it "stops for a staircase even on a square it knew had an item" do
      game = walking
      game.floor.drop 4, 2, Item.new(Kind::Dagger)
      game.floor.set 4, 2, Roguelike::Terrain::StairsDown
      game.look

      went = game.follow route(game, {12, 2})

      expect(went.halt).to eq Halt::Told
      expect(game.player.at).to eq({4, 2})
    end
  end
end
