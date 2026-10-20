require "../spec_helper"

Spectator.describe "items on the floor" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item

  # A one room floor with the character in the middle and nothing on it.
  def bare : Roguelike::Game
    floor = Roguelike::Floor.parse "room", "#####\n#...#\n#.<.#\n#...#\n#####"
    floor.clear_items 2, 2

    Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}),
      Roguelike::Player.new("room", 2, 2)
  end

  describe "Floor#drop" do
    it "puts an item on a square" do
      game = bare
      game.floor.drop 2, 2, Item.new(Kind::Dagger)

      expect(game.here.size).to eq 1
      expect(game.floor.items?(2, 2)).to be_true
    end

    it "leaves other squares bare" do
      game = bare
      game.floor.drop 2, 2, Item.new(Kind::Dagger)

      expect(game.floor.items?(1, 1)).to be_false
    end

    # Two piles of the same thing on one square would be two entries to pick
    # up where a person sees one heap.
    it "joins a stack already there" do
      game = bare
      game.floor.drop 2, 2, Item.new(Kind::Arrow, count: 5)
      game.floor.drop 2, 2, Item.new(Kind::Arrow, count: 7)

      expect(game.here.size).to eq 1
      expect(game.here.first.count).to eq 12
    end

    it "marks a joined stack as put down when the part dropped on it was" do
      game = bare
      game.floor.drop 2, 2, Item.new(Kind::Arrow, count: 5)
      dropped = Item.new Kind::Arrow, count: 7
      dropped.set_down
      game.floor.drop 2, 2, dropped

      expect(game.here.size).to eq 1
      expect(game.here.first.dropped?).to be_true
    end

    it "keeps a different stack apart" do
      game = bare
      game.floor.drop 2, 2, Item.new(Kind::Arrow, count: 5)
      game.floor.drop 2, 2, Item.new(Kind::Arrow, 1, count: 5)

      expect(game.here.size).to eq 2
    end
  end

  describe "Game#pick_up" do
    it "takes an item off the floor and into a letter" do
      game = bare
      dagger = Item.new Kind::Dagger
      game.floor.drop 2, 2, dagger

      expect(game.pick_up(dagger)).to be_true
      expect(game.here).to be_empty
      expect(game.player.inventory['a'].try &.kind).to eq Kind::Dagger
    end

    it "takes a turn" do
      game = bare
      dagger = Item.new Kind::Dagger
      game.floor.drop 2, 2, dagger
      game.pick_up dagger

      expect(game.turn).to eq 1
    end

    it "says which letter it went under" do
      game = bare
      dagger = Item.new Kind::Dagger
      game.floor.drop 2, 2, dagger
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
      game.floor.drop 2, 2, coins

      expect(game.pick_up(coins)).to be_true
      expect(game.player.gold).to eq 42
      expect(game.player.inventory).to be_empty
    end

    it "adds one pile of gold to another" do
      game = bare
      first = Item.new Kind::Gold, count: 10
      game.floor.drop 2, 2, first
      game.pick_up first

      second = Item.new Kind::Gold, count: 5
      game.floor.drop 2, 2, second
      game.pick_up second

      expect(game.player.gold).to eq 15
    end

    it "leaves an item where it was when there is no room for it" do
      game = bare
      Roguelike::Inventory::LETTERS.size.times do
        game.player.inventory.add Item.new(Kind::LongSword)
      end

      dagger = Item.new Kind::Dagger
      game.floor.drop 2, 2, dagger

      expect(game.pick_up(dagger)).to be_false
      expect(game.here.size).to eq 1
      expect(game.log.last?).to contain "cannot carry"
    end

    it "picks up everything on the square" do
      game = bare
      game.floor.drop 2, 2, Item.new(Kind::Dagger)
      game.floor.drop 2, 2, Item.new(Kind::LongSword)
      game.floor.drop 2, 2, Item.new(Kind::Gold, count: 9)

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

    it "marks what it puts down" do
      game = bare
      game.player.inventory.add Item.new(Kind::Dagger)
      game.drop 'a'

      expect(game.here.first.dropped?).to be_true
    end

    it "lets a pickup by hand clear the mark" do
      game = bare
      game.player.inventory.add Item.new(Kind::Dagger)
      game.drop 'a'
      game.pick_up game.here.first

      expect(game.player.inventory['a'].try &.dropped?).to eq false
    end

    it "drops nothing for a letter nothing is under" do
      game = bare

      expect(game.drop('z')).to be_false
      expect(game.turn).to eq 0
    end

    # A curse holds what is in a slot and nothing else. A cursed dagger at
    # the bottom of the pack goes on the floor like any other.
    it "lets a cursed item go while it is only carried" do
      game = bare
      cursed = Item.new Kind::Dagger, blessing: Roguelike::Blessing::Cursed,
        blessing_known: true
      game.player.inventory.add cursed

      expect(game.drop('a')).to be_true
    end

    it "refuses a cursed item that is wielded" do
      game = bare
      cursed = Item.new Kind::Dagger, blessing: Roguelike::Blessing::Cursed,
        blessing_known: true
      game.player.inventory.add cursed
      game.wield 'a'

      expect(game.drop('a')).to be_false
      expect(game.log.last?).to contain "take"
    end
  end

  describe "gold underfoot" do
    alias Direction = Roguelike::Direction

    # Nobody walks over coins and leaves them, and asking would be a
    # keystroke for every pile.
    it "goes into the purse on the step onto the square" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Gold, count: 12)

      game.step Direction::East

      expect(game.player.gold).to eq 12
      expect(game.floor.items?(3, 2)).to be_false
    end

    it "leaves coins the character put down" do
      game = bare
      game.player.take_gold 12
      game.drop_gold 5

      game.step Direction::East
      game.step Direction::West

      expect(game.player.gold).to eq 7
      expect(game.here.first.count).to eq 5
    end

    it "costs no turn of its own" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Gold, count: 12)

      game.step Direction::East

      expect(game.turn).to eq 1
    end

    it "says how much was taken" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Gold, count: 12)

      game.step Direction::East

      expect(game.log.lines.any? &.includes?("12 gold pieces")).to be_true
    end

    it "counts one coin as one piece" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Gold, count: 1)

      game.step Direction::East

      expect(game.log.lines.any? &.includes?("1 gold piece.")).to be_true
    end

    it "leaves everything else where it is" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Gold, count: 12)
      game.floor.drop 3, 2, Item.new(Kind::Dagger)

      game.step Direction::East

      expect(game.player.gold).to eq 12
      expect(game.here.map &.kind).to eq [Kind::Dagger]
    end

    it "says nothing on a square with no gold on it" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Dagger)

      game.step Direction::East

      expect(game.log.lines.any? &.includes?("gold")).to be_false
    end
  end

  describe "ammunition underfoot" do
    alias Direction = Roguelike::Direction
    alias Slot = Roguelike::Slot

    # A game with *quivered* readied, and *lying* on the square to the east.
    def shooting(quivered : Item, lying : Array(Item)) : Roguelike::Game
      game = bare
      letter = game.player.inventory.add quivered
      raise "no room" unless letter
      game.player.equipment.put Slot::Quiver, letter
      lying.each { |item| game.floor.drop 3, 2, item }
      game
    end

    it "goes into the quiver on the step onto the square" do
      game = shooting Item.new(Kind::Arrow, count: 5),
        [Item.new(Kind::Arrow, count: 3)]

      game.step Direction::East

      expect(game.player.quivered.try &.count).to eq 8
      expect(game.floor.items?(3, 2)).to be_false
    end

    it "costs a turn of its own" do
      game = shooting Item.new(Kind::Arrow, count: 5),
        [Item.new(Kind::Arrow, count: 3)]

      game.step Direction::East

      expect(game.turn).to eq 2
    end

    it "says what was taken" do
      game = shooting Item.new(Kind::Arrow, count: 5),
        [Item.new(Kind::Arrow, count: 3)]

      game.step Direction::East

      expect(game.log.lines.any? &.includes?("You pick up 3 arrows.")).to be_true
    end

    # A `+1` arrow reads differently in the pack, and taking it would put it
    # under a letter the character never asked for.
    it "leaves ammunition that looks different" do
      game = shooting Item.new(Kind::Arrow, count: 5),
        [Item.new(Kind::Arrow, count: 2, enchantment: 1)]

      game.step Direction::East

      expect(game.player.quivered.try &.count).to eq 5
      expect(game.here.size).to eq 1
    end

    it "leaves what the quiver does not fire" do
      game = shooting Item.new(Kind::Arrow, count: 5),
        [Item.new(Kind::Stone, count: 4), Item.new(Kind::Dagger)]

      game.step Direction::East

      expect(game.player.quivered.try &.count).to eq 5
      expect(game.here.size).to eq 2
    end

    it "leaves everything where it is with an empty quiver" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Arrow, count: 3)

      game.step Direction::East

      expect(game.here.size).to eq 1
    end
  end

  describe "stacks underfoot" do
    alias Blessing = Roguelike::Blessing
    alias Condition = Roguelike::Condition
    alias Direction = Roguelike::Direction

    # A game with *held* in the pack and *lying* on the square to the east.
    def carrying(held : Array(Item), lying : Array(Item)) : Roguelike::Game
      game = bare
      held.each { |item| game.player.inventory.add(item) || raise "no room" }
      lying.each { |item| game.floor.drop 3, 2, item }
      game
    end

    def arrows(count : Int32, blessing : Blessing? = nil, *,
               enchantment : Int32 = 0,
               condition : Condition = Condition::Plain) : Item
      Item.new Kind::Arrow, enchantment, condition, count: count,
        blessing: blessing || Blessing::Uncursed, blessing_known: !blessing.nil?
    end

    # Some of the blessed arrows in the pack might be among the unknown ones.
    it "takes unknown arrows when the pack holds blessed ones" do
      game = carrying [arrows(8, Blessing::Blessed)], [arrows(3)]

      game.step Direction::East

      expect(game.here).to be_empty
      expect(game.log.lines).to contain "You pick up 3 arrows."
    end

    it "takes blessed arrows when the pack holds unknown ones" do
      game = carrying [arrows(8)], [arrows(3, Blessing::Blessed)]

      game.step Direction::East

      expect(game.here).to be_empty
    end

    it "takes nothing on the strength of a cursed stack" do
      game = carrying [arrows(2, Blessing::Cursed)], [arrows(2)]

      game.step Direction::East

      expect(game.here.size).to eq 1
    end

    it "leaves cursed arrows where they lie" do
      game = carrying [arrows(8)], [arrows(2, Blessing::Cursed)]

      game.step Direction::East

      expect(game.here.size).to eq 1
    end

    it "takes unknown arrows beside a cursed stack when plain ones are held too" do
      game = carrying [arrows(2, Blessing::Cursed), arrows(2, Blessing::Uncursed)],
        [arrows(2), arrows(2, Blessing::Cursed)]

      game.step Direction::East

      expect(game.here.size).to eq 1
      expect(game.here.first.cursed?).to be_true
    end

    it "leaves arrows with a different enchantment" do
      game = carrying [arrows(8, enchantment: 1)], [arrows(3)]

      game.step Direction::East

      expect(game.here.size).to eq 1
    end

    it "leaves arrows in a different condition" do
      game = carrying [arrows(8)], [arrows(3, condition: Condition::Masterwork)]

      game.step Direction::East

      expect(game.here.size).to eq 1
    end

    it "leaves a kind that does not stack" do
      game = carrying [Item.new(Kind::LongSword)], [Item.new(Kind::LongSword)]

      game.step Direction::East

      expect(game.here.size).to eq 1
    end

    it "spends a turn on each thing it takes" do
      game = carrying [arrows(8), Item.new(Kind::HealingPotion)],
        [arrows(3, Blessing::Blessed), Item.new(Kind::HealingPotion)]

      game.step Direction::East

      expect(game.here).to be_empty
      expect(game.turn).to eq 3
    end

    it "takes nothing while something attacks" do
      game = carrying [arrows(8)], [arrows(3)]
      creature = Roguelike::Monster.new Roguelike::Species::Goblin, 3, 1, "band-beside"
      game.floor.place creature
      band = game.floor.band(creature.band) || raise "the floor has lost the band"
      knowledge = band.knowledge game.floor.id
      game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
      knowledge.saw Roguelike::Knowledge::PLAYER, 3, 2, game.turn
      band.awareness = Roguelike::Awareness::Hunting

      game.step Direction::East

      attacked = game.events.any? do |event|
        event.is_a?(Roguelike::Event::Attack) && event.attacker == creature.id
      end
      expect(attacked).to be_true
      expect(game.here.size).to eq 1
      expect(game.turn).to eq 1
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
      game.floor.drop 3, 2, Item.new(Kind::Dagger)
      game.step Roguelike::Direction::East

      expect(game.log.last?).to eq "You see a dagger here."
    end

    it "counts more than one" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Dagger)
      game.floor.drop 3, 2, Item.new(Kind::LongSword)
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

  describe "the floor the game ships" do
    it "has items scattered on it" do
      game = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)
      piles = 0
      game.floor.each_pile { |_x, _y, pile| piles += pile.size }

      expect(piles).to be > 0
    end

    it "puts them on floor and never in rock" do
      game = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)

      game.floor.each_pile do |column, row, _pile|
        expect(game.floor.terrain(column, row).floor?).to be_true
      end
    end

    # Placement is its own stream, so the loot does not shift when anything
    # else changes how much it rolls.
    it "scatters the same items from the same seed" do
      first = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)
      again = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)

      expect(again.floor.litter).to eq first.floor.litter
    end

    it "scatters different items from a different seed" do
      first = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED)
      other = Roguelike::Game.start Roguelike::Rng.new(Playing::SEED + 1)

      expect(other.floor.litter).not_to eq first.floor.litter
    end
  end

  describe "rounds of the log" do
    alias Action = Roguelike::Action
    alias Blessing = Roguelike::Blessing
    alias Direction = Roguelike::Direction

    # The index of the newest line in *game*'s log that starts with *text*.
    def line_of(game : Roguelike::Game, text : String) : Int32
      game.log.lines.rindex(&.starts_with?(text)) || raise "#{text.inspect} was not said"
    end

    it "puts the piles of two steps in two rounds" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Dagger)
      game.floor.drop 3, 3, Item.new(Kind::LongSword)

      game.perform Action::Move.new(Direction::East)
      game.perform Action::Move.new(Direction::South)

      first = line_of game, "You see a dagger"
      second = line_of game, "You see a long sword"
      expect(game.log.round_of first).not_to eq game.log.round_of(second)
      expect(game.log.current? first).to be_false
      expect(game.log.current? second).to be_true
    end

    it "keeps every line of a step with pickups in one round" do
      game = bare
      game.player.inventory.add(Item.new Kind::Arrow, count: 8) || raise "no room"
      game.player.inventory.add(Item.new Kind::HealingPotion) || raise "no room"
      game.floor.drop 3, 2, Item.new(Kind::Arrow, count: 3)
      game.floor.drop 3, 2, Item.new(Kind::HealingPotion)
      game.floor.drop 3, 2, Item.new(Kind::Dagger)
      start = game.log.size

      game.perform Action::Move.new(Direction::East)

      expect(game.turn).to eq 3
      expect(game.log.size - start).to eq 3
      rounds = (start...game.log.size).map { |index| game.log.round_of index }
      expect(rounds.uniq).to eq [game.log.round - 1]
    end
  end

  describe "serialization" do
    it "keeps what is on the floor" do
      game = bare
      game.floor.drop 2, 2, Item.new(Kind::Arrow, count: 7)
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
