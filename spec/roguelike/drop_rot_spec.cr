require "../spec_helper"
require "../support/recording"

Spectator.describe "dropping rot when safe" do
  alias Action = Roguelike::Action
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Food = Roguelike::Food
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Settings = Roguelike::Explore::Settings
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  HALL = ["######################",
          "#....................#",
          "#..<.................#",
          "#....................#",
          "######################"]

  # A corridor that runs east out of sight, so an explore has far to go.
  CORRIDOR = [
    "#########################",
    "#.......................#",
    "########.################",
    "########.################",
    "########<################",
    "#########################",
  ]

  # A turn long past any fight, so a game that starts here is safe.
  LATER = 100

  def game_on(lines : Array(String), bag : Array(Item) = [] of Item,
              pack : Array(Item) = [] of Item) : Game
    floor = Playing.daylight Floor.parse("here", lines.join('\n'))
    player = Player.new "here", *Game.entrance(floor)
    bag.each { |item| player.food_bag.add item }
    pack.each { |item| player.inventory.add item }
    game = Game.new World.new(Playing::SEED, {"here" => floor}), player, turn: LATER
    game.enroll
    game.look
    game
  end

  def rotten(kind : ItemKind = ItemKind::Berries) : Item
    Item.new kind, blessing_known: true, age: Food.facts(kind).keeps * 2
  end

  def masses(count : Int32 = 3) : Item
    Item.new ItemKind::PutridMass, count: count, blessing_known: true
  end

  def creature(game : Game, at : {Int32, Int32}) : Monster
    found = Monster.new Species::Goblin, at[0], at[1], "band-one"
    game.floor.place found
    found
  end

  def kinds_here(game : Game) : Array(ItemKind)
    game.here.map &.kind
  end

  describe "on a wait" do
    it "drops rotten food from the bag, taking the turn" do
      game = game_on HALL, [rotten, Item.new(ItemKind::Ration, blessing_known: true)]
      game.perform Action::Wait.new

      expect(game.turn).to eq LATER + 1
      expect(game.player.food_bag.items.map &.kind).to eq [ItemKind::Ration]
      expect(kinds_here game).to eq [ItemKind::Berries]
      expect(game.log.last?).to eq "You drop a rotten handful of berries."
      expect(game.events.any? Event::Dropped).to be_true
      expect(game.events.any? Event::Waited).to be_false
    end

    it "drops nothing with a creature in sight" do
      game = game_on HALL, [rotten]
      creature game, {18, 2}
      game.perform Action::Wait.new

      expect(game.player.food_bag.size).to eq 1
      expect(kinds_here game).to be_empty
      expect(game.events.any? Event::Waited).to be_true
    end

    it "drops nothing right after a fight, and drops once it is past" do
      game = game_on HALL, [rotten]
      foe = creature game, {game.player.x + 1, game.player.y}
      game.attack foe
      game.floor.remove foe.x, foe.y

      waited = 0
      while game.turn < game.fought_turn + Game::FIGHT_LASTS
        expect(game.unthreatened?).to be_false
        game.perform Action::Wait.new
        waited += 1
        expect(game.player.food_bag.size).to eq 1
      end

      game.perform Action::Wait.new
      expect(waited).to be > 0
      expect(game.player.food_bag.empty?).to be_true
    end

    it "drops one stack a turn, the pack first" do
      game = game_on HALL, [rotten], [masses]
      game.perform Action::Wait.new

      expect(kinds_here game).to eq [ItemKind::PutridMass]
      expect(game.player.food_bag.size).to eq 1

      game.perform Action::Wait.new
      expect(game.player.food_bag.empty?).to be_true
      expect(game.player.inventory.empty?).to be_true
      expect(game.turn).to eq LATER + 2
    end

    it "drops nothing with the option off" do
      game = game_on HALL, [rotten], [masses]
      game.perform Action::Configure.new(Settings.parse "drop_rot=off")
      game.perform Action::Wait.new

      expect(game.player.food_bag.size).to eq 1
      expect(game.player.inventory.empty?).to be_false
      expect(kinds_here game).to be_empty
    end

    it "leaves fresh and stale food alone" do
      stale = Item.new ItemKind::Apple, blessing_known: true, age: Food.facts(ItemKind::Apple).keeps
      game = game_on HALL, [stale]
      game.perform Action::Wait.new

      expect(game.player.food_bag.size).to eq 1
    end

    it "goes on resting past the line" do
      game = game_on HALL, [rotten]
      game.player.hurt hp(6)
      rest = game.rest

      expect(game.player.food_bag.empty?).to be_true
      expect(rest.turns).to be > 1
      expect(rest.halt).to eq Roguelike::Halt::Healed
    end
  end

  describe "on an explore" do
    it "spends a step dropping and then walks on" do
      game = game_on CORRIDOR, [rotten]
      start = game.player.at

      game.perform Action::Explore.new
      expect(game.player.at).to eq start
      expect(game.player.food_bag.empty?).to be_true
      expect(game.turn).to eq LATER + 1

      game.perform Action::Explore.new
      expect(game.player.at).not_to eq start
    end

    it "does not stop the walk for the line" do
      game = game_on CORRIDOR, [rotten], [masses]
      start = game.player.at

      walk = game.explore
      expect(game.player.food_bag.empty?).to be_true
      expect(game.player.inventory.empty?).to be_true
      expect(walk.steps).to be > 0
      expect(game.player.at).not_to eq start
      expect(walk.halt).not_to eq Roguelike::Halt::Told
    end

    it "walks on from the square it dropped on" do
      game = game_on CORRIDOR, [rotten, rotten(ItemKind::Apple)]

      walk = game.explore

      expect(game.player.food_bag.empty?).to be_true
      expect(walk.halt).not_to eq Roguelike::Halt::Spent
    end

    it "walks without dropping with the option off" do
      game = game_on CORRIDOR, [rotten]
      game.perform Action::Configure.new(Settings.parse "drop_rot=off")
      start = game.player.at

      game.perform Action::Explore.new
      expect(game.player.at).not_to eq start
      expect(game.player.food_bag.size).to eq 1
    end
  end

  describe "the setting" do
    it "is on by default and left out of a save while on" do
      settings = Settings.new

      expect(settings.drop_rot?).to be_true
      expect(settings.to_json).not_to contain "drop_rot"
      expect(Settings.from_json(settings.to_json).drop_rot?).to be_true
    end

    it "is written and read back when off" do
      settings = Settings.parse "drop_rot=off"

      expect(settings.to_json).to contain %("drop_rot":false)
      expect(Settings.from_json(settings.to_json).drop_rot?).to be_false
      expect(settings.default?).to be_false
    end
  end

  describe "a replay" do
    # Records waits and explore steps on a game holding rot, with the option
    # set to *on*. Answers the file and the game.
    def recorded(on : Bool) : {String, Game}
      where = (Recording.directory / "rot-#{on}-#{Random.rand UInt32}.jsonl").to_s

      played = Recording.recording where do
        game = game_on CORRIDOR, [rotten], [masses]
        game.player.name = "dropper"
        game.perform Action::Configure.new(Settings.parse "drop_rot=off") unless on
        2.times { game.perform Action::Wait.new }
        3.times { game.perform Action::Explore.new }
        game
      end

      {where, played}
    end

    it "plays the same with the option on" do
      where, game = recorded on: true

      expect(game.player.food_bag.empty?).to be_true
      expect(Roguelike::Replay::Verifier.check(where).trouble).to be_nil
    end

    it "plays the same with the option off" do
      where, game = recorded on: false

      expect(game.player.food_bag.size).to eq 1
      expect(Roguelike::Replay::Verifier.check(where).trouble).to be_nil
    end
  end
end
