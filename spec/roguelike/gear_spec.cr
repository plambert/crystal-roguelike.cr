require "../spec_helper"

Spectator.describe "what a monster wields and wears" do
  alias Awareness = Roguelike::Awareness
  alias Costs = Roguelike::Costs
  alias Dice = Roguelike::Dice
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Items = Roguelike::Items
  alias Kind = Roguelike::Kind
  alias Loot = Roguelike::Loot
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Rng = Roguelike::Rng
  alias Size = Roguelike::Size
  alias Slot = Roguelike::Slot
  alias World = Roguelike::World
  alias Which = Roguelike::Attributes::Which

  GEAR_SEED = 20260930_u64

  # A lit room with the character at 2,1 and a sealed cell at 9,1 and
  # 10,1. A creature in the cell cannot get out and the character cannot
  # get in, so all it can do on its turn is take up what lies under it.
  GEAR_CELL = ["############",
               "#.<.....#..#",
               "############"]

  # A game with *creature* at 9,1 in the cell, hunting the character, with
  # *lying* on its square.
  def caged(creature : Monster, lying : Array(Item) = [] of Item) : Game
    floor = Floor.parse "cell", GEAR_CELL.join('\n')
    floor.ambient = 1
    floor.place creature
    lying.each { |item| floor.drop creature.x, creature.y, item }

    band = floor.band creature.band
    raise "no band" unless band
    band.knowledge("cell").saw Roguelike::Knowledge::PLAYER, 2, 1, 0
    band.awareness = Awareness::Hunting

    Game.new World.new(GEAR_SEED, {"cell" => floor}), Player.new("cell", 2, 1)
  end

  # A lit room with the character at 2,1 and *creature* beside them at 3,1,
  # hunting them.
  def beside(creature : Monster) : Game
    floor = Floor.parse "room", ["#######", "#.<...#", "#######"].join('\n')
    floor.ambient = 1
    floor.place creature
    floor.band(creature.band).try &.awareness=(Awareness::Hunting)

    Game.new World.new(GEAR_SEED, {"room" => floor}),
      Player.new("room", 2, 1, hit_points: 500)
  end

  def strength(creature : Monster) : Int32
    creature.attributes.modifier Which::Strength
  end

  describe "a weapon in its hand" do
    it "hits with the weapon's dice rather than its own" do
      goblin = Monster.new Kind::GoblinScout, 3, 1, "band-one"
      goblin.ready Item.new(ItemKind::ShortSword)

      expect(goblin.damage).to eq Dice.new(1, 6).with_bonus(strength goblin)
      expect(goblin.swing).to eq ItemKind::ShortSword.swing
    end

    it "hits with its own dice when its hand is empty" do
      goblin = Monster.new Kind::GoblinScout, 3, 1, "band-one"

      expect(goblin.damage).to eq Kind::GoblinScout.damage.with_bonus(strength goblin)
      expect(goblin.swing).to eq Kind::GoblinScout.swing
    end

    it "adds the weapon's enchantment to the swing landing" do
      goblin = Monster.new Kind::GoblinWarrior, 3, 1, "band-one"
      bare = goblin.to_hit
      goblin.ready Item.new(ItemKind::ShortSword, 2)

      expect(goblin.to_hit).to eq bare + 2
    end

    it "pays the weapon's cost for a blow at the character" do
      goblin = Monster.new Kind::GoblinWarrior, 3, 1, "band-one"
      goblin.ready Item.new(ItemKind::Dagger)
      game = beside goblin

      game.wait

      # It came in with a tick, paid the dagger's cost, then gained its speed.
      expect(goblin.pace.energy).to eq Costs::TURN - ItemKind::Dagger.swing + goblin.pace.speed
    end

    it "reads the found short sword's dice and cost once it has taken it up" do
      goblin = Monster.new Kind::GoblinScout, 9, 1, "band-one"
      goblin.ready Item.new(ItemKind::Dagger)
      game = caged goblin, [Item.new(ItemKind::ShortSword)]

      game.wait

      expect(goblin.wielded.try &.kind).to eq ItemKind::ShortSword
      expect(goblin.damage).to eq Dice.new(1, 6).with_bonus(strength goblin)
      expect(goblin.swing).to eq 100
    end
  end

  describe "armor it wears" do
    it "raises its armor class by the armor's bonus" do
      orc = Monster.new Kind::Orc, 3, 1, "band-one"
      bare = orc.armor_class
      orc.ready Item.new(ItemKind::ChainMail, 5)

      expect(orc.armor_class).to eq bare + 9
    end

    it "does not go on when it is cut for another size" do
      orc = Monster.new Kind::Orc, 3, 1, "band-one"
      goblin = Monster.new Kind::GoblinWarrior, 3, 1, "band-one"
      medium = Item.new ItemKind::ChainMail

      expect(orc.slot_for medium).to eq Slot::Body
      expect(orc.slot_for Item.new(ItemKind::ChainMail, size: Size::Large)).to be_nil
      expect(goblin.slot_for medium).to be_nil
      expect(goblin.slot_for Item.new(ItemKind::ChainMail, size: Size::Small)).to eq Slot::Body
    end
  end

  describe "armor the character tries to wear" do
    def wearing(size : Size) : {Game, Char}
      game = caged Monster.new(Kind::WhiteSlime, 9, 1, "band-one")
      letter = game.player.inventory.add Item.new(ItemKind::LeatherArmor, size: size)
      raise "the pack is full" unless letter

      {game, letter}
    end

    it "refuses armor cut for a goblin and says why" do
      game, letter = wearing Size::Small

      expect(game.wear letter).to be_false
      expect(game.player.in_slot Slot::Body).to be_nil
      expect(game.log.lines.last).to eq "You cannot wear small leather armor, " \
                                        "which was made for somebody smaller."
    end

    it "refuses armor cut for somebody larger and says why" do
      game, letter = wearing Size::Large

      expect(game.wear letter).to be_false
      expect(game.log.lines.last).to contain "made for somebody larger"
    end

    it "offers no action to wear it" do
      game, letter = wearing Size::Small
      id = game.player.inventory[letter].try &.id

      wear = game.legal.select(Roguelike::Action::Wear)
      expect(wear.none? { |action| action.item == id }).to be_true
    end

    it "puts on armor cut for the character" do
      game, letter = wearing Size::Medium

      expect(game.wear letter).to be_true
    end
  end

  describe "picking things up" do
    it "takes up a better weapon and drops the one it held" do
      goblin = Monster.new Kind::GoblinScout, 9, 1, "band-one"
      goblin.ready Item.new(ItemKind::Dagger)
      game = caged goblin, [Item.new(ItemKind::ShortSword)]

      game.wait

      expect(goblin.wielded.try &.kind).to eq ItemKind::ShortSword
      expect(game.floor.items(9, 1).map &.kind).to eq [ItemKind::Dagger]
    end

    it "leaves a worse weapon where it lies" do
      goblin = Monster.new Kind::GoblinScout, 9, 1, "band-one"
      goblin.ready Item.new(ItemKind::ShortSword)
      game = caged goblin, [Item.new(ItemKind::Dagger)]

      game.wait

      expect(goblin.wielded.try &.kind).to eq ItemKind::ShortSword
      expect(game.floor.items(9, 1).map &.kind).to eq [ItemKind::Dagger]
    end

    it "counts an enchantment toward better" do
      goblin = Monster.new Kind::GoblinWarrior, 9, 1, "band-one"
      goblin.ready Item.new(ItemKind::ShortSword)
      game = caged goblin, [Item.new(ItemKind::ShortSword, 1)]

      game.wait

      expect(goblin.wielded.try &.enchantment).to eq 1
    end

    it "puts on armor that fits it" do
      goblin = Monster.new Kind::GoblinWarrior, 9, 1, "band-one"
      game = caged goblin, [Item.new(ItemKind::Cap), Item.new(ItemKind::Cap, size: Size::Small)]

      game.wait

      expect(goblin.in_slot(Slot::Head).try &.size).to eq Size::Small
      expect(game.floor.items(9, 1).map &.size).to eq [Size::Medium]
    end

    it "spends its action on it" do
      goblin = Monster.new Kind::GoblinWarrior, 3, 1, "band-one"
      game = beside goblin
      game.floor.drop 3, 1, Item.new(ItemKind::LongSword)

      game.wait

      expect(goblin.wielded.try &.kind).to eq ItemKind::LongSword
      expect(game.log.lines.none? &.includes?("you")).to be_true
    end

    it "says so when the character can see it" do
      goblin = Monster.new Kind::GoblinScout, 3, 1, "band-one"
      goblin.ready Item.new(ItemKind::Dagger)
      game = beside goblin
      game.floor.drop 3, 1, Item.new(ItemKind::ShortSword)

      game.wait

      expect(game.log.lines).to contain "The goblin scout drops a dagger and picks up a short sword."
    end

    it "leaves everything alone when it is a slime" do
      slime = Monster.new Kind::GreenSlime, 9, 1, "band-one"
      game = caged slime, [Item.new(ItemKind::ShortSword), Item.new(ItemKind::Cap)]

      game.wait

      expect(slime.gear.empty?).to be_true
      expect(game.floor.items(9, 1).size).to eq 2
    end

    it "takes up a wand of striking when it is a shaman" do
      shaman = Monster.new Kind::GoblinShaman, 9, 1, "band-one"
      game = caged shaman, [Item.new(ItemKind::StrikingWand)]

      game.wait

      expect(shaman.wand.try &.kind).to eq ItemKind::StrikingWand
      expect(game.floor.items(9, 1).empty?).to be_true
    end

    it "takes up stones for the sling it holds when its quiver is empty" do
      scout = Monster.new Kind::GoblinScout, 9, 1, "band-one"
      scout.outfit [Item.new(ItemKind::Sling)]
      game = caged scout, [Item.new(ItemKind::Stone, count: 4)]

      game.wait

      expect(scout.ammunition.try &.count).to eq 4
      expect(game.floor.items(9, 1).empty?).to be_true
    end

    it "adds stones to the stones already in its quiver" do
      scout = Monster.new Kind::GoblinScout, 9, 1, "band-one"
      scout.outfit [Item.new(ItemKind::Sling), Item.new(ItemKind::Stone, count: 2)]
      game = caged scout, [Item.new(ItemKind::Stone, count: 3)]

      game.wait

      expect(scout.ammunition.try &.count).to eq 5
      expect(game.floor.items(9, 1).empty?).to be_true
    end

    it "takes up a bow when it is an archer with an empty hand" do
      archer = Monster.new Kind::OrcArcher, 9, 1, "band-one"
      game = caged archer, [Item.new(ItemKind::Bow)]

      game.wait

      expect(archer.ranged_weapon.try &.kind).to eq ItemKind::Bow
    end

    it "leaves a sling and stones alone when it does not shoot" do
      goblin = Monster.new Kind::GoblinWarrior, 9, 1, "band-one"
      game = caged goblin, [Item.new(ItemKind::Sling), Item.new(ItemKind::Stone, count: 3)]

      game.wait

      expect(goblin.ranged_weapon).to be_nil
      expect(game.floor.items(9, 1).size).to eq 2
    end

    it "leaves a wand alone when it is not a shaman" do
      goblin = Monster.new Kind::GoblinWarrior, 9, 1, "band-one"
      game = caged goblin, [Item.new(ItemKind::StrikingWand)]

      game.wait

      expect(goblin.wand).to be_nil
    end
  end

  describe "killing it" do
    it "drops what it had readied and what it carried" do
      goblin = Monster.new Kind::GoblinWarrior, 3, 1, "band-one"
      goblin.outfit [Item.new(ItemKind::ShortSword), Item.new(ItemKind::Cap, size: Size::Small),
                     Item.new(ItemKind::Gold, count: 5)]
      game = beside goblin

      game.kill goblin

      pile = game.floor.items(3, 1).map &.kind
      expect(pile).to contain ItemKind::ShortSword, ItemKind::Cap, ItemKind::Gold
      expect(goblin.gear.empty?).to be_true
    end
  end

  describe "starting gear" do
    it "goes in its slots rather than its pack" do
      scout = Monster.new Kind::GoblinScout, 3, 1, "band-one"
      scout.outfit Loot.for(Kind::GoblinScout, Rng.new(GEAR_SEED), 1)

      expect(scout.wielded.try &.kind).to eq ItemKind::Dagger
      expect(scout.carrying.none? &.kind.dagger?).to be_true
    end

    it "is cut for the creature that wears it" do
      1.upto(200) do |index|
        items = Loot.for Kind::Orc, Rng.new(GEAR_SEED).derive("orc", index), 5
        items.select(&.kind.item_class.armor?).each do |item|
          expect(item.size).to eq Size::Medium
        end
      end
    end

    it "keeps to the gates and the ceilings on floor 1" do
      1.upto(300) do |index|
        creature = Monster.new Kind::GoblinScout, 3, 1, "band-one"
        creature.outfit Loot.for(Kind::GoblinScout, Rng.new(GEAR_SEED).derive("scout", index), 1)

        creature.belongings.each do |item|
          expect(Loot.allowed? item.kind, 1).to be_true
          expect(item.enchantment).to be <= Loot.ceiling(1)
        end
      end
    end

    it "is the same on every run from one seed" do
      first = Game.dug Rng.new(GEAR_SEED)
      second = Game.dug Rng.new(GEAR_SEED)

      first.floor.each_monster do |column, row, creature|
        other = second.floor.monster column, row
        expect(other.try &.gear).to eq creature.gear
        expect(other.try &.carrying).to eq creature.carrying
      end
    end
  end

  describe "armor lying about" do
    it "is cut for the character most of the time" do
      sizes = Hash(Size, Int32).new 0

      4.times do |index|
        game = Game.dug Rng.new(GEAR_SEED + index)
        game.floor.each_pile do |_column, _row, pile|
          pile.each { |item| sizes[item.size] += 1 if item.kind.item_class.armor? }
        end
      end

      expect(sizes[Size::Medium]).to be > sizes[Size::Small] + sizes[Size::Large]
    end

    it "leans small near a goblin and medium near an orc" do
      floor = Floor.parse "room", ["#" * 40, "#" + "." * 38 + "#", "#" * 40].join('\n')
      floor.place Monster.new(Kind::GoblinScout, 2, 1, "band-one")
      floor.place Monster.new(Kind::Orc, 37, 1, "band-two")

      expect(Items.sizes_at floor, {4, 1}).to eq Items::NEAR_GOBLINS
      expect(Items.sizes_at floor, {35, 1}).to eq Items::SIZES
      expect(Items.sizes_at floor, {20, 1}).to eq Items::SIZES
    end

    it "is cut the same way from one seed" do
      first = Game.dug Rng.new(GEAR_SEED)
      second = Game.dug Rng.new(GEAR_SEED)

      first.floor.each_pile do |column, row, pile|
        expect(second.floor.items(column, row).map &.size).to eq pile.map(&.size)
      end
    end
  end

  describe "a save" do
    it "carries what it has readied through" do
      goblin = Monster.new Kind::GoblinWarrior, 9, 1, "band-one"
      goblin.outfit [Item.new(ItemKind::ShortSword, 1), Item.new(ItemKind::LeatherArmor, size: Size::Small),
                     Item.new(ItemKind::Torch, lit: true)]
      game = caged goblin

      again = Game.from_json game.to_json
      held = again.floor.monster 9, 1

      expect(held).to eq goblin
      expect(held.try &.wielded.try &.enchantment).to eq 1
      expect(held.try &.in_slot(Slot::Body).try &.size).to eq Size::Small
      expect(held.try &.carrying.map &.kind).to eq [ItemKind::Torch]
    end

    it "loads an old creature with what it carried and nothing readied" do
      old = %({"id":3,"species":"goblin","kind":"GoblinWarrior","x":4,"y":5,) +
            %("hit_points":6,"attributes":{"strength":10,"dexterity":13,) +
            %("constitution":10,"intelligence":7,"stealth":13},"band":"band-one",) +
            %("memory":{},"carrying":[{"kind":"ShortSword","enchantment":0,) +
            %("condition":"Plain","blessing":"Uncursed","blessing_known":false,) +
            %("count":1,"lit":false}],"blinded":0,"pace":{"base":100,"energy":0}})

      creature = Monster.from_json old

      expect(creature.gear.empty?).to be_true
      expect(creature.carrying.map &.kind).to eq [ItemKind::ShortSword]
      expect(creature.carrying.first.size).to eq Size::Medium
      expect(creature.damage).to eq Kind::GoblinWarrior.damage.with_bonus(strength creature)
    end

    it "writes nothing new for a creature with nothing readied" do
      creature = Monster.new Kind::WhiteSlime, 1, 1, "band-one"

      expect(creature.to_json).not_to contain "gear"
      expect(Item.new(ItemKind::Cap).to_json).not_to contain "size"
    end
  end

  describe "the examine pane" do
    it "says what a creature wields and wears" do
      goblin = Monster.new Kind::GoblinWarrior, 1, 1, "band-one"
      goblin.outfit [Item.new(ItemKind::ShortSword), Item.new(ItemKind::LeatherArmor, size: Size::Small),
                     Item.new(ItemKind::Cap, size: Size::Small)]

      said = Roguelike::Ui::ExaminePane.gear goblin, Roguelike::Lore.new

      expect(said).to eq "It wields a short sword and wears small leather armor and a small cap."
    end

    it "says nothing for a creature with nothing readied" do
      slime = Monster.new Kind::WhiteSlime, 1, 1, "band-one"

      expect(Roguelike::Ui::ExaminePane.gear slime, Roguelike::Lore.new).to be_nil
    end
  end
end
