require "../spec_helper"

Spectator.describe "how well something is made out" do
  alias Blessing = Roguelike::Blessing
  alias Floor = Roguelike::Floor
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Knowledge = Roguelike::Knowledge
  alias Lore = Roguelike::Lore
  alias Memory = Roguelike::Memory
  alias Monster = Roguelike::Monster
  alias Naming = Roguelike::Ui::Naming
  alias Regard = Roguelike::Regard
  alias Regards = Roguelike::Regards
  alias Size = Roguelike::Size
  alias Species = Roguelike::Species
  alias Terrain = Roguelike::Terrain

  describe Roguelike::Regard do
    it "runs from least made out to most" do
      expect(Regard::Nothing < Regard::Shape).to be_true
      expect(Regard::Shape < Regard::Kind).to be_true
      expect(Regard::Kind < Regard::Everything).to be_true
    end

    it "says whether anything at all was made out" do
      expect(Regard::Nothing.made_out?).to be_false
      expect(Regard::Shape.made_out?).to be_true
      expect(Regard::Everything.made_out?).to be_true
    end

    it "keeps the better of two looks" do
      expect(Regard::Kind.at_least Regard::Everything).to eq Regard::Everything
      expect(Regard::Everything.at_least Regard::Kind).to eq Regard::Everything
      expect(Regard::Nothing.at_least Regard::Nothing).to eq Regard::Nothing
    end
  end

  describe Roguelike::Regards do
    it "makes everything out at the reach and nearer" do
      expect(Regards.of_item 0).to eq Regard::Everything
      expect(Regards.of_item 7).to eq Regard::Everything
      expect(Regards.of_item Regards::READING).to eq Regard::Everything
    end

    it "makes out the kind alone beyond the reach" do
      expect(Regards.of_item 9).to eq Regard::Kind
      expect(Regards.of_item 40).to eq Regard::Kind
    end

    it "counts a diagonal as one step" do
      expect(Regards.of_item({0, 0}, {8, 8})).to eq Regard::Everything
      expect(Regards.of_item({0, 0}, {9, 0})).to eq Regard::Kind
    end
  end

  # A lit room wide enough to put an item on either side of the reach. The
  # character stands in the middle, at 20, 5.
  def hall : Roguelike::Game
    Playing.field 40, 11
  end

  # A dark hall with a goblin standing against the one lit square at the east
  # end. The character is at the west end.
  BACKLIT = [
    "############",
    "#<.....g..*#",
    "############",
  ]

  # A dark hall with nothing lit in it at all.
  UNLIT = [
    "############",
    "#<.....g...#",
    "############",
  ]

  # A game on the hall *lines* describe, with a goblin standing at 7, 1.
  def hall_of(lines : Array(String), lit : Bool = false) : Roguelike::Game
    floor = Floor.parse "hall", lines
    Playing.daylight floor if lit
    floor.place Monster.new(Species::Goblin, 7, 1, "band-one")

    Roguelike::Game.new Roguelike::World.new(Playing::SEED, {floor.id => floor}),
      Roguelike::Player.new(floor.id, 1, 1)
  end

  # The goblin in *game*, or a failure saying there is none.
  def goblin(game : Roguelike::Game) : Monster
    found = game.floor.monster 7, 1
    raise "nothing is standing at 7, 1" unless found

    found
  end

  describe "an item lying on the floor" do
    it "is made out in full seven squares off" do
      game = hall
      game.floor.drop 27, 5, Item.new Kind::Spear

      expect(game.can_see? 27, 5).to be_true
      expect(game.regard_of_item 27, 5).to eq Regard::Everything
    end

    it "is made out as its kind nine squares off" do
      game = hall
      game.floor.drop 29, 5, Item.new Kind::Spear

      expect(game.can_see? 29, 5).to be_true
      expect(game.regard_of_item 29, 5).to eq Regard::Kind
    end

    it "is nothing at all on a square the character has never seen" do
      game = hall_of UNLIT

      expect(game.can_see? 9, 1).to be_false
      expect(game.regard_of_item 9, 1).to eq Regard::Nothing
    end
  end

  describe "a closer look" do
    it "is not undone by a later distant one" do
      game = hall
      game.floor.drop 29, 5, Item.new Kind::Spear
      game.look
      expect(game.regard_of_item 29, 5).to eq Regard::Kind

      game.player.move_to 27, 5
      game.look
      expect(game.regard_of_item 29, 5).to eq Regard::Everything

      game.player.move_to 20, 5
      game.look
      expect(game.regard_of_item 29, 5).to eq Regard::Everything
      expect(game.knowledge[29, 5].try &.regard).to eq Regard::Everything
    end

    it "is not carried over to a different item on the square" do
      game = hall
      spear = Item.new Kind::Spear
      game.floor.drop 29, 5, spear
      game.player.move_to 27, 5
      game.look
      expect(game.regard_of_item 29, 5).to eq Regard::Everything

      game.player.move_to 20, 5
      game.floor.take 29, 5, spear
      game.floor.drop 29, 5, Item.new Kind::TeleportScroll
      game.look

      expect(game.regard_of_item 29, 5).to eq Regard::Kind
      expect(game.knowledge[29, 5].try &.regard).to eq Regard::Kind
    end

    # `Knowledge#see` is where the rule lives. This is the same thing without
    # a game around it.
    it "survives a distant look at the same square" do
      floor = Playing.daylight Floor.parse("room", ["#####", "#...#", "#####"])
      floor.drop 2, 1, Item.new Kind::Spear
      knowledge = Knowledge.new floor.id

      knowledge.see floor, 2, 1, 1, Regard::Everything
      knowledge.see floor, 2, 1, 2, Regard::Kind

      memory = knowledge[2, 1]
      raise "the square was not remembered" unless memory

      expect(memory.regard).to eq Regard::Everything
      expect(memory.turn).to eq 2
    end
  end

  describe "a creature" do
    it "is a shape and no more when it shows against light behind it" do
      game = hall_of BACKLIT

      expect(game.sight.backlit? game.floor, 7, 1).to be_true
      expect(game.regard_of goblin(game)).to eq Regard::Shape
    end

    it "is made out in full when there is light on it" do
      game = hall_of BACKLIT, lit: true

      expect(game.regard_of goblin(game)).to eq Regard::Everything
    end

    it "is nothing at all with no light on it and none behind it" do
      game = hall_of UNLIT

      expect(game.regard_of goblin(game)).to eq Regard::Nothing
    end

    it "is called by its size rather than its species" do
      expect(Size::Small.label).to eq "a small shape"
      expect(Size::Medium.label).to eq "a shape"
      expect(Size::Large.label).to eq "a large shape"

      expect(Size::Small.short).to eq "sml shape"
      expect(Size::Medium.short).to eq "med shape"
      expect(Size::Large.short).to eq "lrg shape"
    end
  end

  describe "naming" do
    let(lore) { Lore.roll Roguelike::Rng.new Playing::SEED }

    let(spear) do
      Item.new Kind::Spear, enchantment: -2,
        blessing: Blessing::Cursed, blessing_known: true
    end

    it "writes everything about an item when no regard is given" do
      expect(lore.name spear).to eq "a cursed -2 spear"
      expect(lore.name spear).to eq lore.name(spear, regard: Regard::Everything)

      expect(Naming.short lore, spear).to eq "crs -2 spear"
      expect(Naming.short lore, spear).to eq Naming.short(lore, spear, Regard::Everything)
    end

    it "writes the kind and no more at a distance" do
      expect(lore.name spear, regard: Regard::Kind).to eq "a spear"
      expect(Naming.short lore, spear, Regard::Kind).to eq "spear"
    end

    it "calls a scroll a scroll rather than what is written on it" do
      scroll = Item.new Kind::TeleportScroll
      look = lore.appearance Kind::TeleportScroll

      expect(lore.name scroll).to eq "a scroll #{look}"
      expect(lore.name scroll, regard: Regard::Kind).to eq "a scroll"
      expect(Naming.short lore, scroll, Regard::Kind).to eq "scroll"
    end

    it "calls a potion a potion rather than a colour" do
      potion = Item.new Kind::HealingPotion, count: 3

      expect(lore.name potion, regard: Regard::Kind).to eq "3 potions"
      expect(Naming.short lore, potion, Regard::Kind).to eq "3 potion"
    end

    it "calls a wand a wand rather than what it is made of" do
      wand = Item.new Kind::LightWand

      expect(lore.name wand, regard: Regard::Kind).to eq "a wand"
    end

    it "leaves a thing that is what it looks like alone" do
      expect(lore.name Item.new(Kind::ChainMail), regard: Regard::Kind).to eq "chain mail"
    end

    it "names an item held in the pack the way it always has" do
      game = Playing.field 20, 10
      item = Item.new Kind::Spear, enchantment: 1

      expect(game.name item).to eq "a +1 spear"
      expect(game.name item, Regard::Kind).to eq "a spear"
    end
  end

  describe "a saved character" do
    it "carries how well each square's item was made out" do
      kept = Playing.store
      game = Playing.field 40, 11
      game.player.name = "Sparky"
      game.floor.drop 29, 5, Item.new Kind::Spear
      game.look

      expect(game.knowledge[29, 5].try &.regard).to eq Regard::Kind

      kept.write game
      back = kept.read "Sparky"
      raise "nothing was read back" unless back

      expect(back.knowledge[29, 5].try &.regard).to eq Regard::Kind
      expect(back.knowledge[20, 5].try &.regard).to eq Regard::Everything
    end

    # What a save written before this field held. A square nobody had walked
    # up to was named in full anyway, so loading it as `Everything` is what
    # that file meant.
    it "loads a square written before the field existed" do
      written = %({"terrain":"stone_floor","item":null,"turn":4})

      expect(Memory.from_json(written).regard).to eq Regard::Everything
    end

    it "round-trips a square made out from a distance" do
      memory = Memory.new Terrain::StoneFloor, nil, Item.new(Kind::Spear), 4, Regard::Kind
      back = Memory.from_json memory.to_json

      expect(back.regard).to eq Regard::Kind
      expect(back).to eq memory
    end
  end
end
