require "../spec_helper"

Spectator.describe "creatures pathing around each other" do
  alias Awareness = Roguelike::Awareness
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # A corridor along the top and another along the bottom, joined at both
  # ends. The character starts at the west end of the top one.
  LOOP = [
    "#########",
    "#<......#",
    "#.#####.#",
    "#.......#",
    "#########",
  ]

  # A room with the character in its north west corner.
  CORNER = [
    "###########",
    "#<........#",
    "#.........#",
    "#.........#",
    "#.........#",
    "###########",
  ]

  # A game on *lines* with a goblin band at each of *spots*, all hunting.
  #
  # The band has walked the whole floor and last saw the character where
  # they stand, so the spec is about walking and not about noticing.
  def hunt(lines : Array(String), spots : Array({Int32, Int32})) : {Game, Array(Monster)}
    floor = Playing.daylight Floor.parse("pathing", lines)
    members = spots.map { |spot| Monster.new Species::Goblin, spot[0], spot[1], "band-one" }
    members.each { |member| floor.place member }

    player = Player.new floor.id, *Game.entrance(floor), hit_points: 5000
    game = Game.new World.new(20260930_u64, {floor.id => floor}), player

    band = floor.band "band-one"
    raise "the floor has lost the band" unless band

    knowledge = band.knowledge floor.id
    floor.each { |column, row, _tile| knowledge.see floor, column, row }
    knowledge.saw Knowledge::PLAYER, player.x, player.y, game.turn
    band.awareness = Awareness::Hunting

    {game, members}
  end

  # Passes *turns* turns with the character standing still.
  def pass(game : Game, turns : Int32) : Nil
    turns.times { game.wait }
  end

  # Puts a goblin of another band on *at* that cannot see, so it never wakes
  # and never moves. Goblins do not fight goblins, so it stays in the way.
  def plug(game : Game, at : {Int32, Int32}) : Monster
    goblin = Monster.new Species::Goblin, at[0], at[1], "band-asleep"
    goblin.blind 1000
    game.floor.place goblin
    goblin
  end

  describe "a corridor with a creature standing in it" do
    # The plug is in the top corridor, and the two goblins behind it can
    # only reach the character by the bottom one.
    it "sends the members behind it round by the other way" do
      game, members = hunt LOOP, [{5, 1}, {4, 1}]
      plug game, {3, 1}

      furthest = members.map &.x
      20.times do
        game.wait
        members.each_with_index { |member, index| furthest[index] = {furthest[index], member.x}.min }
      end

      expect(furthest).to all(be < 3)
      expect(game.floor.monster? 3, 1).to be_true
    end

    it "waits behind it while it counts the turns" do
      game, members = hunt LOOP, [{4, 1}]
      plug game, {3, 1}

      pass game, 2

      expect(members.first.at).to eq({4, 1})
      expect(members.first.hemmed).to be >= 2
    end

    it "clears the count once it is walking again" do
      game, members = hunt LOOP, [{4, 1}]
      plug game, {3, 1}

      pass game, 6

      expect(members.first.at).not_to eq({4, 1})
      expect(members.first.hemmed).to eq 0
    end
  end

  describe "three creatures after a character in a corner" do
    # The corner has three squares beside the character. The first two to
    # arrive take two of them, and the third has to go round to the last.
    it "take every square beside them" do
      game, members = hunt CORNER, [{6, 1}, {7, 1}, {8, 1}]

      pass game, 20

      beside = [{2, 1}, {1, 2}, {2, 2}]
      expect(members.map(&.at).sort!).to eq beside.sort
    end

    it "arrive on more than one side of the character" do
      game, members = hunt CORNER, [{6, 1}, {7, 1}, {8, 1}]

      pass game, 20

      expect(members.map(&.x).uniq!.size).to be > 1
      expect(members.map(&.y).uniq!.size).to be > 1
    end

    it "play out the same way twice from one seed" do
      first, one = hunt CORNER, [{6, 1}, {7, 1}, {8, 1}]
      second, two = hunt CORNER, [{6, 1}, {7, 1}, {8, 1}]

      pass first, 20
      pass second, 20

      expect(one.map &.at).to eq two.map(&.at)
    end
  end
end
