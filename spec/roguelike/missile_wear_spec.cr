require "../spec_helper"

Spectator.describe "missiles wearing out" do
  alias Condition = Roguelike::Condition
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Player = Roguelike::Player
  alias World = Roguelike::World

  # One lit hall with the character at the west end.
  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  # Where a shot east stops, against the end wall.
  EAST = {10, 1}

  # How many shots each example takes. Enough that the seed rolls both ways.
  SHOTS = 100

  # A game with the character at the west end, holding *held*.
  def armed(held : Array(Item)) : Game
    floor = Playing.daylight Floor.parse("hall", HALL)
    player = Player.new floor.id, 1, 1, hit_points: 500
    game = Game.new World.new(Playing::SEED, {floor.id => floor}), player
    held.each { |item| player.inventory.add item }
    game
  end

  # A game that has fired *count* of *ammunition* from *weapon* at the wall.
  def fired(weapon : Kind, ammunition : Item) : Game
    game = armed [Item.new(weapon), ammunition]
    game.wield 'a'
    game.wield 'b'
    ammunition.count.times { game.fire EAST }
    game
  end

  # The pieces lying where the shots stopped, by condition.
  def landed(game : Game) : Hash(Condition, Int32)
    found = Hash(Condition, Int32).new 0
    game.floor.items(*EAST).each { |item| found[item.condition] += item.count }
    found
  end

  describe "a sound arrow" do
    it "can come down damaged" do
      game = fired Kind::Bow, Item.new(Kind::Arrow, count: SHOTS)
      lying = landed game

      expect(lying[Condition::Damaged]).to be > 0
      expect(lying[Condition::Plain]).to be > 0
    end

    it "never breaks" do
      game = fired Kind::Bow, Item.new(Kind::Arrow, count: SHOTS)

      expect(landed(game).values.sum).to eq SHOTS
      expect(game.log.lines.none? &.ends_with?("breaks.")).to be_true
    end
  end

  describe "a damaged arrow" do
    it "can break, and the character is told" do
      game = fired Kind::Bow, Item.new(Kind::Arrow, condition: Condition::Damaged, count: SHOTS)
      lying = landed(game)[Condition::Damaged]

      expect(lying).to be < SHOTS
      expect(game.log.lines.any? &.starts_with?("The damaged arrow breaks.")).to be_true
    end
  end

  describe "a dart" do
    it "can come down damaged when thrown" do
      game = armed [Item.new(Kind::Dart, count: SHOTS)]
      SHOTS.times { game.throw 'a', EAST }

      expect(landed(game)[Condition::Damaged]).to be > 0
    end
  end

  describe "a stone" do
    it "never wears" do
      game = fired Kind::Sling, Item.new(Kind::Stone, count: SHOTS)

      expect(landed(game)).to eq({Condition::Plain => SHOTS})
      expect(game.wears).to eq 0
    end

    it "is never damaged when it starts damaged" do
      game = fired Kind::Sling, Item.new(Kind::Stone, condition: Condition::Damaged, count: SHOTS)

      expect(landed(game)).to eq({Condition::Damaged => SHOTS})
    end
  end

  describe "a rock" do
    it "never wears" do
      game = armed [Item.new(Kind::Rock, count: SHOTS)]
      SHOTS.times { game.throw 'a', EAST }

      expect(landed(game)).to eq({Condition::Plain => SHOTS})
    end
  end

  describe "a damaged arrow and a sound one" do
    it "do not stack" do
      sound = Item.new Kind::Arrow
      damaged = Item.new Kind::Arrow, condition: Condition::Damaged

      expect(sound.stacks_with?(damaged)).to be_false
      expect(sound.looks_like?(damaged)).to be_false
    end

    it "take two letters in the pack" do
      game = armed [Item.new(Kind::Arrow, count: 3),
                    Item.new(Kind::Arrow, condition: Condition::Damaged, count: 2)]

      expect(game.player.inventory.size).to eq 2
      expect(game.player.inventory.count('a')).to eq 3
      expect(game.player.inventory.count('b')).to eq 2
    end
  end

  describe "the name" do
    it "says one arrow is damaged" do
      game = armed [] of Item

      expect(game.name Item.new(Kind::Arrow, condition: Condition::Damaged)).to eq "a damaged arrow"
    end

    it "says a stack is damaged" do
      game = armed [] of Item
      arrows = Item.new Kind::Arrow, 1, condition: Condition::Damaged, count: 12

      expect(game.name arrows).to eq "12 damaged +1 arrows"
    end
  end

  describe "a save" do
    it "keeps a damaged arrow damaged" do
      arrow = Item.new Kind::Arrow, condition: Condition::Damaged, count: 4

      expect(Item.from_json(arrow.to_json).condition).to eq Condition::Damaged
    end

    it "keeps how many missiles have worn" do
      game = fired Kind::Bow, Item.new(Kind::Arrow, count: 3)
      again = Game.from_json game.to_json

      expect(again.wears).to eq 3
    end

    it "writes no wear count before the first shot" do
      expect(armed([] of Item).to_json).not_to contain %("wears")
    end
  end

  describe "refilling the quiver" do
    it "passes over a damaged stack for a sound one" do
      game = armed [Item.new(Kind::Bow), Item.new(Kind::Arrow),
                    Item.new(Kind::Arrow, condition: Condition::Damaged, count: 20),
                    Item.new(Kind::Arrow, count: 5)]
      game.wield 'a'
      game.wield 'b'
      game.fire EAST

      expect(game.player.quivered.try &.condition).to eq Condition::Plain
      expect(game.player.quivered.try &.count).to eq 5
    end

    it "takes a damaged stack when nothing else is left" do
      game = armed [Item.new(Kind::Bow), Item.new(Kind::Arrow),
                    Item.new(Kind::Arrow, condition: Condition::Damaged, count: 20)]
      game.wield 'a'
      game.wield 'b'
      game.fire EAST

      expect(game.player.quivered.try &.condition).to eq Condition::Damaged
    end
  end
end
