require "../spec_helper"

Spectator.describe Roguelike::Explore::Circling do
  alias Action = Roguelike::Action
  alias Circling = Roguelike::Explore::Circling
  alias Event = Roguelike::Event
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Regard = Roguelike::Regard

  GROUND = Circling::Ground.new "floor", 1, 0

  # Walks *circling* round *squares* with nothing learned, one square a
  # turn from *turn* on. Each step heads for *goal*. Answers what each
  # watch found.
  def round(circling : Circling, squares : Array({Int32, Int32}), goal : {Int32, Int32},
            turn : Int32 = 0, sight : UInt64 = 0_u64) : Array(Circling::Watch)
    squares.map_with_index do |square, index|
      found = circling.watch GROUND, square, sight, turn + index
      circling.chose goal, squares[(index + 1) % squares.size]
      found
    end
  end

  PAIR = [{1, 1}, {2, 1}, {3, 1}, {2, 1}]

  describe "the watch" do
    it "finds nothing on a walk that does not come back" do
      circling = Circling.new
      found = round circling, [{1, 1}, {2, 1}, {3, 1}, {4, 1}], {9, 1}

      expect(found.uniq).to eq [Circling::Watch::Going]
      expect(circling.avoid).to be_empty
    end

    it "turns away from the goal on the first square that comes round" do
      circling = Circling.new
      found = round circling, PAIR, {9, 1}

      expect(found).to eq [Circling::Watch::Going, Circling::Watch::Going,
                           Circling::Watch::Going, Circling::Watch::Turned]
      expect(circling.avoid).to eq Set.new([{9, 1}])
      expect(circling.tries).to eq 1
    end

    it "counts a second ask on the same turn from the same square once" do
      circling = Circling.new
      circling.watch GROUND, {1, 1}, 0_u64, 5

      expect(circling.watch GROUND, {1, 1}, 0_u64, 5).to eq Circling::Watch::Going
      expect(circling.tries).to eq 0
    end

    it "gives up after it has turned away three times" do
      circling = Circling.new
      found = [] of Circling::Watch
      turn = 0
      until found.last?.try &.stuck?
        square = PAIR[turn % PAIR.size]
        found << circling.watch(GROUND, square, 0_u64, turn)
        turn += 1
        circling.chose({turn, 9}, PAIR[turn % PAIR.size]) unless found.last.stuck?
      end

      expect(found.count &.turned?).to eq Circling::TRIES
      expect(circling.stuck? GROUND, {2, 1}).to be_true
      expect(circling.watch GROUND, {2, 1}, 0_u64, turn).to eq Circling::Watch::Stuck
    end

    it "takes a square seen differently as a different square" do
      circling = Circling.new
      circling.watch GROUND, {1, 1}, 1_u64, 0
      circling.chose({9, 1}, {2, 1})
      circling.watch GROUND, {2, 1}, 1_u64, 1
      circling.chose({9, 1}, {1, 1})

      expect(circling.watch GROUND, {1, 1}, 2_u64, 2).to eq Circling::Watch::Going
    end

    it "starts again once the character learns something" do
      circling = Circling.new
      round circling, PAIR + PAIR, {9, 1}
      learned = Circling::Ground.new "floor", 2, 0

      expect(circling.watch learned, {1, 1}, 0_u64, 20).to eq Circling::Watch::Going
      expect(circling.avoid).to be_empty
      expect(circling.tries).to eq 0
    end

    it "starts again once something other than explore moves the character" do
      circling = Circling.new
      round circling, PAIR + PAIR, {9, 1}

      expect(circling.watch GROUND, {7, 7}, 0_u64, 20).to eq Circling::Watch::Going
      expect(circling.avoid).to be_empty
    end

    it "stays given up while the character stands still" do
      circling = Circling.new
      circling.give_up({1, 1})

      expect(circling.watch GROUND, {1, 1}, 0_u64, 0).to eq Circling::Watch::Going
      circling.give_up({1, 1})
      expect(circling.stuck? GROUND, {1, 1}).to be_true
      expect(circling.stuck? GROUND, {2, 1}).to be_false
    end
  end

  # A lit room 31 squares wide. Two items lie at the ends of the top row,
  # where the character starts between them, and a third lies at the
  # bottom. From the square where either end is read, the other end is
  # nearer than the bottom.
  def room(kind : ItemKind, charges : Int32? = nil) : {Game, Item, Item, Item}
    game = Playing.field 31, 34
    west = Item.new kind, charges: charges
    east = Item.new kind, charges: charges
    south = Item.new kind, charges: charges
    game.floor.drop 1, 1, west
    game.floor.drop 29, 1, east
    game.floor.drop 15, 32, south
    game.player.move_to 15, 1
    game.look
    {game, west, east, south}
  end

  # Takes explore steps until one stops or *limit* is reached. *between*
  # runs before each step. Answers the halts of the steps that stopped and
  # every square stood on.
  def explore(game : Game, limit : Int32, &between : ->) : {Array(Halt), Array({Int32, Int32})}
    halts = [] of Halt
    squares = [game.player.at]
    limit.times do
      between.call
      game.perform Action::Explore.new
      game.look
      game.events.each { |event| halts << event.halt if event.is_a?(Event::Stopped) }
      break unless halts.empty?

      squares << game.player.at
    end
    {halts, squares}
  end

  describe "explore" do
    # Seed 5023 went round between two squares from turn 5,334 on. A loaf
    # read from close by was seen again from beyond `Regards::READING` a
    # few turns older. The memory took the older loaf for a different item,
    # forgot the close look, and explore walked back to read it again.
    it "reads aging food once and does not walk back to it" do
      game, west, east, south = room ItemKind::Bread
      [west, east, south].each &.set_down
      halts, squares = explore(game, 200) do
        [west, east].each &.ripen
      end

      expect(halts).to eq [Halt::Explored]
      expect(squares.min_by &.[0]).to eq({9, 1})
      expect(squares.max_by &.[0]).to eq({21, 1})
      expect(squares.count({15, 1})).to eq 2
      expect(game.knowledge[1, 1].try &.regard).to eq Regard::Everything
      expect(game.knowledge[29, 1].try &.regard).to eq Regard::Everything
    end

    # A wand used up while nobody looks is a changed item, so a distant look
    # at it makes out only the kind. Using up the two at the ends between
    # steps makes explore go back and forth between them for ever.
    it "turns away from a circle and stops once nothing else is left" do
      game, west, east, _south = room ItemKind::LightWand, 1_000
      halts, squares = explore(game, 400) do
        [west, east].each &.spend
      end

      expect(halts).to eq [Halt::Circling]
      expect(game.log.last?).to eq "You stop. You keep coming back to the same places."
      expect(game.knowledge[15, 32].try &.regard).to eq Regard::Everything
      expect(squares.max_by &.[1]).to eq({15, 24})
      expect(game.explorable?).to be_false
      expect(game.legal.map &.class).not_to contain Action::Explore
    end

    it "tells a bot the halt as circling" do
      game, west, east, _south = room ItemKind::LightWand, 1_000
      explore(game, 400) { [west, east].each &.spend }
      stop = game.events.find(&.is_a?(Event::Stopped))

      expect(stop.to_json).to contain %("halt":"circling")
    end

    it "is offered again once the character stands somewhere else" do
      game, west, east, _south = room ItemKind::LightWand, 1_000
      explore(game, 400) { [west, east].each &.spend }
      expect(game.explorable?).to be_false

      game.player.move_to 15, 10
      expect(game.explorable?).to be_true
    end
  end
end
