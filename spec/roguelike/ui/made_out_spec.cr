require "../../spec_helper"

Spectator.describe "naming an item lying on the floor" do
  alias Blessing = Roguelike::Blessing
  alias Floor = Roguelike::Floor
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Line = Roguelike::Ui::Line
  alias Player = Roguelike::Player
  alias Regard = Roguelike::Regard
  alias World = Roguelike::World

  # Where the character stands in the hall, and the two squares an item is
  # laid on: one inside the reach and one past it.
  HERE  = 20
  NEAR  = 27
  APART = 29

  # A spear a character standing over it would call "a cursed -2 spear".
  def spear : Item
    Item.new Kind::Spear, enchantment: -2,
      blessing: Blessing::Cursed, blessing_known: true
  end

  # A lit hall wide enough to lay an item on either side of the reach, one
  # row of the floor to a line. The character starts in the middle.
  def hall_map : Array(String)
    Array.new(11) do |row|
      String.build(40) do |line|
        40.times do |column|
          edge = row.zero? || column.zero? || row == 10 || column == 39
          middle = row == 5 && column == HERE
          line << (edge ? '#' : middle ? '<' : '.')
        end
      end
    end
  end

  # A run on the hall with *item* lying at *at*, 5.
  #
  # The appearances are rolled, because a spec about a colour being dropped
  # from a name needs the name to have had a colour in it.
  def hall(at : Int32, item : Item) : Playing::Run
    floor = Playing.daylight Floor.parse("hall", hall_map)
    floor.drop at, 5, item

    game = Roguelike::Game.new World.new(Playing::SEED, {floor.id => floor}),
      Player.new(floor.id, HERE, 5),
      lore: Roguelike::Lore.roll(Roguelike::Rng.new Playing::SEED)

    Playing.open game, 100, 40
  end

  # A dark hall with nothing to see by. What the character knows of it is
  # what a spec writes into their memory.
  DARK = [
    "###############",
    "#<............#",
    "###############",
  ]

  # A run on `DARK` with *item* lying at 11, 1, made out as *regard* and no
  # better. The character is at the west end and can see none of it.
  def remembering(item : Item, regard : Regard) : Playing::Run
    floor = Floor.parse "dark", DARK
    floor.drop 11, 1, item

    game = Roguelike::Game.new World.new(Playing::SEED, {floor.id => floor}),
      Player.new(floor.id, 1, 1)
    game.knowledge.see floor, 11, 1, 0, regard

    Playing.open game, 100, 40
  end

  # What the "Here" section says, row by row.
  def underfoot(run : Playing::Run) : Array(String)
    run.nearby.here.children.compact_map { |child| child.as?(Line).try &.text }
  end

  # What the "Seen" section says, row by row.
  def in_sight(run : Playing::Run) : Array(String)
    run.nearby.seen.children.compact_map { |child| child.as?(Line).try &.text }
  end

  # What the "Look" readout says is lying on *x*, *y*.
  def looked_at(run : Playing::Run, x : Int32, y : Int32) : String
    run.examiner.point_at x, y
    run.examine.litter.text
  end

  describe "the Seen section" do
    it "names a spear past the reach by its kind alone" do
      run = hall APART, spear

      expect(in_sight run).to contain "a spear"
    end

    it "names a spear inside the reach in full" do
      run = hall NEAR, spear

      expect(in_sight run).to contain "a cursed -2 spear"
    end

    it "takes the colour off a potion past the reach" do
      run = hall APART, Item.new(Kind::HealingPotion)
      look = run.game.lore.appearance Kind::HealingPotion

      expect(in_sight run).to contain "a potion"
      expect(in_sight run).not_to contain "a #{look} potion"
    end

    it "keeps the colour on a potion inside the reach" do
      run = hall NEAR, Item.new(Kind::HealingPotion)
      look = run.game.lore.appearance Kind::HealingPotion

      expect(in_sight run).to contain "a #{look} potion"
    end

    it "takes the label off a scroll past the reach" do
      run = hall APART, Item.new(Kind::IdentifyScroll)
      look = run.game.lore.appearance Kind::IdentifyScroll

      expect(in_sight run).to contain "a scroll"
      expect(in_sight run).not_to contain "a scroll #{look}"
    end

    it "keeps the label on a scroll inside the reach" do
      run = hall NEAR, Item.new(Kind::IdentifyScroll)
      look = run.game.lore.appearance Kind::IdentifyScroll

      expect(in_sight run).to contain "a scroll #{look}"
    end
  end

  describe "the Look readout" do
    it "names a spear past the reach by its kind alone" do
      run = hall APART, spear

      expect(looked_at run, APART, 5).to eq "Here: a spear"
    end

    it "names a spear inside the reach in full" do
      run = hall NEAR, spear

      expect(looked_at run, NEAR, 5).to eq "Here: a cursed -2 spear"
    end

    it "names a remembered item by what was made out of it" do
      run = remembering spear, Regard::Kind

      expect(looked_at run, 11, 1).to eq "Here: a spear"
      expect(run.examine.detail.text).to eq Roguelike::Ui::ExaminePane::REMEMBERED
    end

    it "names a remembered item in full when it was made out in full" do
      run = remembering spear, Regard::Everything

      expect(looked_at run, 11, 1).to eq "Here: a cursed -2 spear"
    end
  end

  describe "walking up to a thing" do
    it "keeps the full name after the character walks away again" do
      run = hall APART, spear
      expect(in_sight run).to contain "a spear"

      run.press "l"
      expect(run.at).to eq({HERE + 1, 5})
      expect(in_sight run).to contain "a cursed -2 spear"

      run.press "h"
      expect(run.at).to eq({HERE, 5})
      expect(in_sight run).to contain "a cursed -2 spear"
    end
  end

  describe "what the character has in reach" do
    it "names what they are standing on in full" do
      run = hall HERE, spear

      expect(underfoot run).to contain "a cursed -2 spear"
    end

    it "names what they are standing on in full in the Look readout" do
      run = hall HERE, spear

      expect(looked_at run, HERE, 5).to eq "Here: a cursed -2 spear"
    end

    # A menu row carries the curse as the mark beside the key rather than as
    # a word in the name, so both halves of the row are read here.
    it "names what they are carrying in full in the pack menu" do
      run = hall APART, spear
      run.game.player.inventory.add spear

      run.press "i"
      found = run.menu.entries.find &.text.includes?("spear")

      expect(found.try &.text).to eq " a -2 spear"
      expect(found.try &.mark).to eq Roguelike::Ui::Palette::CURSED
    end

    it "names what they pick up in full in the menu that asks which" do
      run = hall HERE, spear
      run.game.floor.drop HERE, 5, Item.new(Kind::Dagger)

      run.press ","
      found = run.menu.entries.find &.text.includes?("spear")

      expect(found.try &.text).to eq " a -2 spear"
      expect(found.try &.mark).to eq Roguelike::Ui::Palette::CURSED
    end
  end
end
