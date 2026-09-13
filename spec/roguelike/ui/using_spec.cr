require "../../spec_helper"

Spectator.describe "quaffing, reading and zapping" do
  alias Aiming = Roguelike::Ui::Aiming
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Species = Roguelike::Species

  # One lit hall with the character at the west end.
  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "#..........#",
    "############",
  ]

  # Where the character stands.
  HERE = {1, 1}

  # A run with the character carrying *items*.
  def carrying(items : Array(Item) = [] of Item, dark : Bool = false) : Playing::Run
    floor = Roguelike::Floor.parse "hall", HALL
    Playing.daylight floor unless dark

    player = Roguelike::Player.new "hall", *HERE, hit_points: 1
    items.each { |item| player.inventory.add item }

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}), player)
  end

  # The letters the menu on the screen is offering.
  def offered(run : Playing::Run) : Array(Char)
    run.menu.entries.map &.key
  end

  describe "q" do
    it "says so when the character has nothing to drink" do
      run = carrying [Item.new Kind::Dagger]

      run.press "q"

      expect(run.said).to contain "nothing to drink"
      expect(run.menu.showing?).to be_false
    end

    it "offers only the potions" do
      run = carrying [Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)]

      run.press "q"

      expect(offered run).to eq ['b']
    end

    it "drinks the one that was chosen" do
      run = carrying [Item.new Kind::HealingPotion]
      before = run.game.player.hit_points

      run.press "q", "a"

      expect(run.game.player.hit_points).to be > before
      expect(run.game.player.inventory.has? 'a').to be_false
    end
  end

  describe "r" do
    it "says so when the character has nothing to read" do
      run = carrying [Item.new Kind::HealingPotion]

      run.press "r"

      expect(run.said).to contain "nothing to read"
    end

    it "reads a scroll that needs no second question" do
      run = carrying [Item.new Kind::MappingScroll]

      run.press "r", "a"

      expect(run.menu.showing?).to be_false
      expect(run.game.knowledge.seen? 10, 3).to be_true
    end

    it "asks which item a scroll of identify names" do
      run = carrying [Item.new(Kind::IdentifyScroll), Item.new(Kind::HealingPotion)]

      run.press "r", "a"

      expect(run.menu.showing?).to be_true
      expect(offered run).to eq ['b']
    end

    it "names the item that was chosen" do
      run = carrying [Item.new(Kind::IdentifyScroll), Item.new(Kind::HealingPotion)]

      run.press "r", "a"
      run.press "b"

      expect(run.game.lore.known? Kind::HealingPotion).to be_true
      expect(run.game.player.inventory.has? 'a').to be_false
    end

    it "says so in the dark, without offering anything" do
      run = carrying [Item.new Kind::MappingScroll], dark: true

      run.press "r"

      expect(run.said).to eq "It is too dark to read."
      expect(run.menu.showing?).to be_false
      expect(run.game.player.inventory.has? 'a').to be_true
    end

    it "reads by the light of a carried torch" do
      run = carrying [Item.new(Kind::MappingScroll), Playing.torch], dark: true

      run.press "r", "a"

      expect(run.game.player.inventory.has? 'a').to be_false
    end

    # Offering an empty list would be a question with no answer.
    it "reads the scroll anyway when there is nothing left to name" do
      run = carrying [Item.new Kind::IdentifyScroll]

      run.press "r", "a"

      expect(run.menu.showing?).to be_false
      expect(run.game.player.inventory.has? 'a').to be_false
      expect(run.log).to contain "You feel knowledgeable, and the feeling passes."
    end
  end

  describe "z" do
    it "says so when the character has nothing to zap" do
      run = carrying [Item.new Kind::HealingPotion]

      run.press "z"

      expect(run.said).to contain "nothing to zap"
    end

    it "zaps a wand of light where the character stands" do
      run = carrying [Item.new Kind::LightWand], dark: true

      run.press "z", "a"

      expect(run.play.aiming).to be_nil
      expect(run.game.floor.glow_at 3, 1).to be > 0
    end

    it "puts the targeting cursor up for a wand of striking" do
      run = carrying [Item.new Kind::StrikingWand]

      run.press "z", "a"

      expect(run.play.aiming).to eq Aiming::Zap
      expect(run.examiner.cursoring?).to be_true
    end

    it "aims at the nearest monster" do
      run = carrying [Item.new Kind::StrikingWand]
      run.game.floor.place Monster.new(Species::Goblin, 5, 1, "band-one", hit_points: 200)
      run.play.refresh

      run.press "z", "a"

      expect(run.examiner.spot).to eq({5, 1})
    end

    it "looses the bolt on Enter" do
      run = carrying [Item.new Kind::StrikingWand]
      run.game.floor.place Monster.new(Species::Goblin, 5, 1, "band-one", hit_points: 200)
      run.play.refresh

      run.press "z", "a"
      run.press "Enter"

      expect(run.play.aiming).to be_nil
      expect(run.log.join " ").to match /bolt (hits|misses) the goblin/
    end

    it "spends a charge only when the bolt goes" do
      run = carrying [Item.new Kind::StrikingWand]
      full = Kind::StrikingWand.charges

      run.press "z", "a"
      expect(run.game.player.inventory['a'].try &.charges).to eq full

      run.press "Enter"
      expect(run.game.player.inventory['a'].try &.charges).to eq full - 1
    end

    it "costs no charge and no turn when the aim is cancelled" do
      run = carrying [Item.new Kind::StrikingWand]
      before = run.turn

      run.press "z", "a"
      run.press "Escape"

      expect(run.play.aiming).to be_nil
      expect(run.turn).to eq before
      expect(run.game.player.inventory['a'].try &.charges).to eq Kind::StrikingWand.charges
    end
  end
end
