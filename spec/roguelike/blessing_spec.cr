require "../spec_helper"

Spectator.describe "blessing and uncursing" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Blessing = Roguelike::Blessing

  # A lit one room floor with the character in the middle and nothing on it.
  #
  # Reading needs light, and `#cannot_read` refuses a character standing in
  # the dark before it offers them a scroll.
  def bare(seed : UInt64 = Playing::SEED) : Roguelike::Game
    floor = Roguelike::Floor.parse "room", "#####\n#...#\n#.<.#\n#...#\n#####"
    floor.clear_items 2, 2
    floor.ambient = 1

    Roguelike::Game.new Roguelike::World.new(seed, {"room" => floor}),
      Roguelike::Player.new("room", 2, 2)
  end

  # A scroll of *kind* under a letter, with the blessing given.
  def carrying(game : Roguelike::Game, kind : Kind,
               blessing : Blessing = Blessing::Uncursed) : Char
    letter = game.player.inventory.add Item.new(kind, blessing: blessing)
    raise "no room" unless letter
    letter
  end

  describe "a scroll of blessing" do
    it "marks what a god has touched and leaves the rest alone" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll
      cursed = Item.new Kind::Dagger, blessing: Blessing::Cursed
      blessed = Item.new Kind::Mace, blessing: Blessing::Blessed
      plain = Item.new Kind::Spear
      [cursed, blessed, plain].each { |item| game.player.inventory.add item }

      game.start_reading scroll

      expect(cursed.blessing_known?).to be_true
      expect(blessed.blessing_known?).to be_true
      expect(plain.blessing_known?).to be_false
    end

    it "blesses the one the character picked" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll
      sword = Item.new Kind::LongSword
      letter = game.player.inventory.add sword
      raise "no room" unless letter

      spent = game.start_reading scroll
      raise "no scroll" unless spent
      game.finish_reading spent, letter

      expect(sword.blessed?).to be_true
      expect(sword.blessing_known?).to be_true
    end

    it "spends the scroll and the turn on the first half" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll
      before = game.turn

      game.start_reading scroll

      expect(game.player.inventory.has? scroll).to be_false
      expect(game.turn).to eq before + 1
    end

    it "spends no second turn on the choice" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll
      letter = game.player.inventory.add Item.new(Kind::LongSword)
      raise "no room" unless letter

      spent = game.start_reading scroll
      raise "no scroll" unless spent
      after = game.turn
      game.finish_reading spent, letter

      expect(game.turn).to eq after
    end

    it "gives nothing away when the character picks nothing" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll
      sword = Item.new Kind::LongSword
      game.player.inventory.add sword

      spent = game.start_reading scroll
      raise "no scroll" unless spent
      game.finish_reading spent, nil

      expect(sword.blessed?).to be_false
    end

    it "asks nothing when it is blessed" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll, Blessing::Blessed

      expect(game.choice_needed? scroll).to be_false
      expect(game.marks_first? scroll).to be_false
    end

    it "asks when nothing has touched it" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll

      expect(game.choice_needed? scroll).to be_true
      expect(game.marks_first? scroll).to be_true
    end
  end

  describe "a blessed scroll" do
    it "blesses everything carried" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll, Blessing::Blessed
      carried = [Item.new(Kind::LongSword), Item.new(Kind::Mace),
                 Item.new(Kind::Cap)]
      carried.each { |item| game.player.inventory.add item }

      game.read scroll

      expect(carried.all? &.blessed?).to be_true
    end

    it "blesses what is lying underfoot as well" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll, Blessing::Blessed
      underfoot = Item.new Kind::LongSword
      game.floor.drop 2, 2, underfoot

      game.read scroll

      expect(underfoot.blessed?).to be_true
    end

    it "leaves what is lying elsewhere alone" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll, Blessing::Blessed
      elsewhere = Item.new Kind::LongSword
      game.floor.drop 1, 1, elsewhere

      game.read scroll

      expect(elsewhere.blessed?).to be_false
    end

    # Two scrolls of blessing are worth more than one used twice.
    it "is what one scroll of blessing makes of another" do
      game = bare
      first = carrying game, Kind::BlessingScroll
      second = carrying game, Kind::BlessingScroll
      sword = Item.new Kind::LongSword
      game.player.inventory.add sword

      spent = game.start_reading first
      raise "no scroll" unless spent
      game.finish_reading spent, second

      held = game.player.inventory[second]
      raise "no scroll" unless held
      expect(held.blessed?).to be_true

      game.read second

      expect(sword.blessed?).to be_true
    end
  end

  describe "a scroll of remove curse" do
    it "marks the curses and nothing else" do
      game = bare
      scroll = carrying game, Kind::RemoveCurseScroll
      cursed = Item.new Kind::Dagger, blessing: Blessing::Cursed
      blessed = Item.new Kind::Mace, blessing: Blessing::Blessed
      [cursed, blessed].each { |item| game.player.inventory.add item }

      game.start_reading scroll

      expect(cursed.blessing_known?).to be_true
      expect(blessed.blessing_known?).to be_false
    end

    it "lifts the curse off the one the character picked" do
      game = bare
      scroll = carrying game, Kind::RemoveCurseScroll
      cursed = Item.new Kind::Dagger, blessing: Blessing::Cursed
      letter = game.player.inventory.add cursed
      raise "no room" unless letter

      spent = game.start_reading scroll
      raise "no scroll" unless spent
      game.finish_reading spent, letter

      expect(cursed.cursed?).to be_false
      expect(cursed.blessed?).to be_false
    end

    it "frees a cursed sword from the hand" do
      game = bare
      scroll = carrying game, Kind::RemoveCurseScroll, Blessing::Blessed
      cursed = Item.new Kind::LongSword, blessing: Blessing::Cursed
      letter = game.player.inventory.add cursed
      raise "no room" unless letter
      game.wield letter

      expect(game.take_off Roguelike::Slot::Melee).to be_false

      game.read scroll

      expect(game.take_off Roguelike::Slot::Melee).to be_true
    end
  end

  describe "a cursed scroll" do
    # It helps rather than harms, and it aims badly.
    it "blesses something it picked itself" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll, Blessing::Cursed
      carried = [Item.new(Kind::LongSword), Item.new(Kind::Mace)]
      carried.each { |item| game.player.inventory.add item }

      game.read scroll

      expect(carried.count &.blessed?).to eq 1
    end

    it "names what it settled on" do
      game = bare
      scroll = carrying game, Kind::BlessingScroll, Blessing::Cursed
      game.player.inventory.add Item.new(Kind::LongSword)

      game.read scroll

      expect(game.log.lines.any? &.includes?("picks out")).to be_true
    end

    # Nothing is cursed, so lifting a curse has nothing to lift.
    it "usually does nothing at all on a scroll of remove curse" do
      misses = 0

      20.times do |index|
        game = bare Playing::SEED + index.to_u64
        scroll = carrying game, Kind::RemoveCurseScroll, Blessing::Cursed
        game.player.inventory.add Item.new(Kind::LongSword)
        game.player.inventory.add Item.new(Kind::Mace)

        game.read scroll
        misses += 1 if game.log.lines.any? &.includes?("to no effect")
      end

      expect(misses).to eq 20
    end

    # Three times in four it looks only at what it could change. The fourth
    # time it looks at everything, and lands on something it cannot.
    it "lands on something already blessed some of the time" do
      astray = 0

      400.times do |index|
        game = bare Playing::SEED + index.to_u64
        scroll = carrying game, Kind::BlessingScroll, Blessing::Cursed
        game.player.inventory.add Item.new(Kind::LongSword,
          blessing: Blessing::Blessed)
        game.player.inventory.add Item.new(Kind::Mace)

        game.read scroll
        astray += 1 if game.log.lines.any? &.includes?("to no effect")
      end

      expect(astray).to be > 20
      expect(astray).to be < 120
    end
  end

  describe "a potion" do
    it "puts back half as much when it is cursed" do
      expect(Blessing::Cursed.potency).to eq 50
    end

    it "puts back double when it is blessed" do
      expect(Blessing::Blessed.potency).to eq 200
    end

    it "heals less from a cursed draught than from a blessed one" do
      hurt = ->(blessing : Blessing) do
        total = 0

        40.times do |index|
          game = bare Playing::SEED + index.to_u64
          game.player.hurt 100
          letter = game.player.inventory.add Item.new(Kind::HealingPotion,
            blessing: blessing)
          raise "no room" unless letter

          before = game.player.hit_points
          game.quaff letter
          total += game.player.hit_points - before
        end

        total
      end

      expect(hurt.call Blessing::Cursed).to be < hurt.call(Blessing::Uncursed)
      expect(hurt.call Blessing::Blessed).to be > hurt.call(Blessing::Uncursed)
    end

    it "tells the character what they drank" do
      game = bare
      letter = game.player.inventory.add Item.new(Kind::HealingPotion,
        blessing: Blessing::Cursed)
      raise "no room" unless letter
      game.player.hurt 5
      game.quaff letter

      expect(game.log.lines.any? &.includes?("cursed")).to be_true
    end
  end
end
