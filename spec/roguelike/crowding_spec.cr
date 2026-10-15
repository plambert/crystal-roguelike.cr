require "../spec_helper"

Spectator.describe "creatures crowding round the character" do
  alias Awareness = Roguelike::Awareness
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Pursuit = Roguelike::Pursuit
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # A corridor running south into a room through a doorway on row 3.
  DOORWAY = [
    "#########",
    "####.####",
    "####.####",
    "####'####",
    "#.......#",
    "#.......#",
    "#.......#",
    "#########",
  ]

  # A room to the west and a corridor running north to south past its
  # doorway on column 5.
  PASSING = [
    "#########",
    "######.##",
    "######.##",
    "######.##",
    "#....'.##",
    "#.....###",
    "######.##",
    "######.##",
    "#########",
  ]

  # A game on *lines* with the character on *at* and a goblin band at each
  # of *spots*, all hunting.
  #
  # The band has walked the whole floor and has just seen the character.
  def hunt(lines : Array(String), at : {Int32, Int32},
           spots : Array({Int32, Int32})) : {Game, Array(Monster)}
    floor = Playing.daylight Floor.parse("crowding", lines)
    members = spots.map { |spot| Monster.new Species::Goblin, spot[0], spot[1], "band-one" }
    members.each { |member| floor.place member }

    player = Player.new floor.id, at[0], at[1], hit_points: 5000
    game = Game.new World.new(20261015_u64, {floor.id => floor}), player

    band = floor.band "band-one"
    raise "the floor has lost the band" unless band

    knowledge = band.knowledge floor.id
    floor.each { |column, row, _tile| knowledge.see floor, column, row }
    knowledge.saw Knowledge::PLAYER, player.x, player.y, game.turn
    band.awareness = Awareness::Hunting

    {game, members}
  end

  # Whether *creature* swung at the character during the last action.
  def swung?(game : Game, creature : Monster) : Bool
    game.events.any? do |event|
      event.is_a?(Event::Attack) && event.attacker == creature.id
    end
  end

  # Whether *creature* stands beside the character.
  def beside?(game : Game, creature : Monster) : Bool
    Pursuit.gap(creature.at, game.player.at) == 1
  end

  describe "a character in a doorway with two creatures in the room" do
    it "has the one behind step to a side square and swing on the next turn" do
      game, members = hunt DOORWAY, {4, 3}, [{4, 4}, {4, 5}]
      front, back = members

      game.wait
      expect(front.at).to eq({4, 4})
      expect(beside? game, back).to be_true

      game.wait
      expect(swung? game, back).to be_true
    end

    it "finds a square for a third as well" do
      game, members = hunt DOORWAY, {4, 3}, [{4, 4}, {4, 5}, {4, 6}]

      3.times { game.wait }

      expect(members.all? { |member| beside? game, member }).to be_true
    end
  end

  describe "a character in a doorway with a corridor running past it" do
    # The first creature stops on the first square beside the character.
    # The free square beside the character past it is reachable only
    # through it, so it steps along to that square and lets the second in.
    it "has the one in front step along to let the other in" do
      game, members = hunt PASSING, {5, 4}, [{6, 3}, {6, 2}]
      front, back = members

      game.wait
      expect(front.at).to eq({6, 4})

      game.wait
      expect(back.at).to eq({6, 3})

      game.wait
      expect(swung? game, front).to be_true
      expect(swung? game, back).to be_true
    end
  end

  describe "a character just inside a room with creatures in the doorway" do
    it "has the one in the doorway step into the room to let the other in" do
      game, members = hunt DOORWAY, {4, 4}, [{4, 3}, {4, 2}]
      front, back = members

      game.wait
      expect(beside? game, front).to be_true
      expect(front.at).not_to eq({4, 3})

      game.wait
      expect(back.at).to eq({4, 3})

      game.wait
      expect(swung? game, back).to be_true
    end
  end

  describe "a character in a doorway with creatures in single file in the corridor" do
    it "has the one behind wait where it is" do
      game, members = hunt DOORWAY, {4, 3}, [{4, 2}, {4, 1}]
      front, back = members

      6.times do
        game.wait
        expect(front.at).to eq({4, 2})
        expect(back.at).to eq({4, 1})
      end
    end
  end
end
