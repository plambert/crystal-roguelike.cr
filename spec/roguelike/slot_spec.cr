require "../spec_helper"

Spectator.describe Roguelike::Slot do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Slot = Roguelike::Slot
  alias ArmourSlot = Roguelike::ArmourSlot

  describe "the two groups" do
    it "splits into weapons and armour with nothing left over" do
      expect(Slot.weapons.size + Slot.armours.size).to eq Slot.values.size
    end

    it "calls three of them weapons" do
      expect(Slot.weapons).to eq [Slot::Melee, Slot::Ranged, Slot::Quiver]
    end

    it "calls five of them armour" do
      expect(Slot.armours).to eq [Slot::Head, Slot::Body, Slot::Hands,
                                  Slot::Feet, Slot::Shield]
    end

    it "answers an armour slot for each piece of armour and none otherwise" do
      Slot.armours.each { |slot| expect(slot.armour_slot).not_to be_nil }
      Slot.weapons.each { |slot| expect(slot.armour_slot).to be_nil }
    end

    it "round-trips through ArmourSlot" do
      ArmourSlot.values.each do |worn|
        expect(Slot.for(worn).armour_slot).to eq worn
      end
    end
  end

  describe ".for an item" do
    # One key readies anything. A person should not have to remember which
    # key a bow takes and which key an arrow takes.
    it "puts a melee weapon in the hand" do
      expect(Slot.for Item.new(Kind::LongSword)).to eq Slot::Melee
    end

    it "puts a thrown weapon in the hand too" do
      expect(Slot.for Item.new(Kind::Dart)).to eq Slot::Melee
    end

    it "puts a launcher in the other hand" do
      expect(Slot.for Item.new(Kind::Bow)).to eq Slot::Ranged
      expect(Slot.for Item.new(Kind::Sling)).to eq Slot::Ranged
    end

    it "puts ammunition in the quiver" do
      expect(Slot.for Item.new(Kind::Arrow)).to eq Slot::Quiver
      expect(Slot.for Item.new(Kind::Stone)).to eq Slot::Quiver
    end

    it "puts each piece of armour where that piece is worn" do
      expect(Slot.for Item.new(Kind::Cap)).to eq Slot::Head
      expect(Slot.for Item.new(Kind::ChainMail)).to eq Slot::Body
      expect(Slot.for Item.new(Kind::Gloves)).to eq Slot::Hands
      expect(Slot.for Item.new(Kind::Boots)).to eq Slot::Feet
      expect(Slot.for Item.new(Kind::Shield)).to eq Slot::Shield
    end

    it "answers nothing for what is not readied at all" do
      expect(Slot.for Item.new(Kind::HealingPotion)).to be_nil
      expect(Slot.for Item.new(Kind::IdentifyScroll)).to be_nil
      expect(Slot.for Item.new(Kind::LightWand)).to be_nil
      expect(Slot.for Item.new(Kind::Gold)).to be_nil
    end
  end

  describe "#accepts?" do
    it "takes what belongs in it" do
      expect(Slot::Body.accepts? Item.new(Kind::ChainMail)).to be_true
      expect(Slot::Melee.accepts? Item.new(Kind::Mace)).to be_true
    end

    it "refuses what belongs somewhere else" do
      expect(Slot::Head.accepts? Item.new(Kind::Boots)).to be_false
      expect(Slot::Melee.accepts? Item.new(Kind::Bow)).to be_false
    end

    it "refuses what is not readied at all" do
      Slot.values.each do |slot|
        expect(slot.accepts? Item.new(Kind::HealingPotion)).to be_false
      end
    end
  end

  describe "the words" do
    it "gives every slot a label and a note" do
      Slot.values.each do |slot|
        expect(slot.label).not_to be_empty
        expect(slot.note).not_to be_empty
      end
    end

    it "says armour is being worn" do
      Slot.armours.each { |slot| expect(slot.note).to eq "being worn" }
    end
  end
end
