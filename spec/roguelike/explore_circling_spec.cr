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
            turn : Int32 = 0, sight : Int64 = 0_i64) : Array(Circling::Watch)
    squares.map_with_index do |square, index|
      found = circling.watch GROUND, square, sight, turn + index
      circling.chose goal, squares[(index + 1) % squares.size]
      found
    end
  end

  PAIR = [{1, 1}, {2, 1}, {3, 1}, {2, 1}]

  # FNV-1a over 1, 1, 2, 0, 1 as four bytes each, worked out outside the game.
  SIGHT = -6_493_152_605_587_415_690_i64

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
      circling.watch GROUND, {1, 1}, 0_i64, 5

      expect(circling.watch GROUND, {1, 1}, 0_i64, 5).to eq Circling::Watch::Going
      expect(circling.tries).to eq 0
    end

    it "gives up after it has turned away three times" do
      circling = Circling.new
      found = [] of Circling::Watch
      turn = 0
      until found.last?.try &.stuck?
        square = PAIR[turn % PAIR.size]
        found << circling.watch(GROUND, square, 0_i64, turn)
        turn += 1
        circling.chose({turn, 9}, PAIR[turn % PAIR.size]) unless found.last.stuck?
      end

      expect(found.count &.turned?).to eq Circling::TRIES
      expect(circling.stuck? GROUND, {2, 1}).to be_true
      expect(circling.watch GROUND, {2, 1}, 0_i64, turn).to eq Circling::Watch::Stuck
    end

    it "takes a square seen differently as a different square" do
      circling = Circling.new
      circling.watch GROUND, {1, 1}, 1_i64, 0
      circling.chose({9, 1}, {2, 1})
      circling.watch GROUND, {2, 1}, 1_i64, 1
      circling.chose({9, 1}, {1, 1})

      expect(circling.watch GROUND, {1, 1}, 2_i64, 2).to eq Circling::Watch::Going
    end

    it "starts again once the character learns something" do
      circling = Circling.new
      round circling, PAIR + PAIR, {9, 1}
      learned = Circling::Ground.new "floor", 2, 0

      expect(circling.watch learned, {1, 1}, 0_i64, 20).to eq Circling::Watch::Going
      expect(circling.avoid).to be_empty
      expect(circling.tries).to eq 0
    end

    it "starts again once something other than explore moves the character" do
      circling = Circling.new
      round circling, PAIR + PAIR, {9, 1}

      expect(circling.watch GROUND, {7, 7}, 0_i64, 20).to eq Circling::Watch::Going
      expect(circling.avoid).to be_empty
    end

    it "numbers a sight the same way in every process" do
      none = [] of {Int32, Int32}

      expect(Circling.sight [{1, 2}], none, true).to eq SIGHT
      expect(Circling.sight none, [{1, 2}], true).not_to eq SIGHT
      expect(Circling.sight [{1, 2}], none, false).not_to eq SIGHT
    end

    it "stays given up while the character stands still" do
      circling = Circling.new
      circling.give_up({1, 1})

      expect(circling.watch GROUND, {1, 1}, 0_i64, 0).to eq Circling::Watch::Going
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
      expect(game.knowledge[1, 1].try &.items.first?.try &.regard).to eq Regard::Everything
      expect(game.knowledge[29, 1].try &.items.first?.try &.regard).to eq Regard::Everything
    end

    # A wand used up while nobody looks keeps its id, so the close look at
    # it stands. Explore reads each wand once and runs out of places to go.
    it "reads wands used up out of sight once and finishes" do
      game, west, east, _south = room ItemKind::LightWand, 1_000
      halts, squares = explore(game, 400) do
        [west, east].each &.spend
      end

      expect(halts).to eq [Halt::Explored]
      expect(game.knowledge[15, 32].try &.items.first?.try &.regard).to eq Regard::Everything
      expect(squares.max_of &.[1]).to eq 32 - Roguelike::Regards::READING
      expect(game.explorable?).to be_false
    end

    # A look that changes nothing it remembers leaves the revision alone,
    # and reading a pile up close moves it. No pile can make explore go
    # round, so these give the game a watch that has already given up.
    def given_up(game : Game) : Game
      saved = JSON.parse(game.to_json).as_h
      moves = saved["pack_moves"]?.try(&.as_i) || 0
      ground = Circling::Ground.new game.floor.id, game.knowledge.revision, moves
      watch = Circling.new
      watch.watch ground, game.player.at, 0_i64, game.turn
      watch.give_up game.player.at
      saved["circling"] = JSON.parse(watch.to_json)
      Game.from_json saved.to_json
    end

    it "stops with circling where the watch has given up" do
      game, _west, _east, _south = room ItemKind::LightWand, 1_000
      game = given_up game

      expect(game.explorable?).to be_false
      game.perform Action::Explore.new
      stop = game.events.find(&.is_a?(Event::Stopped))

      expect(game.log.last?).to eq "You stop. You keep coming back to the same places."
      expect(stop.to_json).to contain %("halt":"circling")
      expect(game.legal.map &.class).not_to contain Action::Explore
    end

    it "is offered again once the character stands somewhere else" do
      game, _west, _east, _south = room ItemKind::LightWand, 1_000
      game = given_up game
      expect(game.explorable?).to be_false

      game.player.move_to 15, 10
      expect(game.explorable?).to be_true
    end
  end

  # How far *watch* has got, read from what a save holds.
  def stage(watch : Circling) : String
    saved = JSON.parse watch.to_json
    return "stuck" if saved["stuck"]?.try(&.raw)

    "tries #{saved["tries"]}"
  end

  # How far the watch in *game* has got, read from what a save holds.
  def stage(game : Game) : String
    watch = JSON.parse(game.to_json)["circling"]?
    return "none" unless watch
    return "stuck" if watch["stuck"]?.try(&.raw)

    "tries #{watch["tries"]}"
  end

  describe "a save" do
    def holding(watch : Circling) : Game
      game, _west, _east, _south = room ItemKind::LightWand
      saved = JSON.parse(game.to_json).as_h
      saved["circling"] = JSON.parse(watch.to_json)
      saved["pack_moves"] = JSON::Any.new(3_i64)
      Game.from_json saved.to_json
    end

    it "holds the watch and the pack count, and not in the fingerprint" do
      watch = Circling.new
      round watch, PAIR, {9, 1}
      game = holding watch
      saved = JSON.parse game.to_json

      expect(saved["circling"]?).not_to be_nil
      expect(saved["pack_moves"]?).not_to be_nil
      expect(Roguelike::Fingerprint::UNCOUNTED).to contain "circling", "pack_moves"
    end

    it "loads one written without the watch with a fresh watch" do
      watch = Circling.new
      round watch, PAIR, {9, 1}
      saved = JSON.parse(holding(watch).to_json).as_h
      saved.delete "circling"
      saved.delete "pack_moves"
      loaded = Game.from_json saved.to_json

      expect(stage loaded).to eq "none"
      expect(loaded.explorable?).to be_true
    end

    it "carries the watch at every stage through a save and a load" do
      watch = Circling.new
      stages = [] of String
      turn = 0
      until stage(watch) == "stuck"
        square = PAIR[turn % PAIR.size]
        watch.watch GROUND, square, 0_i64, turn
        turn += 1
        watch.chose({turn, 9}, PAIR[turn % PAIR.size])
        stages << stage(watch)

        game = holding watch
        loaded = Game.from_json game.to_json
        expect(stage loaded).to eq stage(watch)
        expect(loaded.fingerprint).to eq game.fingerprint
        expect(JSON.parse(loaded.to_json)["circling"]).to eq JSON.parse(watch.to_json)
      end

      expect(stages.uniq).to eq ["tries 0", "tries 1", "tries 2", "tries 3", "stuck"]
    end
  end
end
