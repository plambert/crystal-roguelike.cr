require "../spec_helper"

Spectator.describe "drinking, reading and zapping" do
  alias Effect = Roguelike::Effect
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Lore = Roguelike::Lore
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Rng = Roguelike::Rng
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # The seed every example here rolls on. A failure names a run somebody can
  # start.
  SEED = 20260912_u64

  # One hall with the character at the west end.
  #
  # The wall at column 5 of row 3 is what a bolt with something in the way
  # meets. Row 1 is clear the whole way.
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

  # How far east a bolt goes before it hits the end wall.
  EAST = {10, 1}

  # A game with the character carrying *held*.
  #
  # The floor is lit unless *dark*. A *torch* puts light on the character's
  # own square and the few round it, which is what somebody reading in a dark
  # dungeon is doing. The character has *hit_points*, so an example about
  # healing can start somebody short of full.
  def carrying(held : Array(Item) = [] of Item,
               dark : Bool = false,
               torch : Bool = false,
               hit_points : Int32? = nil) : Game
    floor = Floor.parse "hall", HALL
    Playing.daylight floor unless dark

    player = Player.new floor.id, *HERE, hit_points: hit_points
    game = Game.new World.new(SEED, {floor.id => floor}), player,
      lore: Lore.roll(Rng.new SEED)
    held.each { |item| player.inventory.add item }
    player.inventory.add Playing.torch if torch
    game
  end

  # A goblin standing at *at*.
  def goblin(at : {Int32, Int32}, hit_points : Int32? = nil) : Monster
    Monster.new Species::Goblin, at[0], at[1], "band-one", hit_points: hit_points
  end

  # What *game* calls what is under *letter*.
  def named(game : Game, letter : Char) : String
    item = game.player.inventory[letter]
    raise "nothing is under #{letter}" unless item

    game.name item
  end

  # How many charges are left in what is under *letter*.
  def charges(game : Game, letter : Char) : Int32
    item = game.player.inventory[letter]
    raise "nothing is under #{letter}" unless item

    item.charges || 0
  end

  describe "what an item says it does" do
    it "names an effect for each kind that has one" do
      expect(Kind::HealingPotion.effect).to eq Effect::Heal
      expect(Kind::IdentifyScroll.effect).to eq Effect::Identify
      expect(Kind::MappingScroll.effect).to eq Effect::MapFloor
      expect(Kind::LightWand.effect).to eq Effect::Light
      expect(Kind::StrikingWand.effect).to eq Effect::Strike
    end

    it "names none for everything else" do
      Kind.values.reject(&.disguised?).each do |kind|
        expect(kind.effect).to eq Effect::None
      end
    end

    it "says which effects need a square and which need an item" do
      expect(Effect::Strike.aimed?).to be_true
      expect(Effect::Identify.chosen?).to be_true
      expect(Effect::Heal.aimed?).to be_false
      expect(Effect::Heal.chosen?).to be_false
    end
  end

  describe "Game#quaff" do
    it "puts hit points back" do
      game = carrying [Item.new(Kind::HealingPotion)], hit_points: 1

      game.quaff 'a'

      expect(game.player.hit_points).to be > 1
      expect(game.log.lines).to contain "You feel better."
    end

    it "never goes past full health" do
      game = carrying [Item.new(Kind::HealingPotion)]
      full = game.player.max_hit_points

      game.quaff 'a'

      expect(game.player.hit_points).to eq full
    end

    it "uses the potion up" do
      game = carrying [Item.new(Kind::HealingPotion)]

      game.quaff 'a'

      expect(game.player.inventory.has? 'a').to be_false
    end

    it "drinks one of a stack" do
      game = carrying [Item.new(Kind::HealingPotion, count: 3)]

      game.quaff 'a'

      expect(game.player.inventory['a'].try &.count).to eq 2
    end

    it "counts a turn" do
      game = carrying [Item.new(Kind::HealingPotion)]
      before = game.turn

      game.quaff 'a'

      expect(game.turn).to eq before + 1
    end

    it "refuses anything that is not a potion" do
      game = carrying [Item.new(Kind::Dagger)]
      before = game.turn

      expect(game.quaff 'a').to be_false
      expect(game.turn).to eq before
      expect(game.log.last?.to_s).to contain "cannot drink"
    end
  end

  describe "finding out what a thing is" do
    it "names the potion by drinking it" do
      game = carrying [Item.new(Kind::HealingPotion)]
      expect(game.lore.known? Kind::HealingPotion).to be_false

      game.quaff 'a'

      expect(game.lore.known? Kind::HealingPotion).to be_true
      expect(game.log.lines).to contain "It was a potion of healing."
    end

    it "calls it by its look before anybody drinks one" do
      game = carrying [Item.new(Kind::HealingPotion)]
      look = game.lore.appearance Kind::HealingPotion

      expect(named game, 'a').to eq "#{Lore.article look.to_s} #{look} potion"
    end

    # Identification is per kind, so one potion names every potion that
    # looks the same.
    it "names every other potion of the same kind" do
      game = carrying [Item.new(Kind::HealingPotion, count: 3)]
      expect(named game, 'a').to contain "potion"

      game.quaff 'a'

      expect(named game, 'a').to eq "2 potions of healing"
    end

    it "says nothing the second time" do
      game = carrying [Item.new(Kind::HealingPotion, count: 2)]

      game.quaff 'a'
      before = game.log.lines.size
      game.quaff 'a'

      said = game.log.lines[before..]
      expect(said.any? &.starts_with? "It was").to be_false
    end

    it "names the wand by zapping it" do
      game = carrying [Item.new(Kind::LightWand)]

      game.zap 'a'

      expect(game.lore.known? Kind::LightWand).to be_true
    end

    it "names the scroll by reading it" do
      game = carrying [Item.new(Kind::MappingScroll)]

      game.read 'a'

      expect(game.lore.known? Kind::MappingScroll).to be_true
    end
  end

  describe "a scroll of magic mapping" do
    it "remembers the shape of the whole floor" do
      game = carrying [Item.new(Kind::MappingScroll)], dark: true, torch: true

      game.read 'a'

      every = game.floor.columns * game.floor.rows
      expect(game.knowledge.size).to eq every
    end

    it "remembers a square the character has never seen" do
      game = carrying [Item.new(Kind::MappingScroll)], dark: true, torch: true
      expect(game.knowledge.seen? 10, 4).to be_false

      game.read 'a'

      expect(game.knowledge[10, 4].try &.terrain).to eq game.floor.terrain 10, 4
    end

    # The scroll records the terrain and what is fixed to it, and nothing
    # that is lying about.
    it "says nothing about what is lying on the floor" do
      game = carrying [Item.new(Kind::MappingScroll)], dark: true, torch: true
      game.floor.drop 10, 4, Item.new(Kind::LongSword)

      game.read 'a'

      expect(game.knowledge[10, 4].try &.item).to be_nil
    end

    it "uses the scroll up" do
      game = carrying [Item.new(Kind::MappingScroll)]

      game.read 'a'

      expect(game.player.inventory.has? 'a').to be_false
    end
  end

  # A scroll is words on paper.
  describe "reading in the dark" do
    it "refuses, and costs neither the scroll nor a turn" do
      game = carrying [Item.new(Kind::MappingScroll)], dark: true
      before = game.turn

      expect(game.read 'a').to be_false
      expect(game.player.inventory.has? 'a').to be_true
      expect(game.turn).to eq before
      expect(game.log.last?).to eq "It is too dark to read."
    end

    it "says so before anything is chosen" do
      game = carrying [] of Item, dark: true

      expect(game.cannot_read).to eq "It is too dark to read."
    end

    it "says nothing when the character carries a lit torch" do
      game = carrying [] of Item, dark: true, torch: true

      expect(game.cannot_read).to be_nil
    end

    it "reads by the light of a carried torch" do
      game = carrying [Item.new(Kind::MappingScroll)], dark: true, torch: true

      expect(game.read 'a').to be_true
      expect(game.player.inventory.has? 'a').to be_false
    end

    it "reads by the light a wand of light left behind" do
      game = carrying [Item.new(Kind::LightWand), Item.new(Kind::MappingScroll)],
        dark: true
      expect(game.cannot_read).not_to be_nil

      game.zap 'a'

      expect(game.cannot_read).to be_nil
      expect(game.read 'b').to be_true
    end

    it "stops the character reading once the torch goes out" do
      game = carrying [Item.new(Kind::MappingScroll)], dark: true, torch: true
      torch = game.player.inventory['b']
      expect(game.cannot_read).to be_nil

      torch.try &.douse

      expect(game.cannot_read).to eq "It is too dark to read."
    end

    it "leaves drinking and zapping alone" do
      game = carrying [Item.new(Kind::HealingPotion), Item.new(Kind::LightWand)],
        dark: true, hit_points: 1

      expect(game.quaff 'a').to be_true
      expect(game.zap 'b').to be_true
    end
  end

  describe "a scroll of identify" do
    it "names the item it is read on" do
      game = carrying [Item.new(Kind::IdentifyScroll), Item.new(Kind::HealingPotion)]

      game.read 'a', 'b'

      expect(game.lore.known? Kind::HealingPotion).to be_true
      expect(game.log.lines).to contain "It is an uncursed potion of healing."
    end

    it "says whether the item is cursed" do
      cursed = Item.new Kind::HealingPotion, blessing: Roguelike::Blessing::Cursed
      game = carrying [Item.new(Kind::IdentifyScroll), cursed]

      game.read 'a', 'b'

      expect(cursed.blessing_known?).to be_true
      expect(game.log.lines.find(&.starts_with? "It is").to_s).to contain "cursed"
    end

    it "is used up when there is nothing to name" do
      game = carrying [Item.new(Kind::IdentifyScroll)]

      game.read 'a'

      expect(game.player.inventory.has? 'a').to be_false
      expect(game.log.lines).to contain "You feel knowledgeable, and the feeling passes."
    end

    it "says so when the character already knew" do
      game = carrying [
        Item.new(Kind::IdentifyScroll, count: 2),
        Item.new(Kind::HealingPotion),
      ]

      game.read 'a', 'b'
      game.read 'a', 'b'

      expect(game.log.lines.last?.to_s).to contain "knew that already"
    end
  end

  describe "a wand of light" do
    it "leaves the floor glowing where the character stood" do
      game = carrying [Item.new(Kind::LightWand)], dark: true
      expect(game.floor.glow_at 3, 1).to eq 0

      game.zap 'a'

      expect(game.floor.glow_at 3, 1).to be > 0
    end

    it "lights the room and keeps it lit with no torch" do
      game = carrying [Item.new(Kind::LightWand)], dark: true
      expect(game.sight.lit? 4, 1).to be_false

      game.zap 'a'

      expect(game.sight.lit? 4, 1).to be_true
    end

    it "leaves the walls alone and lets the glow spill onto them" do
      game = carrying [Item.new(Kind::LightWand)], dark: true

      game.zap 'a'

      expect(game.floor.glow_at 0, 1).to eq 0
      expect(game.sight.lit? 0, 1).to be_true
    end

    it "does not light the far end of the hall" do
      game = carrying [Item.new(Kind::LightWand)], dark: true

      game.zap 'a'

      expect(game.floor.glow_at 10, 1).to eq 0
    end

    it "stays lit after the run is written out and read back" do
      game = carrying [Item.new(Kind::LightWand)], dark: true
      game.zap 'a'

      again = Game.from_json game.to_json

      expect(again.floor.glow_at 3, 1).to be > 0
    end
  end

  describe "a wand of striking" do
    it "hits a creature in the line" do
      game = carrying [Item.new(Kind::StrikingWand)]
      game.floor.place goblin({6, 1}, hit_points: 200)

      game.zap 'a', EAST

      said = game.log.lines.find(&.includes? "goblin").to_s
      expect(said).to match /bolt (hits|misses) the goblin/
    end

    it "kills a creature it takes to zero" do
      game = carrying [Item.new(Kind::StrikingWand, charges: 40)]
      game.floor.place goblin({6, 1})

      40.times { game.zap 'a', EAST }

      expect(game.log.lines).to contain "You kill the goblin."
    end

    it "leaves nothing on the floor" do
      game = carrying [Item.new(Kind::StrikingWand)]

      game.zap 'a', EAST

      expect(game.floor.items(*EAST).empty?).to be_true
    end

    it "says what it hit when there was no creature" do
      game = carrying [Item.new(Kind::StrikingWand)]

      game.zap 'a', EAST

      expect(game.log.lines.any? &.starts_with? "The bolt strikes").to be_true
    end

    it "goes nowhere with no square to aim at" do
      game = carrying [Item.new(Kind::StrikingWand)]

      game.zap 'a'

      expect(game.log.lines).to contain "The bolt goes nowhere."
    end
  end

  describe "charges" do
    it "gives a new wand what its kind says" do
      expect(Item.new(Kind::LightWand).charges).to eq Kind::LightWand.charges
    end

    it "uses one up per zap" do
      game = carrying [Item.new(Kind::LightWand)]
      before = charges game, 'a'

      game.zap 'a'

      expect(charges game, 'a').to eq before - 1
    end

    it "keeps the wand in the inventory" do
      game = carrying [Item.new(Kind::LightWand)]

      game.zap 'a'

      expect(game.player.inventory.has? 'a').to be_true
    end

    it "says so once it is spent" do
      game = carrying [Item.new(Kind::LightWand, charges: 1)]

      game.zap 'a'
      before = game.log.lines.size
      game.zap 'a'

      expect(game.log.lines[before..].last?.to_s).to contain "Nothing happens"
    end

    # A person cannot know a wand is empty until they try it. Trying takes
    # the turn.
    it "still costs a turn once it is spent" do
      game = carrying [Item.new(Kind::LightWand, charges: 0)]
      before = game.turn

      expect(game.zap 'a').to be_true
      expect(game.turn).to eq before + 1
    end

    it "refuses anything that is not a wand" do
      game = carrying [Item.new(Kind::Dagger)]
      before = game.turn

      expect(game.zap 'a').to be_false
      expect(game.turn).to eq before
    end
  end

  describe "the stream a use rolls on" do
    # A potion rolls on its own stream. The swings that follow it come up the
    # same as they would have.
    it "leaves the swings where they were" do
      plain = carrying
      drinking = carrying [Item.new(Kind::HealingPotion)]
      drinking.quaff 'a'

      [plain, drinking].each do |game|
        game.floor.place goblin({2, 1}, hit_points: 500)
        3.times { game.step Roguelike::Direction::East }
      end

      expect(plain.blows).to eq drinking.blows
      expect(plain.log.lines.select(&.includes? "goblin"))
        .to eq drinking.log.lines.select(&.includes? "goblin")
    end

    it "counts every use" do
      game = carrying [Item.new(Kind::HealingPotion, count: 3)]

      3.times { game.quaff 'a' }

      expect(game.uses).to eq 3
    end

    it "carries the count through serialization" do
      game = carrying [Item.new(Kind::HealingPotion, count: 2)]
      game.quaff 'a'

      expect(Game.from_json(game.to_json).uses).to eq game.uses
    end
  end
end
