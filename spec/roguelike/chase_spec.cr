require "../spec_helper"

Spectator.describe "being chased" do
  alias Awareness = Roguelike::Awareness
  alias Descent = Roguelike::Descent
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Knowledge = Roguelike::Knowledge
  alias Monster = Roguelike::Monster
  alias Notice = Roguelike::Notice
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  SEED = 20260912_u64

  # A room split by a wall, with the way round it along the bottom.
  #
  # The character starts on the left of the wall. A creature put on the right
  # of it has to walk south, round the end of the wall, and back north.
  SPLIT = [
    "##########",
    "#...#....#",
    "#.<.#....#",
    "#...#....#",
    "#........#",
    "##########",
  ]

  # One room with nothing in it.
  OPEN = [
    "##########",
    "#........#",
    "#.<......#",
    "#........#",
    "##########",
  ]

  # A game on *lines* with one creature at *at*.
  #
  # The floor is lit throughout, so nothing here turns on the light. The
  # character is given hit points enough to be chased for a hundred turns
  # without the spec becoming one about dying.
  def chase(lines : Array(String) = SPLIT,
            species : Species = Species::Goblin,
            at : {Int32, Int32} = {8, 2},
            seen : Bool = true) : {Game, Monster}
    floor = Playing.daylight Floor.parse("split", lines)
    creature = Monster.new species, at[0], at[1], "band-one"
    floor.place creature

    player = Player.new floor.id, *Game.entrance(floor), hit_points: 500
    game = Game.new World.new(SEED, {floor.id => floor}), player
    already_seen game, creature if seen

    {game, creature}
  end

  # Tells the band *creature* belongs to that it has walked this floor and
  # that the character is where they are standing now.
  #
  # A creature on the far side of a wall cannot see the character through it,
  # so left alone it would never notice them and never come round. This is
  # the state it is in after seeing them and losing sight of them, which is
  # the state pathing is for.
  def already_seen(game : Game, creature : Monster) : Nil
    band = game.floor.band creature.band
    raise "the floor has lost the band" unless band

    knowledge = band.knowledge game.floor.id
    game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
    knowledge.saw Knowledge::PLAYER, game.player.x, game.player.y, game.turn
    band.awareness = Awareness::Hunting
  end

  # Passes *turns* turns. The character steps one square east and back again,
  # which takes a turn each way and leaves them where they started.
  def wait(game : Game, turns : Int32) : Nil
    turns.times { |taken| game.step taken.even? ? Direction::East : Direction::West }
  end

  # Steps the character out of the way of the square a creature is walking
  # to, then passes *turns* turns there.
  #
  # A character standing on that square would be walked into, and walking
  # into a creature is a swing at it. A spec about giving up is not a spec
  # about a fight.
  def wait_aside(game : Game, turns : Int32) : Nil
    game.step Direction::North
    wait game, turns
  end

  # What the band the creature belongs to knows.
  def knowledge(game : Game, creature : Monster) : Knowledge
    band = game.floor.band creature.band
    raise "the floor has lost the band" unless band

    band.knowledge game.floor.id
  end

  describe "a creature on the far side of a wall" do
    # The wall runs down column 4. Walking west is walking into it.
    it "walks round it rather than into it" do
      game, creature = chase
      start = creature.at

      wait game, 4

      expect(creature.at).not_to eq start
      expect(creature.y).to be > start[1]
      expect(game.floor.passable? creature.x, creature.y).to be_true
    end

    it "reaches the character" do
      game, creature = chase

      wait game, 12

      expect(Notice.touching? creature.at, game.player.at).to be_true
    end

    it "swings once it is there" do
      game, _ = chase
      before = game.player.hit_points

      wait game, 12

      expect(game.log.lines.any? &.starts_with?("The goblin")).to be_true
      expect(game.player.hit_points).to be < before
    end

    it "hunts again once it can see them" do
      game, creature = chase

      wait game, 12

      expect(game.floor.awareness creature).to eq Awareness::Hunting
    end
  end

  describe "a creature that loses the character" do
    it "goes to where it last saw them" do
      game, creature = chase
      seen = game.player.at

      # It cannot see through the wall, so it is already walking to a square
      # it remembers rather than to one it can see.
      expect(game.floor.awareness creature).to eq Awareness::Hunting

      game.step Direction::East
      expect(game.floor.awareness creature).to eq Awareness::Alert

      wait game, 3
      expect(creature.at).not_to eq({8, 2})

      map = Descent.toward knowledge(game, creature), seen
      away = map[creature.at] || 99

      expect(away).to be < 6
    end

    # The floor goes dark, so the goblin never picks the character up again
    # when it rounds the wall. It walks to the square it remembers, finds
    # nothing there, and casts about until its patience runs out.
    it "gives up after a while" do
      game, creature = chase
      game.floor.ambient = 0

      wait_aside game, Game::PATIENCE + 6

      expect(game.floor.awareness creature).to eq Awareness::Asleep
    end

    it "forgets where they were when it gives up" do
      game, creature = chase
      game.floor.ambient = 0

      wait_aside game, Game::PATIENCE + 6

      expect(knowledge(game, creature).sighting Knowledge::PLAYER).to be_nil
    end

    it "stops walking once it has given up" do
      game, creature = chase
      game.floor.ambient = 0

      wait_aside game, Game::PATIENCE + 6
      resting = creature.at
      wait game, 6

      expect(creature.at).to eq resting
    end

    it "keeps what it learned of the floor after it gives up" do
      game, creature = chase
      game.floor.ambient = 0

      wait_aside game, Game::PATIENCE + 6

      expect(knowledge(game, creature).empty?).to be_false
    end
  end

  describe "a band's knowledge of the floor" do
    it "fills in as its creatures look about" do
      game, creature = chase seen: false
      floor = game.floor

      # It starts knowing nothing, and it is woken by hand rather than by
      # walking, because this is about what it learns and not about light.
      expect(knowledge(game, creature).empty?).to be_true
      floor.band(creature.band).try &.awareness = Awareness::Hunting

      wait game, 4

      expect(knowledge(game, creature).empty?).to be_false
      expect(knowledge(game, creature).seen? creature.x, creature.y).to be_true
    end

    it "learns nothing while it is asleep" do
      game, creature = chase seen: false

      wait game, 10

      expect(knowledge(game, creature).empty?).to be_true
      expect(creature.at).to eq({8, 2})
    end

    # A shortcut a band has never looked down is not one it can walk.
    it "leaves out what nobody in it has seen" do
      game, creature = chase seen: false
      game.floor.band(creature.band).try &.awareness = Awareness::Hunting

      wait game, 2
      found = knowledge game, creature
      hidden = 0
      game.floor.each do |column, row, tile|
        hidden += 1 if tile.passable? && !found.seen?(column, row)
      end

      expect(hidden).to be > 0
    end

    it "stays apart from what the character remembers" do
      game, creature = chase

      wait game, 4
      game.look

      expect(knowledge(game, creature).same? game.knowledge).to be_false
    end
  end

  # A corridor with one pool of light in it, thrown by a torch lying on the
  # floor rather than carried. The character stands in the light and the
  # creature stands in the dark beyond it.
  DARK = [
    "####################",
    "#............<.....#",
    "####################",
  ]

  describe "a creature in the dark looking at a lit character" do
    # Where the torch lies, two squares east of the character. It reaches six
    # squares, so the corridor west of column nine is dark.
    TORCH = {15, 1}

    # Where the creature stands, in the dark end of the corridor. Nine
    # squares off, which is as far as a goblin notices a character lit this
    # brightly.
    LURKING = {4, 1}

    def corridor : {Game, Monster}
      floor = Floor.parse "corridor", DARK
      floor.drop TORCH[0], TORCH[1], Roguelike::Item.new(Roguelike::ItemKind::Torch, lit: true)

      creature = Monster.new Species::Goblin, LURKING[0], LURKING[1], "band-one"
      floor.place creature

      player = Player.new floor.id, *Game.entrance(floor)
      {Game.new(World.new(SEED, {floor.id => floor}), player), creature}
    end

    it "cannot be seen by the character it can see" do
      game, creature = corridor
      seen = game.sight

      expect(seen.light(*game.player.at)).to be > 0
      expect(seen.light(*creature.at)).to eq 0
      expect(seen.shows? game.floor, creature.x, creature.y).to be_false
    end

    it "notices them" do
      game, creature = corridor

      game.step Direction::East

      expect(game.floor.awareness creature).to eq Awareness::Hunting
    end

    # It sees nothing but the square under its own feet, so the lit squares
    # it knows about do not join up with the one it is standing on. It walks
    # anyway: a creature knows the ground it could reach out and touch.
    it "walks toward them through the dark" do
      game, creature = corridor
      start = creature.at

      game.step Direction::East

      expect(creature.at).not_to eq start
      expect(creature.x).to be > start[0]
    end

    it "reaches them" do
      game, creature = corridor

      wait game, 12

      expect(Notice.touching? creature.at, game.player.at).to be_true
    end

    it "knows the ground beside it whether it can see it or not" do
      game, creature = corridor

      game.step Direction::East

      found = knowledge game, creature
      expect(found.seen? LURKING[0] + 1, LURKING[1]).to be_true
      expect(found.seen? LURKING[0] - 1, LURKING[1]).to be_true
    end

    # It feels its way one square at a time. It does not come to know the
    # whole dark corridor by standing in it.
    it "learns no more of the dark than it is standing in" do
      game, creature = corridor

      game.step Direction::East
      found = knowledge game, creature

      expect(found.seen? 8, 1).to be_false
    end
  end

  describe "a creature that does not path" do
    # A slime walks straight at the character and comes up against the wall.
    # It has no idea the way round the end of it is there.
    it "stops at the wall rather than going round it" do
      game, creature = chase species: Species::Slime

      wait game, 20

      expect(creature.x).to be >= 5
      expect(Notice.touching? creature.at, game.player.at).to be_false
    end

    it "reaches the character when nothing is in the way" do
      game, creature = chase OPEN, species: Species::Slime, at: {8, 3}

      wait game, 20

      expect(Notice.touching? creature.at, game.player.at).to be_true
    end
  end

  describe "a hundred turns of pursuit" do
    it "finishes, and leaves every creature on a square of the floor" do
      game, creature = chase

      wait game, 100

      expect(game.turn).to eq 100
      expect(game.floor.passable? creature.x, creature.y).to be_true
      expect(game.floor.monster creature.x, creature.y).to eq creature
    end

    # The work is bounded by the descent, and the descent is bounded by its
    # own limit however much floor a band has walked.
    it "never floods more squares than the limit allows" do
      game, creature = chase

      wait game, 100
      map = Descent.toward knowledge(game, creature), game.player.at

      expect(map.steps.values.max).to be <= Descent::LIMIT
      expect(map.size).to be <= knowledge(game, creature).size + 1
    end

    it "builds one descent for a band rather than one for each creature" do
      floor = Playing.daylight Floor.parse("split", SPLIT)
      3.times { |index| floor.place Monster.new(Species::Goblin, 6 + index, 3, "band-one") }

      player = Player.new floor.id, *Game.entrance(floor), hit_points: 500
      game = Game.new World.new(SEED, {floor.id => floor}), player

      wait game, 20

      expect(game.floor.bands.size).to eq 1
      expect(game.floor.monsters.size).to eq 3
    end
  end
end
