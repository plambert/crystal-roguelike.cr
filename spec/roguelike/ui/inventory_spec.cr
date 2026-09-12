require "../../spec_helper"

Spectator.describe "picking up and dropping" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item

  # A one room floor with the character in the middle, holding *items*.
  def litter(items : Array(Item) = [] of Item) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", "#####\n#...#\n#.<.#\n#...#\n#####")
    floor.clear_items 2, 2
    items.each { |item| floor.drop 2, 2, item }

    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}),
      Roguelike::Player.new("room", 2, 2)

    Playing.open game
  end

  describe "," do
    it "says so when there is nothing here" do
      run = litter

      run.press ","

      expect(run.said).to contain "nothing here to pick up"
    end

    it "takes one thing without asking" do
      run = litter [Item.new(Kind::Dagger)]

      run.press ","

      expect(run.menu.showing?).to be_false
      expect(run.game.player.inventory['a'].try &.kind).to eq Kind::Dagger
    end

    # A person standing on a pile has to say which.
    it "asks which when there is more than one" do
      run = litter [Item.new(Kind::Dagger), Item.new(Kind::LongSword)]

      run.press ","

      expect(run.menu.showing?).to be_true
      expect(run.menu.entries.size).to eq 2
    end

    it "takes the one the letter names" do
      run = litter [Item.new(Kind::Dagger), Item.new(Kind::LongSword)]

      run.press ","
      run.press "b"

      expect(run.game.player.inventory['a'].try &.kind).to eq Kind::LongSword
      expect(run.game.here.size).to eq 1
    end

    it "takes nothing on Escape" do
      run = litter [Item.new(Kind::Dagger), Item.new(Kind::LongSword)]

      run.press ","
      run.press "Escape"

      expect(run.game.player.inventory).to be_empty
      expect(run.game.here.size).to eq 2
      expect(run.menu.showing?).to be_false
    end
  end

  describe "d" do
    it "says so when the character carries nothing" do
      run = litter

      run.press "d"

      expect(run.said).to contain "carrying nothing"
    end

    it "asks which to drop" do
      run = litter [Item.new(Kind::Dagger)]
      run.press ","

      run.press "d"

      expect(run.menu.showing?).to be_true
      expect(run.menu.entries.map &.key).to eq ['a']
    end

    it "drops the one the letter names" do
      run = litter [Item.new(Kind::Dagger)]
      run.press ","

      run.press "d"
      run.press "a"

      expect(run.game.player.inventory).to be_empty
      expect(run.game.here.size).to eq 1
    end
  end

  describe "i" do
    it "says so when the character carries nothing" do
      run = litter

      run.press "i"

      expect(run.said).to contain "carrying nothing"
    end

    it "lists what is carried, by letter" do
      run = litter [Item.new(Kind::Dagger), Item.new(Kind::Arrow, count: 9)]
      run.press ","
      run.press "a"
      run.press ","

      run.press "i"

      expect(run.menu.showing?).to be_true
      expect(run.menu.entries.map &.text).to contain "a dagger"
      expect(run.menu.entries.map &.text).to contain "9 arrows"
    end

    it "closes on Escape" do
      run = litter [Item.new(Kind::Dagger)]
      run.press ","

      run.press "i"
      run.press "Escape"

      expect(run.menu.showing?).to be_false
    end
  end

  describe "the map" do
    it "draws what is lying on a square" do
      run = litter [Item.new(Kind::Dagger)]

      expect(run.map.mark?(2, 2)).to eq Roguelike::Ui::Palette::PLAYER

      run.press "l"
      expect(run.map.mark?(2, 2))
        .to eq Roguelike::Ui::Palette[Item.new(Kind::Dagger)]
    end

    it "draws each class with its own glyph" do
      expect(Roguelike::Ui::Palette[Item.new(Kind::Dagger)].glyph).to eq ')'
      expect(Roguelike::Ui::Palette[Item.new(Kind::Cap)].glyph).to eq '['
      expect(Roguelike::Ui::Palette[Item.new(Kind::HealingPotion)].glyph).to eq '!'
      expect(Roguelike::Ui::Palette[Item.new(Kind::IdentifyScroll)].glyph).to eq '?'
      expect(Roguelike::Ui::Palette[Item.new(Kind::LightWand)].glyph).to eq '/'
      expect(Roguelike::Ui::Palette[Item.new(Kind::Torch)].glyph).to eq '('
      expect(Roguelike::Ui::Palette[Item.new(Kind::Gold)].glyph).to eq '$'
    end

    it "stops drawing an item once it is picked up" do
      run = litter [Item.new(Kind::Dagger)]

      run.press ","
      run.press "l"

      expect(run.map.mark?(2, 2)).to be_nil
    end
  end

  describe "the examine pane" do
    it "lists what is on a square" do
      run = litter [Item.new(Kind::Dagger), Item.new(Kind::Arrow, count: 3)]

      run.hover 2, 2

      expect(run.examine.litter.text).to contain "a dagger"
      expect(run.examine.litter.text).to contain "3 arrows"
    end

    it "says nothing about a bare square" do
      run = litter [Item.new(Kind::Dagger)]

      run.hover 1, 1

      expect(run.examine.litter.hidden?).to be_true
    end
  end

  describe "the status line" do
    it "counts the gold" do
      run = litter [Item.new(Kind::Gold, count: 25)]

      run.press ","

      expect(run.play.status_line.bar["gold"]?.try &.text).to eq "25"
    end

    it "leaves no letter for the gold" do
      run = litter [Item.new(Kind::Gold, count: 25)]

      run.press ","

      expect(run.game.player.inventory).to be_empty
    end
  end

  describe "a menu on the screen" do
    it "dims what is behind it" do
      run = litter [Item.new(Kind::Dagger)]
      run.press ","
      wall = run.buffer.hit(0, 0).try &.cell.style

      run.press "i"

      expect(run.buffer.hit(0, 0).try &.cell.style).not_to eq wall
    end

    # A menu that let other keys through would walk the character while the
    # person was reading it.
    it "swallows a movement key" do
      run = litter [Item.new(Kind::Dagger)]
      run.press ","
      start = run.at

      run.press "i"
      run.press "l"

      expect(run.at).to eq start
      expect(run.menu.showing?).to be_true
    end

    it "draws what it drew last time" do
      run = litter [Item.new(Kind::Dagger), Item.new(Kind::Arrow, count: 9)]
      run.press ","
      run.press "a"
      run.press ","
      run.press "i"

      drawn = run.text
      expect(drawn).to eq Fixture.expected("screen/inventory-menu.txt", drawn)
    end
  end
end
