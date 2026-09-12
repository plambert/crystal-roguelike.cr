require "../spec_helper"

Spectator.describe "items on the floor" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item

  # A one room level with the character in the middle and nothing on it.
  def bare : Roguelike::Game
    level = Roguelike::Level.parse "room", "#####\n#...#\n#.<.#\n#...#\n#####"
    level.clear_items 2, 2

    Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => level}),
      Roguelike::Player.new("room", 2, 2)
  end

  describe "Level#drop" do
    it "puts an item on a square" do
      game = bare
      game.level.drop 2, 2, Item.new(Kind::Dagger)

      expect(game.here.size).to eq 1
      expect(game.level.items?(2, 2)).to be_true
    end

    it "leaves other squares bare" do
      game = bare
      game.level.drop 2, 2, Item.new(Kind::Dagger)

      expect(game.level.items?(1, 1)).to be_false
    end

    # Two piles of the same thing on one square would be two entries to pick
    # up where a person sees one heap.
    it "joins a stack already there" do
      game = bare
      game.level.drop 2, 2, Item.new(Kind::Arrow, count: 5)
      game.level.drop 2, 2, Item.new(Kind::Arrow, count: 7)

      expect(game.here.size).to eq 1
      expect(game.here.first.count).to eq 12
    end

    it "keeps a different stack apart" do
      game = bare
      game.level.drop 2, 2, Item.new(Kind::Arrow, count: 5)
      game.level.drop 2, 2, Item.new(Kind::Arrow, 1, count: 5)

      expect(game.here.size).to eq 2
    end
  end

  describe "Game#pick_up" do
    it "takes an item off the floor and into a letter" do
      game = bare
      dagger = Item.new Kind::Dagger
      game.level.drop 2, 2, dagger

      expect(game.pick_up(dagger)).to be_true
      expect(game.here).to be_empty
      expect(game.player.inventory['a'].try &.kind).to eq Kind::Dagger
    end

    it "takes a turn" do
      game = bare
      dagger = Item.new Kind::Dagger
      game.level.drop 2, 2, dagger
      game.pick_up dagger

      expect(game.turn).to eq 1
    end

    it "says which letter it went under" do
      game = bare
      dagger = Item.new Kind::Dagger
      game.level.drop 2, 2, dagger
      game.pick_up dagger

      expect(game.log.last?).to eq "a - a dagger"
    end

    it "takes nothing that is not there" do
      game = bare

      expect(game.pick_up(Item.new(Kind::Dagger))).to be_false
      expect(game.turn).to eq 0
    end

    # Gold is counted rather than carried. It takes no letter and never fills
    # the inventory.
    it "counts gold rather than carrying it" do
      game = bare
      coins = Item.new Kind::Gold, count: 42
      game.level.drop 2, 2, coins

      expect(game.pick_up(coins)).to be_true
      expect(game.player.gold).to eq 42
      expect(game.player.inventory).to be_empty
    end

    it "adds one pile of gold to another" do
      game = bare
      first = Item.new Kind::Gold, count: 10
      game.level.drop 2, 2, first
      game.pick_up first

      second = Item.new Kind::Gold, count: 5
      game.level.drop 2, 2, second
      game.pick_up second

      expect(game.player.gold).to eq 15
    end

    it "leaves an item where it was when there is no room for it" do
      game = bare
      Roguelike::Inventory::LETTERS.size.times do
        game.player.inventory.add Item.new(Kind::LongSword)
      end

      dagger = Item.new Kind::Dagger
      game.level.drop 2, 2, dagger

      expect(game.pick_up(dagger)).to be_false
      expect(game.here.size).to eq 1
      expect(game.log.last?).to contain "cannot carry"
    end

    it "picks up everything on the square" do
      game = bare
      game.level.drop 2, 2, Item.new(Kind::Dagger)
      game.level.drop 2, 2, Item.new(Kind::LongSword)
      game.level.drop 2, 2, Item.new(Kind::Gold, count: 9)

      expect(game.pick_up_all).to eq 3
      expect(game.here).to be_empty
      expect(game.player.inventory.size).to eq 2
      expect(game.player.gold).to eq 9
    end
  end

  describe "Game#drop" do
    it "puts a carried item back on the floor" do
      game = bare
      game.player.inventory.add Item.new(Kind::Dagger)

      expect(game.drop('a')).to be_true
      expect(game.player.inventory).to be_empty
      expect(game.here.size).to eq 1
    end

    it "takes a turn and says so" do
      game = bare
      game.player.inventory.add Item.new(Kind::Dagger)
      game.drop 'a'

      expect(game.turn).to eq 1
      expect(game.log.last?).to eq "You drop a dagger."
    end

    it "drops nothing for a letter nothing is under" do
      game = bare

      expect(game.drop('z')).to be_false
      expect(game.turn).to eq 0
    end

    # Phase 11 will stop a cursed item being taken off. A character who does
    # not know it is cursed can still put it down.
    it "refuses a cursed item once the character knows" do
      game = bare
      cursed = Item.new Kind::Dagger, blessing: Roguelike::Blessing::Cursed,
        blessing_known: true
      game.player.inventory.add cursed

      expect(game.drop('a')).to be_false
      expect(game.log.last?).to contain "cannot let go"
    end

    it "lets a cursed item go while the character does not know" do
      game = bare
      cursed = Item.new Kind::Dagger, blessing: Roguelike::Blessing::Cursed
      game.player.inventory.add cursed

      expect(game.drop('a')).to be_true
    end
  end

  describe "Game#drop_gold" do
    it "puts gold on the floor" do
      game = bare
      game.player.take_gold 50

      expect(game.drop_gold(20)).to eq 20
      expect(game.player.gold).to eq 30
      expect(game.here.first.count).to eq 20
    end

    it "drops no more than the character has" do
      game = bare
      game.player.take_gold 10

      expect(game.drop_gold(50)).to eq 10
      expect(game.player.gold).to eq 0
    end

    it "drops nothing when the character has none" do
      game = bare

      expect(game.drop_gold(10)).to eq 0
      expect(game.turn).to eq 0
    end
  end

  describe "walking onto a square" do
    it "says what one thing there is" do
      game = bare
      game.level.drop 3, 2, Item.new(Kind::Dagger)
      game.step Roguelike::Direction::East

      expect(game.log.last?).to eq "You see a dagger here."
    end

    it "counts more than one" do
      game = bare
      game.level.drop 3, 2, Item.new(Kind::Dagger)
      game.level.drop 3, 2, Item.new(Kind::LongSword)
      game.step Roguelike::Direction::East

      expect(game.log.last?).to eq "There are 2 things here."
    end

    it "says nothing about a bare square" do
      game = bare
      before = game.log.size
      game.step Roguelike::Direction::East

      expect(game.log.size).to eq before
    end
  end

  describe "the level the game ships" do
    it "has items scattered on it" do
      game = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)
      piles = 0
      game.level.each_pile { |_x, _y, pile| piles += pile.size }

      expect(piles).to be > 0
    end

    it "puts them on floor and never in rock" do
      game = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)

      game.level.each_pile do |column, row, _pile|
        expect(game.level.terrain(column, row).floor?).to be_true
      end
    end

    # Placement is its own stream, so the loot does not shift when anything
    # else changes how much it rolls.
    it "scatters the same items from the same seed" do
      first = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)
      again = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)

      expect(again.level.litter).to eq first.level.litter
    end

    it "scatters different items from a different seed" do
      first = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)
      other = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED + 1)

      expect(other.level.litter).not_to eq first.level.litter
    end
  end

  describe "serialization" do
    it "keeps what is on the floor" do
      game = bare
      game.level.drop 2, 2, Item.new(Kind::Arrow, count: 7)
      again = Roguelike::Game.from_json game.to_json

      expect(again.here.size).to eq 1
      expect(again.here.first.count).to eq 7
    end

    it "keeps what is carried and the gold" do
      game = bare
      game.player.inventory.add Item.new(Kind::LongSword, 1)
      game.player.take_gold 33

      again = Roguelike::Game.from_json game.to_json

      expect(again.player.gold).to eq 33
      expect(again.player.inventory['a'].try &.enchantment).to eq 1
    end
  end
end
