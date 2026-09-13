require "../../spec_helper"

Spectator.describe "wielding, wearing and taking off" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Slot = Roguelike::Slot
  alias Widgets = Roguelike::Ui::Widgets

  # A one room floor with the character in the middle, carrying *items*.
  def carrying(items : Array(Item) = [] of Item) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", "#####\n#...#\n#.<.#\n#...#\n#####")
    floor.clear_items 2, 2

    player = Roguelike::Player.new "room", 2, 2
    items.each { |item| player.inventory.add item }

    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}),
      player

    Playing.open game
  end

  # The letter of the row whose text holds *text*.
  def row_for(run : Playing::Run, text : String) : Char
    found = run.menu.entries.find &.text.includes?(text)
    raise "no menu row holds #{text.inspect}" unless found

    found.key
  end

  describe "w" do
    it "says so when the character has nothing to wield" do
      run = carrying

      run.press "w"

      expect(run.said).to contain "nothing to wield"
      expect(run.menu.showing?).to be_false
    end

    it "puts a sword in the hand" do
      run = carrying [Item.new Kind::LongSword]

      run.press "w"
      run.press "a"

      expect(run.game.player.wielded.try &.kind).to eq Kind::LongSword
      expect(run.said).to contain "now holding"
    end

    it "puts a bow in the ranged slot rather than the hand" do
      run = carrying [Item.new Kind::Bow]

      run.press "w"
      run.press "a"

      expect(run.game.player.launcher.try &.kind).to eq Kind::Bow
      expect(run.game.player.wielded).to be_nil
    end

    it "puts arrows in the quiver" do
      run = carrying [Item.new(Kind::Arrow, count: 20)]

      run.press "w"
      run.press "a"

      expect(run.game.player.quivered.try &.kind).to eq Kind::Arrow
    end

    # One key readies all three weapon slots, so the message has to say which
    # one it filled. Arrows announced as held read as arrows in the hand.
    it "says arrows went in the quiver rather than in the hand" do
      run = carrying [Item.new(Kind::Arrow, count: 12)]

      run.press "w"
      run.press "a"

      expect(run.said).to contain "in your quiver"
      expect(run.said).not_to contain "holding"
    end

    it "says a bow is held and its arrows are quivered" do
      run = carrying [Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 12)]

      run.press "w"
      run.press row_for(run, "bow").to_s
      first = run.said

      run.press "w"
      run.press row_for(run, "arrow").to_s

      expect(first).to contain "now holding"
      expect(run.said).to contain "in your quiver"
    end

    it "takes arrows out of the quiver rather than letting go of them" do
      run = carrying [Item.new(Kind::Arrow, count: 12)]

      run.press "w"
      run.press "a"
      run.press "T"

      expect(run.game.player.quivered).to be_nil
      expect(run.said).to contain "out of your quiver"
    end

    # Everything readied at once. One key fills all three weapon slots.
    it "fills the three weapon slots from one key" do
      run = carrying [Item.new(Kind::Mace), Item.new(Kind::Sling),
                      Item.new(Kind::Stone, count: 8)]

      3.times do |index|
        run.press "w"
        run.press Widgets::Menu.letter(index).to_s
      end

      expect(run.game.player.wielded.try &.kind).to eq Kind::Mace
      expect(run.game.player.launcher.try &.kind).to eq Kind::Sling
      expect(run.game.player.quivered.try &.kind).to eq Kind::Stone
    end

    it "offers nothing that is worn or drunk" do
      run = carrying [Item.new(Kind::LongSword), Item.new(Kind::ChainMail),
                      Item.new(Kind::HealingPotion)]

      run.press "w"

      expect(run.menu.entries.size).to eq 1
      expect(run.menu.entries.first.text).to contain "long sword"
    end

    it "swaps what is in the hand" do
      run = carrying [Item.new(Kind::Dagger), Item.new(Kind::LongSword)]

      run.press "w"
      run.press row_for(run, "dagger").to_s
      run.press "w"
      run.press row_for(run, "long sword").to_s

      expect(run.game.player.wielded.try &.kind).to eq Kind::LongSword
      expect(run.game.player.equipment.size).to eq 1
    end

    it "takes a turn" do
      run = carrying [Item.new Kind::LongSword]

      run.press "w"
      run.press "a"

      expect(run.turn).to eq 1
    end
  end

  describe "W" do
    it "says so when the character has nothing to wear" do
      run = carrying [Item.new Kind::LongSword]

      run.press "W"

      expect(run.said).to contain "nothing to wear"
    end

    it "puts armour on" do
      run = carrying [Item.new Kind::ChainMail]

      run.press "W"
      run.press "a"

      expect(run.game.player.armour_class).to eq 4
      expect(run.said).to contain "now wearing"
    end

    it "fills every armour slot" do
      run = carrying [Kind::ChainMail, Kind::Shield, Kind::Cap, Kind::Boots,
                      Kind::Gloves].map { |kind| Item.new kind }

      5.times do |index|
        run.press "W"
        run.press Widgets::Menu.letter(index).to_s
      end

      expect(run.game.player.worn.size).to eq 5
      expect(run.game.player.armour_class).to eq 9
    end

    # A person takes one thing off before they put another on. Saying so is
    # clearer than doing it for them.
    it "refuses a second piece in one slot" do
      run = carrying [Item.new(Kind::ChainMail), Item.new(Kind::LeatherArmour)]

      run.press "W"
      run.press row_for(run, "chain mail").to_s
      run.press "W"
      run.press row_for(run, "leather armour").to_s

      expect(run.said).to contain "already wearing"
      expect(run.game.player.armour_class).to eq 4
    end

    it "takes no turn when it refuses" do
      run = carrying [Item.new(Kind::ChainMail), Item.new(Kind::LeatherArmour)]

      run.press "W"
      run.press row_for(run, "chain mail").to_s
      turn = run.turn

      run.press "W"
      run.press row_for(run, "leather armour").to_s

      expect(run.turn).to eq turn
    end
  end

  describe "T" do
    it "says so when the character is holding nothing" do
      run = carrying

      run.press "T"

      expect(run.said).to contain "not wearing or holding"
    end

    it "takes the one readied thing off without asking" do
      run = carrying [Item.new Kind::ChainMail]

      run.press "W"
      run.press "a"
      run.press "T"

      expect(run.game.player.worn).to be_empty
      expect(run.menu.showing?).to be_false
      expect(run.said).to contain "no longer wearing"
    end

    it "asks which when more than one is readied" do
      run = carrying [Item.new(Kind::ChainMail), Item.new(Kind::LongSword)]

      run.press "W"
      run.press row_for(run, "chain mail").to_s
      run.press "w"
      run.press row_for(run, "long sword").to_s
      run.press "T"

      expect(run.menu.showing?).to be_true
      expect(run.menu.entries.size).to eq 2
    end

    it "takes off the one chosen" do
      run = carrying [Item.new(Kind::ChainMail), Item.new(Kind::LongSword)]

      run.press "W"
      run.press row_for(run, "chain mail").to_s
      run.press "w"
      run.press row_for(run, "long sword").to_s
      run.press "T"
      run.press row_for(run, "chain mail").to_s

      expect(run.game.player.worn).to be_empty
      expect(run.game.player.wielded.try &.kind).to eq Kind::LongSword
    end

    it "says a weapon is no longer held rather than worn" do
      run = carrying [Item.new Kind::LongSword]

      run.press "w"
      run.press "a"
      run.press "T"

      expect(run.said).to contain "no longer holding"
    end
  end

  describe "a cursed item" do
    # Putting it on is the moment the character finds out.
    it "welds itself on when it goes on" do
      mail = Item.new Kind::ChainMail, blessing: Roguelike::Blessing::Cursed
      run = carrying [mail]

      run.press "W"
      run.press "a"

      expect(run.log.any? &.includes?("welds itself")).to be_true
      expect(mail.blessing_known?).to be_true
    end

    it "refuses to come off" do
      run = carrying [Item.new(Kind::ChainMail, blessing: Roguelike::Blessing::Cursed)]

      run.press "W"
      run.press "a"
      run.press "T"

      expect(run.said).to contain "cannot let go"
      expect(run.game.player.worn.size).to eq 1
    end

    it "says nothing extra when it is not cursed" do
      run = carrying [Item.new Kind::ChainMail]

      run.press "W"
      run.press "a"

      expect(run.log.any? &.includes?("welds itself")).to be_false
    end
  end

  describe "dropping something readied" do
    it "is refused until it comes off" do
      run = carrying [Item.new Kind::ChainMail]

      run.press "W"
      run.press "a"
      run.press "d"
      run.press "a"

      expect(run.said).to contain "take"
      expect(run.game.player.inventory.size).to eq 1
      expect(run.game.here).to be_empty
    end

    it "goes once it comes off" do
      run = carrying [Item.new Kind::ChainMail]

      run.press "W"
      run.press "a"
      run.press "T"
      run.press "d"
      run.press "a"

      expect(run.game.player.inventory.empty?).to be_true
      expect(run.game.here.size).to eq 1
    end
  end

  describe "the inventory list" do
    it "marks what is in the hand" do
      run = carrying [Item.new Kind::LongSword]

      run.press "w"
      run.press "a"
      run.press "i"

      expect(run.menu.entries.first.text).to contain "weapon in hand"
    end

    it "marks what is being worn" do
      run = carrying [Item.new Kind::ChainMail]

      run.press "W"
      run.press "a"
      run.press "i"

      expect(run.menu.entries.first.text).to contain "being worn"
    end

    it "marks nothing that is put away" do
      run = carrying [Item.new Kind::LongSword]

      run.press "i"

      expect(run.menu.entries.first.text).not_to contain "("
    end
  end

  describe "the status line" do
    it "shows the armour class" do
      run = carrying [Item.new Kind::ChainMail]

      run.press "W"
      run.press "a"

      expect(run.rows.join).to contain "ac: 4"
    end

    it "shows the wielded weapon and what it does" do
      run = carrying [Item.new Kind::LongSword]

      run.press "w"
      run.press "a"

      expect(run.rows.join).to contain "wep: long sword 1d8"
    end

    it "shows bare hands as the dice on their own" do
      run = carrying

      expect(run.rows.join).to contain "wep: 1d2"
    end
  end
end
