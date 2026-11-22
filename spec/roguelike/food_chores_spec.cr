require "../spec_helper"

Spectator.describe "the food bag's batch chores" do
  alias Action = Roguelike::Action
  alias Floor = Roguelike::Floor
  alias Food = Roguelike::Food
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  HALL = ["######################",
          "#....................#",
          "#..<.................#",
          "#....................#",
          "######################"]

  # A hall split by a wall, with the way round it along the bottom. A
  # creature east of the wall has to walk round to be seen.
  SPLIT = ["############",
           "#.....#....#",
           "#..<..#....#",
           "#.....#....#",
           "#..........#",
           "############"]

  def game_on(lines : Array(String), bag : Array(Item), lit : Bool = true,
              hunger : Int32 = 2000) : Game
    floor = Floor.parse "here", lines.join('\n')
    Playing.daylight floor if lit
    player = Player.new "here", 3, 2
    player.sustenance.hunger = hunger
    bag.each { |item| player.food_bag.add item }
    game = Game.new World.new(Playing::SEED, {"here" => floor}), player, turn: 100
    game.enroll
    game.look
    game
  end

  def keeps(kind : ItemKind) : Int32
    Food.facts(kind).keeps
  end

  def food(kind : ItemKind, age : Int32 = 0) : Item
    Item.new kind, blessing_known: true, age: age
  end

  # *count* stacks of berries, each *left* turns or less from going stale.
  # Each is a turn older than the one before, so none of them stack.
  def turning(count : Int32, left : Int32 = 50) : Array(Item)
    (0...count).map { |index| food ItemKind::Berries, keeps(ItemKind::Berries) - left + index }
  end

  # *count* stacks of rotten berries that do not stack.
  def rotting(count : Int32) : Array(Item)
    (0...count).map { |index| food ItemKind::Berries, keeps(ItemKind::Berries) * 2 + index }
  end

  # Tells the band of *found* where the character is, so it comes for them.
  def hunting(game : Game, found : Monster) : Nil
    band = game.floor.band found.band
    raise "the floor has lost the band" unless band

    knowledge = band.knowledge game.floor.id
    game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
    knowledge.saw Roguelike::Knowledge::PLAYER, game.player.x, game.player.y, game.turn
    band.awareness = Roguelike::Awareness::Hunting
  end

  def creature(game : Game, at : {Int32, Int32}) : Monster
    found = Monster.new Species::Goblin, at[0], at[1], "band-one"
    game.floor.place found
    found
  end

  describe "the food about to turn" do
    it "holds food within an hour of turning, soonest first" do
      soon = food ItemKind::Bread, keeps(ItemKind::Bread) - 300
      sooner = food ItemKind::Berries, keeps(ItemKind::Berries) - 10
      later = food ItemKind::Apple, keeps(ItemKind::Apple) - Food::TURNING_SOON - 1
      rotten = food ItemKind::Herbs, keeps(ItemKind::Herbs) * 3 - 5
      game = game_on HALL, [soon, later, rotten, sooner, food(ItemKind::Ration)]

      expect(game.turning_soon.map &.kind).to eq [ItemKind::Berries, ItemKind::Bread]
    end
  end

  describe "eating it" do
    it "eats every food about to turn, soonest first, a turn each" do
      bread = food ItemKind::Bread, keeps(ItemKind::Bread) - 100
      berries = food ItemKind::Berries, keeps(ItemKind::Berries) - 10
      apple = food ItemKind::Apple
      game = game_on HALL, [bread, apple, berries]

      expect(game.eat_turning).to be_nil
      eaten = game.log.lines.select &.starts_with?("You eat")
      expect(eaten.size).to eq 2
      expect(eaten.first).to contain "berries"
      expect(eaten.last).to contain "bread"
      expect(game.player.food_bag.items.map &.kind).to eq [ItemKind::Apple]
      expect(game.turn).to eq 102
    end

    it "stops once the character is full" do
      game = game_on HALL, turning(4), hunger: 300

      expect(game.eat_turning).to be_nil
      expect(game.log.lines.reverse_each.find(&.starts_with?("You eat"))).to contain "are full"
      expect(game.log.lines.count &.starts_with?("You eat")).to eq 2
      expect(game.player.food_bag.size).to eq 3
      expect(game.turn).to eq 102
    end

    it "is refused once when full from the start" do
      game = game_on HALL, turning(2), hunger: 0

      game.eat_turning

      expect(game.log.last?).to eq "You are too full to eat."
      expect(game.turn).to eq 100
      expect(game.player.food_bag.size).to eq 2
    end

    it "stops when the character is hurt" do
      game = game_on HALL, turning(12), lit: false, hunger: 9000
      hunting game, creature(game, {4, 2})

      halt = game.eat_turning

      expect([Halt::Hurt, Halt::Over]).to contain halt
      expect(game.player.food_bag.size).to be > 0
    end
  end

  describe "dropping the rot" do
    it "drops every rotten food and putrid mass, a turn each" do
      bag = rotting(2) << food(ItemKind::Ration)
      game = game_on HALL, bag
      game.player.inventory.add Item.new(ItemKind::PutridMass, count: 2, blessing_known: true)
      game.enroll

      expect(game.drop_all_rot).to be_nil
      expect(game.player.food_bag.items.map &.kind).to eq [ItemKind::Ration]
      expect(game.player.inventory.empty?).to be_true
      expect(game.turn).to eq 103
    end

    it "drops with the setting off and a creature in sight" do
      game = game_on HALL, rotting(2)
      game.perform Action::Configure.new(Roguelike::Explore::Settings.parse "drop_rot=off")
      creature game, {18, 2}

      expect(game.drop_all_rot).to be_nil
      expect(game.player.food_bag.empty?).to be_true
    end

    it "stops when a creature comes into view" do
      game = game_on SPLIT, rotting(15)
      hunting game, creature(game, {9, 2})

      halt = game.drop_all_rot

      expect(halt).to eq Halt::Creature
      expect(game.monsters_in_sight).not_to be_empty
      expect(game.player.food_bag.size).to be > 0
      expect(game.log.last?).to contain "comes into view"
    end
  end
end
