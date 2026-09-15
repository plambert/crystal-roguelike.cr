require "../../spec_helper"

Spectator.describe Roguelike::Ui::Naming do
  alias Blessing = Roguelike::Blessing
  alias Condition = Roguelike::Condition
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Lore = Roguelike::Lore
  alias Naming = Roguelike::Ui::Naming

  # A lore with the looks rolled, so a potion has a colour to be called by.
  subject(lore) { Lore.roll Roguelike::Rng.new(20260914_u64) }

  # A lore that knows every kind.
  subject(known) { lore.revealed }

  describe ".short" do
    it "drops the article" do
      expect(Naming.short lore, Item.new(Kind::Dagger)).to eq "dagger"
    end

    it "puts the count in front and leaves the noun singular" do
      expect(Naming.short lore, Item.new(Kind::Arrow, count: 14)).to eq "14 arrow"
    end

    it "shortens the condition and the blessing" do
      item = Item.new Kind::ChainMail, enchantment: 1,
        condition: Condition::Masterwork, blessing: Blessing::Blessed,
        blessing_known: true

      expect(Naming.short lore, item).to eq "bls mwk +1 chain"
    end

    it "says nothing about an uncursed item" do
      item = Item.new Kind::Dagger, blessing: Blessing::Uncursed, blessing_known: true

      expect(Naming.short lore, item).to eq "dagger"
    end

    it "shortens the kinds whose own name is too long" do
      Naming::KINDS.each do |kind, short|
        expect(Naming.short known, Item.new(kind)).to eq short
      end
    end

    it "leaves a kind with a short name alone" do
      expect(Naming.short known, Item.new(Kind::Rapier)).to eq "rapier"
    end

    it "names an unknown kind by what it looks like" do
      potion = Naming.short lore, Item.new(Kind::HealingPotion)

      expect(potion).to end_with " potion"
      expect(potion).not_to contain "healing"
    end

    it "puts the look in front of the noun on a scroll" do
      scroll = Naming.short lore, Item.new(Kind::IdentifyScroll)

      expect(scroll).to end_with " scroll"
      expect(scroll).not_to contain "labelled"
    end

    it "names a kind once it has been found out" do
      expect(Naming.short known, Item.new(Kind::HealingPotion)).to eq "healing potion"
    end

    # A floor built by hand for a spec has no looks rolled at all. The kind's
    # own name is what is left.
    it "falls back to the kind when no look was rolled" do
      expect(Naming.short Lore.new, Item.new(Kind::HealingPotion)).to eq "healing potion"
    end

    # How many columns a name has on a slot row.
    ROOM = Roguelike::Ui::Screen::SIDEBAR_WIDTH - 2 - Roguelike::Ui::CharacterPane::NAME

    # The ordinary case has to fit: a name, a `+N` and one word about how it
    # was made. A pile of variants on one item does not, and `Line` marks
    # what it cut. The whole name is in the tooltip either way.
    it "fits the sidebar for a name with a plus and a condition" do
      too_long = [] of String

      Kind.values.each do |kind|
        item = Item.new kind, enchantment: 1, condition: Condition::Masterwork
        [lore, known].each do |which|
          found = Naming.short which, item
          too_long << found if found.size > ROOM
        end
      end

      expect(too_long).to be_empty
    end

    it "fits a stack of ammunition with a plus on it" do
      item = Item.new Kind::Arrow, enchantment: 1, count: 99

      expect(Naming.short(known, item).size).to be <= ROOM
    end
  end
end
