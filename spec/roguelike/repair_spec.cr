require "../spec_helper"

Spectator.describe "a scroll of repair" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Blessing = Roguelike::Blessing
  alias Condition = Roguelike::Condition

  # A lit room with the character in the middle and nothing on the floor.
  def bare : Roguelike::Game
    floor = Roguelike::Floor.parse "room", "#####\n#...#\n#.<.#\n#...#\n#####"
    floor.clear_items 2, 2
    floor.ambient = 1

    Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}),
      Roguelike::Player.new("room", 2, 2)
  end

  # Puts a scroll of repair in *game*'s pack and answers its letter.
  def reading(game : Roguelike::Game,
              blessing : Blessing = Blessing::Uncursed) : Char
    letter = game.player.inventory.add Item.new(Kind::RepairScroll, blessing: blessing)
    raise "no room" unless letter
    letter
  end

  # Puts *item* in the pack and answers its letter.
  def carrying(game : Roguelike::Game, item : Item) : Char
    letter = game.player.inventory.add item
    raise "no room" unless letter
    letter
  end

  describe "read on what is damaged" do
    it "takes the damage out" do
      game = bare
      mace = carrying game, Item.new(Kind::Mace, condition: Condition::Damaged)

      game.read reading(game), mace

      expect(game.player.inventory[mace].try &.condition).to eq Condition::Plain
    end

    it "says so, naming what was wrong with it" do
      game = bare
      mace = carrying game, Item.new(Kind::Mace, condition: Condition::Damaged)

      game.read reading(game), mace

      expect(game.log.last?.to_s).to eq "A damaged mace is as good as new."
    end

    it "agrees with a stack" do
      game = bare
      arrows = carrying game,
        Item.new(Kind::Arrow, count: 6, condition: Condition::Damaged)

      game.read reading(game), arrows

      expect(game.log.last?.to_s).to eq "6 damaged arrows are as good as new."
    end

    # A masterwork item is better than plain. Mending undoes wear; it does
    # not take the making out.
    it "leaves a masterwork item alone" do
      game = bare
      sword = carrying game,
        Item.new(Kind::LongSword, condition: Condition::Masterwork)

      game.read reading(game), sword

      expect(game.player.inventory[sword].try &.condition).to eq Condition::Masterwork
      expect(game.log.last?.to_s).to contain "Nothing about"
    end

    it "says so when it was given nothing to work on" do
      game = bare

      game.read reading(game), nil

      expect(game.log.last?.to_s).to contain "writing fades"
    end

    it "is used up either way" do
      game = bare
      letter = reading game

      game.read letter, nil

      expect(game.player.inventory.has? letter).to be_false
    end
  end

  describe "read blessed" do
    it "mends everything carried" do
      game = bare
      mace = carrying game, Item.new(Kind::Mace, condition: Condition::Damaged)
      cap = carrying game, Item.new(Kind::Cap, condition: Condition::Damaged)

      game.read reading(game, Blessing::Blessed)

      expect(game.player.inventory[mace].try &.condition).to eq Condition::Plain
      expect(game.player.inventory[cap].try &.condition).to eq Condition::Plain
    end

    it "mends what is lying underfoot" do
      game = bare
      game.floor.drop 2, 2, Item.new(Kind::Spear, condition: Condition::Damaged)

      game.read reading(game, Blessing::Blessed)

      expect(game.here.first.condition).to eq Condition::Plain
    end

    it "leaves what is lying on the next square" do
      game = bare
      game.floor.drop 3, 2, Item.new(Kind::Spear, condition: Condition::Damaged)

      game.read reading(game, Blessing::Blessed)

      expect(game.floor.items(3, 2).first.condition).to eq Condition::Damaged
    end

    it "says how many it mended" do
      game = bare
      carrying game, Item.new(Kind::Mace, condition: Condition::Damaged)
      carrying game, Item.new(Kind::Cap, condition: Condition::Damaged)

      game.read reading(game, Blessing::Blessed)

      expect(game.log.last?.to_s).to eq "2 of them are as good as new."
    end

    it "says so when nothing was broken" do
      game = bare
      carrying game, Item.new(Kind::Mace)

      game.read reading(game, Blessing::Blessed)

      expect(game.log.last?.to_s).to contain "Nothing within reach was broken."
    end
  end

  describe "read cursed" do
    it "damages something that was whole" do
      game = bare
      mace = carrying game, Item.new(Kind::Mace)

      game.read reading(game, Blessing::Cursed)

      expect(game.player.inventory[mace].try &.condition).to eq Condition::Damaged
    end

    it "says what it broke" do
      game = bare
      carrying game, Item.new(Kind::Mace)

      game.read reading(game, Blessing::Cursed)

      expect(game.log.last?.to_s).to eq "A mace buckles and cracks."
    end

    it "agrees with a stack" do
      game = bare
      carrying game, Item.new(Kind::Arrow, count: 6)

      game.read reading(game, Blessing::Cursed)

      expect(game.log.last?.to_s).to eq "6 arrows buckle and crack."
    end

    it "leaves what is damaged already alone" do
      game = bare
      mace = carrying game, Item.new(Kind::Mace, condition: Condition::Damaged)

      game.read reading(game, Blessing::Cursed)

      expect(game.player.inventory[mace].try &.condition).to eq Condition::Damaged
      expect(game.log.last?.to_s).to contain "writing fades"
    end

    # A condition means nothing on a potion, and a cracked wand is the way
    # out of a cursed one. Neither is something this breaks.
    it "leaves alone what a condition means nothing on" do
      game = bare
      potion = carrying game, Item.new(Kind::HealingPotion)
      wand = carrying game, Item.new(Kind::StrikingWand)

      game.read reading(game, Blessing::Cursed)

      expect(game.player.inventory[potion].try &.condition).to eq Condition::Plain
      expect(game.player.inventory[wand].try &.condition).to eq Condition::Plain
      expect(game.log.last?.to_s).to contain "writing fades"
    end

    it "breaks what is worn as readily as what is carried" do
      game = bare
      armour = carrying game, Item.new(Kind::LeatherArmour)
      game.wear armour

      game.read reading(game, Blessing::Cursed)

      expect(game.player.inventory[armour].try &.condition).to eq Condition::Damaged
    end
  end

  describe "the reading itself" do
    it "spends one turn" do
      game = bare
      carrying game, Item.new(Kind::Mace, condition: Condition::Damaged)
      before = game.turn

      game.read reading(game), 'b'

      expect(game.turn).to eq before + 1
    end

    # A game each. Three scrolls differing only in a blessing nobody knows
    # about look alike, so all three would sit under one letter.
    it "asks which item only while nothing has touched it" do
      plain = bare
      blessed = bare
      cursed = bare

      expect(plain.choice_needed? reading(plain)).to be_true
      expect(blessed.choice_needed? reading(blessed, Blessing::Blessed)).to be_false
      expect(cursed.choice_needed? reading(cursed, Blessing::Cursed)).to be_false
    end

    it "needs no marks first and no square" do
      game = bare
      letter = reading game

      expect(game.marks_first? letter).to be_false
      expect(game.target_needed? letter).to be_false
    end

    it "names the kind once it has been read" do
      game = bare

      game.read reading(game), nil

      expect(game.lore.known? Kind::RepairScroll).to be_true
    end
  end
end
