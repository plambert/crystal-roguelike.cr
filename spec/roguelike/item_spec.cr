require "../spec_helper"

Spectator.describe Roguelike::Item do
  alias Kind = Roguelike::ItemKind
  alias Condition = Roguelike::Condition

  describe "the catalogue" do
    it "says what every kind is" do
      Kind.each do |kind|
        expect(kind.label).not_to be_empty
        expect(kind.plural).not_to be_empty
      end
    end

    it "gives every kind a different name" do
      labels = Kind.values.map &.label

      expect(labels.uniq.size).to eq labels.size
    end

    it "gives every weapon damage" do
      (Kind.of_class(Roguelike::ItemClass::Melee) +
        Kind.of_class(Roguelike::ItemClass::Ammunition) +
        Kind.of_class(Roguelike::ItemClass::Thrown)).each do |kind|
        expect(kind.damage.none?).to be_false
      end
    end

    it "gives every piece of armour a slot and a rating" do
      Kind.of_class(Roguelike::ItemClass::Armour).each do |kind|
        expect(kind.slot).not_to be_nil
        expect(kind.armour).to be > 0
      end
    end

    it "covers all five armour slots" do
      slots = Kind.of_class(Roguelike::ItemClass::Armour).compact_map &.slot

      expect(slots.to_set).to eq Roguelike::ArmourSlot.values.to_set
    end

    it "gives every piece of ammunition something that fires it" do
      Kind.of_class(Roguelike::ItemClass::Ammunition).each do |kind|
        ranged_weapon = kind.ranged_weapon
        expect(ranged_weapon).not_to be_nil
        expect(ranged_weapon.try &.item_class.ranged_weapon?).to be_true
      end
    end

    it "gives every wand charges" do
      Kind.of_class(Roguelike::ItemClass::Wand).each do |kind|
        expect(kind.charges).to be > 0
      end
    end
  end

  describe "what a kind allows" do
    it "lets a weapon take a plus and a condition" do
      expect(Kind::LongSword.enchantable?).to be_true
      expect(Kind::ChainMail.enchantable?).to be_true
      expect(Kind::Arrow.enchantable?).to be_true
    end

    it "does not let a potion take one" do
      expect(Kind::HealingPotion.enchantable?).to be_false
      expect(Kind::LightWand.enchantable?).to be_false
    end

    # A person carries dozens of arrows. Two wands have different charges.
    it "stacks what a person carries dozens of" do
      expect(Kind::Arrow.stacks?).to be_true
      expect(Kind::HealingPotion.stacks?).to be_true
      expect(Kind::LightWand.stacks?).to be_false
      expect(Kind::LongSword.stacks?).to be_false
    end

    it "disguises what has to be found out" do
      expect(Kind::HealingPotion.disguised?).to be_true
      expect(Kind::IdentifyScroll.disguised?).to be_true
      expect(Kind::LightWand.disguised?).to be_true
      expect(Kind::LongSword.disguised?).to be_false
    end
  end

  describe "a new item" do
    it "takes the variants it is given" do
      item = described_class.new Kind::LongSword, 2, Condition::Masterwork

      expect(item.enchantment).to eq 2
      expect(item.condition).to eq Condition::Masterwork
    end

    it "drops a plus a kind cannot carry" do
      item = described_class.new Kind::HealingPotion, 2, Condition::Masterwork

      expect(item.enchantment).to eq 0
      expect(item.condition).to eq Condition::Plain
    end

    it "holds one of anything that does not stack" do
      expect(described_class.new(Kind::LongSword, count: 5).count).to eq 1
    end

    it "holds the count of anything that does" do
      expect(described_class.new(Kind::Arrow, count: 5).count).to eq 5
    end

    it "starts a wand at full charges" do
      expect(described_class.new(Kind::LightWand).charges).to eq Kind::LightWand.charges
    end

    it "gives nothing else charges" do
      expect(described_class.new(Kind::LongSword).charges).to be_nil
    end
  end

  describe "#damage" do
    it "is the kind's dice for a plain item" do
      expect(described_class.new(Kind::LongSword).damage.to_s)
        .to eq Kind::LongSword.damage.to_s
    end

    it "adds the plus and the condition" do
      item = described_class.new Kind::LongSword, 2, Condition::Masterwork

      expect(item.damage.bonus).to eq Kind::LongSword.damage.bonus + 3
    end

    it "takes off a damaged item's penalty" do
      item = described_class.new Kind::LongSword, 0, Condition::Damaged

      expect(item.damage.bonus).to eq Kind::LongSword.damage.bonus - 1
    end
  end

  describe "#armour" do
    it "adds the plus and the condition" do
      item = described_class.new Kind::ChainMail, 1, Condition::Masterwork

      expect(item.armour).to eq Kind::ChainMail.armour + 2
    end

    it "never falls below nothing" do
      item = described_class.new Kind::Cap, -5, Condition::Damaged

      expect(item.armour).to eq 0
    end

    it "is nothing at all for anything that is not armour" do
      expect(described_class.new(Kind::LongSword).armour).to eq 0
    end
  end

  describe "a blessing" do
    it "is uncursed and hidden on a new item" do
      item = described_class.new Kind::LongSword

      expect(item.blessing).to eq Roguelike::Blessing::Uncursed
      expect(item.blessing_known?).to be_false
    end

    it "takes the one it is given" do
      item = described_class.new Kind::LongSword, blessing: Roguelike::Blessing::Cursed

      expect(item.cursed?).to be_true
      expect(item.blessed?).to be_false
    end

    # Unlike an enchantment, anything can be blessed. A cursed potion is a
    # classic.
    it "goes on a kind that cannot take a plus" do
      potion = described_class.new Kind::HealingPotion,
        blessing: Roguelike::Blessing::Blessed

      expect(potion.blessed?).to be_true
      expect(potion.enchantment).to eq 0
    end

    it "is revealed once and then known" do
      item = described_class.new Kind::LongSword

      expect(item.reveal_blessing).to be_true
      expect(item.blessing_known?).to be_true
      expect(item.reveal_blessing).to be_false
    end

    # Phase 11 uses this. A cursed weapon cannot be put down.
    it "sticks when it is cursed" do
      cursed = described_class.new Kind::LongSword, blessing: Roguelike::Blessing::Cursed
      plain = described_class.new Kind::LongSword

      expect(cursed.sticks?).to be_true
      expect(plain.sticks?).to be_false
    end
  end

  describe "#stacks_with?" do
    it "joins two of the same" do
      one = described_class.new Kind::Arrow, count: 3
      two = described_class.new Kind::Arrow, count: 5

      expect(one.stacks_with?(two)).to be_true
    end

    # A person firing them would want to know which is which.
    it "keeps a plus apart from a plain one" do
      plain = described_class.new Kind::Arrow, count: 3
      blessed = described_class.new Kind::Arrow, 1, count: 3

      expect(plain.stacks_with?(blessed)).to be_false
    end

    it "keeps a damaged one apart" do
      plain = described_class.new Kind::Arrow, count: 3
      worn = described_class.new Kind::Arrow, 0, Condition::Damaged, count: 3

      expect(plain.stacks_with?(worn)).to be_false
    end

    it "keeps a cursed one apart" do
      plain = described_class.new Kind::Arrow, count: 3
      cursed = described_class.new Kind::Arrow, count: 3,
        blessing: Roguelike::Blessing::Cursed

      expect(plain.stacks_with?(cursed)).to be_false
    end

    # One known and one not are two piles. A person who put them together
    # would lose track of which was which.
    it "keeps a known blessing apart from an unknown one" do
      hidden = described_class.new Kind::Arrow, count: 3
      shown = described_class.new Kind::Arrow, count: 3, blessing_known: true

      expect(hidden.stacks_with?(shown)).to be_false
    end

    it "never joins two of a kind that does not stack" do
      one = described_class.new Kind::LongSword
      two = described_class.new Kind::LongSword

      expect(one.stacks_with?(two)).to be_false
    end
  end

  describe "#spend" do
    it "uses a charge at a time" do
      wand = described_class.new Kind::LightWand
      charges = Kind::LightWand.charges

      expect(wand.spend).to be_true
      expect(wand.charges).to eq charges - 1
    end

    it "runs out" do
      wand = described_class.new Kind::LightWand
      Kind::LightWand.charges.times { wand.spend }

      expect(wand.spent?).to be_true
      expect(wand.spend).to be_false
    end

    it "does nothing to something with no charges" do
      expect(described_class.new(Kind::LongSword).spend).to be_false
    end
  end

  describe "#weight" do
    it "counts the whole stack" do
      one = described_class.new Kind::Arrow, count: 1
      ten = described_class.new Kind::Arrow, count: 10

      expect(ten.weight).to eq one.weight * 10
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      item = described_class.new Kind::Arrow, -1, Condition::Damaged, count: 7,
        blessing: Roguelike::Blessing::Cursed, blessing_known: true

      expect(described_class.from_json(item.to_json)).to eq item
    end

    it "round-trips a wand with charges spent" do
      wand = described_class.new Kind::LightWand
      2.times { wand.spend }

      expect(described_class.from_json(wand.to_json).charges).to eq wand.charges
    end

    # A save file holds the member name. An old save has to keep meaning what
    # it meant, so a member is never removed and never reordered.
    it "stores the kind by name" do
      stored = JSON.parse described_class.new(Kind::LongSword).to_json

      expect(stored["kind"]).to eq "long_sword"
    end
  end

  describe "a thing that burns" do
    it "starts out unlit" do
      expect(Roguelike::Item.new(Roguelike::ItemKind::Torch).lit?).to be_false
    end

    it "throws light once it is lit" do
      torch = Roguelike::Item.new Roguelike::ItemKind::Torch

      expect(torch.light).to eq 0
      expect(torch.kindle).to be_true
      expect(torch.lit?).to be_true
      expect(torch.light).to eq Roguelike::ItemKind::Torch.light
    end

    it "goes out again" do
      torch = Roguelike::Item.new Roguelike::ItemKind::Torch, lit: true

      expect(torch.douse).to be_true
      expect(torch.lit?).to be_false
      expect(torch.douse).to be_false
    end

    it "says so when it is already alight" do
      torch = Roguelike::Item.new Roguelike::ItemKind::Torch, lit: true

      expect(torch.kindle).to be_false
    end

    it "keeps the flame through JSON" do
      torch = Roguelike::Item.new Roguelike::ItemKind::Torch, lit: true

      expect(Roguelike::Item.from_json(torch.to_json).lit?).to be_true
    end
  end

  describe "a thing that does not burn" do
    it "cannot be lit" do
      sword = Roguelike::Item.new Roguelike::ItemKind::LongSword

      expect(sword.burns?).to be_false
      expect(sword.kindle).to be_false
      expect(sword.lit?).to be_false
      expect(sword.light).to eq 0
    end

    it "ignores a lit flag it was built with" do
      expect(Roguelike::Item.new(Roguelike::ItemKind::LongSword, lit: true).lit?).to be_false
    end
  end
end
