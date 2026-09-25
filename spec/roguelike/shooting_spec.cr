require "../spec_helper"

Spectator.describe "shooting and throwing" do
  alias Blessing = Roguelike::Blessing
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Slot = Roguelike::Slot
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # The seed every example here shoots on. A failure names a run somebody can
  # start.
  SEED = 20260912_u64

  # One lit hall with the character at the west end.
  #
  # A shot east runs the length of it. The pillar at column 5 of row 3 is what
  # a shot with something in the way meets.
  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "#....#.....#",
    "#..........#",
    "############",
  ]

  # Where the character stands.
  HERE = {1, 1}

  # How far east a shot goes before it hits the end wall.
  EAST = {10, 1}

  # A game with the character holding *held*.
  #
  # The character has enough hit points to lose a fight and go on standing,
  # because these examples are about the shot rather than about dying.
  def armed(held : Array(Item) = [] of Item,
            at : {Int32, Int32} = HERE) : Game
    floor = Playing.daylight Floor.parse("hall", HALL)

    player = Player.new floor.id, *at, hit_points: 500
    game = Game.new World.new(SEED, {floor.id => floor}), player
    held.each { |item| player.inventory.add item }
    game
  end

  # A goblin standing at *at* with nothing on it.
  def goblin(at : {Int32, Int32}, hit_points : Int32? = nil) : Monster
    Monster.new Species::Goblin, at[0], at[1], "band-one", hit_points: hit_points
  end

  # A game with a bow readied and *arrows* arrows in the quiver.
  #
  # Any *monsters* go on the floor after the two turns readying costs. A
  # creature placed before them would have walked somewhere else by the time
  # the first shot goes.
  def archer(arrows : Int32 = 12, monsters : Array(Monster) = [] of Monster) : Game
    game = armed [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: arrows)]
    game.wield 'a'
    game.wield 'b'
    monsters.each { |creature| game.floor.place creature }
    game
  end

  # Every square of the floor holding an item of *kind*.
  def lying(game : Game, kind : Kind) : Array({Int32, Int32})
    found = [] of {Int32, Int32}

    game.floor.each_pile do |column, row, pile|
      found << {column, row} if pile.any? &.kind.== kind
    end

    found
  end

  # What was said about the goblin, if anything.
  def about_the_goblin(game : Game) : String
    game.log.lines.find(&.includes? "goblin").to_s
  end

  describe "Game#cannot_fire" do
    it "says so when nothing is readied to shoot with" do
      game = armed [Item.new(Kind::Arrow, count: 3)]

      expect(game.cannot_fire).to eq "You have nothing readied to shoot with."
    end

    it "says so when the quiver is empty" do
      game = armed [Item.new(Kind::Bow)]
      game.wield 'a'

      expect(game.cannot_fire).to eq "Your quiver is empty."
    end

    it "says so when the quiver holds the wrong ammunition" do
      game = armed [Item.new(Kind::Bow), Item.new(Kind::Stone, count: 6)]
      game.wield 'a'
      game.wield 'b'

      expect(game.cannot_fire.to_s).to contain "cannot shoot"
    end

    it "says nothing when the bow and the arrows match" do
      expect(archer.cannot_fire).to be_nil
    end
  end

  describe "Game#fire" do
    it "costs no turn when the quiver is empty" do
      game = armed [Item.new(Kind::Bow)]
      game.wield 'a'
      before = game.turn

      expect(game.fire EAST).to be_false
      expect(game.turn).to eq before
      expect(game.log.last?).to eq "Your quiver is empty."
    end

    it "takes one arrow out of the quiver" do
      game = archer 12
      game.fire EAST

      expect(game.player.quivered.try &.count).to eq 11
    end

    it "empties the quiver slot with the last arrow" do
      game = archer 1
      game.fire EAST

      expect(game.player.quivered).to be_nil
      expect(game.player.inventory.has? 'b').to be_false
    end

    it "puts the arrow on the square the shot stopped on" do
      game = archer
      game.fire EAST

      pile = game.floor.items(*EAST).map &.kind
      expect(pile).to contain Kind::Arrow
    end

    it "puts one arrow down rather than the whole quiver" do
      game = archer 12
      game.fire EAST

      landed = game.floor.items(*EAST).find &.kind.arrow?
      expect(landed.try &.count).to eq 1
    end

    it "lets the character pick the arrow up again" do
      game = archer
      game.fire EAST

      taken = Game.new game.world, Player.new(game.floor.id, *EAST)
      expect(taken.pick_up_all).to eq 1
    end

    it "counts a turn" do
      game = archer
      before = game.turn
      game.fire EAST

      expect(game.turn).to eq before + 1
    end

    it "stops at the pillar rather than reaching past it" do
      game = armed [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 4)], at: {1, 3}
      game.wield 'a'
      game.wield 'b'
      game.fire({10, 3})

      expect(game.floor.items(4, 3).map &.kind).to contain Kind::Arrow
      expect(game.floor.items(10, 3).empty?).to be_true
    end

    it "says what it shot" do
      game = archer
      game.fire EAST

      expect(game.log.lines).to contain "You shoot an arrow."
    end
  end

  describe "hitting a creature with a shot" do
    it "rolls against the creature the shot stopped on" do
      game = archer monsters: [goblin({6, 1})]
      game.fire EAST

      expect(about_the_goblin game).to match /arrow (hits|misses) the goblin/
    end

    it "leaves the arrow on the creature's square" do
      game = archer monsters: [goblin({6, 1})]
      game.fire EAST

      expect(game.floor.items(6, 1).map &.kind).to contain Kind::Arrow
    end

    it "wakes the band it hit" do
      creature = goblin({6, 1}, hit_points: 200)
      game = archer monsters: [creature]
      game.fire EAST

      expect(game.awake? creature).to be_true
    end

    # Twenty arrows into one goblin kill it, whatever the rolls were. It
    # walks toward the character between shots, so which square it falls on
    # is not fixed.
    it "kills a creature it takes to zero" do
      game = archer 20, monsters: [goblin({6, 1})]
      20.times { game.fire EAST }

      expect(game.log.lines).to contain "You kill the goblin."
    end

    it "drops what the creature carried where it fell" do
      creature = goblin({6, 1})
      creature.carry [Item.new(Kind::Cap)]
      game = archer 20, monsters: [creature]
      20.times { game.fire EAST }

      expect(lying game, Kind::Cap).not_to be_empty
    end
  end

  describe "Game#throw" do
    it "throws one of a stack" do
      game = armed [Item.new(Kind::Dart, count: 5)]
      game.throw 'a', EAST

      expect(game.player.inventory['a'].try &.count).to eq 4
    end

    it "puts what was thrown on the floor" do
      game = armed [Item.new(Kind::Rock, count: 2)]
      game.throw 'a', EAST

      expect(game.floor.items(*EAST).map &.kind).to contain Kind::Rock
    end

    it "throws a thing nobody made for throwing" do
      game = armed [Item.new(Kind::Dagger)]
      game.throw 'a', EAST

      expect(game.player.inventory.has? 'a').to be_false
      expect(game.floor.items(*EAST).map &.kind).to contain Kind::Dagger
    end

    # Chain mail weighs three hundred, which is over the weight that leaves
    # anything but the shortest throw.
    it "drops something too heavy to throw one square away" do
      game = armed [Item.new(Kind::ChainMail)]
      game.throw 'a', EAST

      expect(game.floor.items(2, 1).map &.kind).to contain Kind::ChainMail
      expect(game.floor.items(*EAST).empty?).to be_true
    end

    it "counts a turn" do
      game = armed [Item.new(Kind::Rock)]
      before = game.turn
      game.throw 'a', EAST

      expect(game.turn).to eq before + 1
    end

    # A curse holds what is in a slot. A cursed dagger in the pack throws
    # like any other; one in the hand does not leave it.
    it "throws a cursed item that is only carried" do
      cursed = Item.new Kind::Dagger, blessing: Blessing::Cursed
      cursed.reveal_blessing
      game = armed [cursed]

      expect(game.throw 'a', EAST).to be_true
    end

    it "refuses to let go of a cursed item in the hand" do
      cursed = Item.new Kind::Dagger, blessing: Blessing::Cursed
      game = armed [cursed]
      game.wield 'a'

      expect(game.throw 'a', EAST).to be_false
      expect(game.player.inventory.has? 'a').to be_true
      expect(game.log.last?.to_s).to contain "cannot let go"
    end

    it "refuses to throw what is being worn" do
      game = armed [Item.new(Kind::Cap)]
      game.wear 'a'

      expect(game.throw 'a', EAST).to be_false
      expect(game.log.last?.to_s).to contain "take"
    end

    # A person holding a handful of darts throws one of them. Only worn
    # armor has to come off first.
    it "throws what the character is holding" do
      game = armed [Item.new(Kind::Dart, count: 4)]
      game.wield 'a'

      expect(game.slot_of 'a').to eq Slot::Melee
      expect(game.throw 'a', EAST).to be_true
      expect(game.player.inventory['a'].try &.count).to eq 3
    end

    it "rolls against a creature in the way" do
      game = armed [Item.new(Kind::Rock, count: 1)]
      game.floor.place goblin({6, 1})
      game.throw 'a', EAST

      expect(about_the_goblin game).to match /rock (hits|misses) the goblin/
    end
  end

  describe "how far a thing goes" do
    it "sends an arrow further than a rock" do
      expect(Kind::Bow.reach).to be > Kind::Rock.reach
    end

    it "sends a dart further than a dagger" do
      expect(Kind::Dart.reach).to be > Kind::Dagger.reach
    end

    it "sends a heavy thing less far than a light one" do
      expect(Kind::ChainMail.reach).to be < Kind::Dagger.reach
    end

    it "never sends anything nowhere" do
      Kind.values.each { |kind| expect(kind.reach).to be >= 1 }
    end
  end

  describe "serialization" do
    it "carries a fired arrow through" do
      game = archer
      game.fire EAST

      again = Game.from_json game.to_json
      expect(again.floor.items(*EAST).map &.kind).to contain Kind::Arrow
      expect(again.player.quivered.try &.count).to eq 11
    end
  end
end
