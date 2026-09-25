require "../spec_helper"

Spectator.describe Roguelike::Slot do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Slot = Roguelike::Slot
  alias ArmorSlot = Roguelike::ArmorSlot

  describe "the two groups" do
    it "splits into weapons and armor with nothing left over" do
      expect(Slot.weapons.size + Slot.armors.size).to eq Slot.values.size
    end

    it "calls three of them weapons" do
      expect(Slot.weapons).to eq [Slot::Melee, Slot::Ranged, Slot::Quiver]
    end

    it "calls five of them armor" do
      expect(Slot.armors).to eq [Slot::Head, Slot::Body, Slot::Hands,
                                 Slot::Feet, Slot::Shield]
    end

    it "answers an armor slot for each piece of armor and none otherwise" do
      Slot.armors.each { |slot| expect(slot.armor_slot).not_to be_nil }
      Slot.weapons.each { |slot| expect(slot.armor_slot).to be_nil }
    end

    it "round-trips through ArmorSlot" do
      ArmorSlot.values.each do |worn|
        expect(Slot.for(worn).armor_slot).to eq worn
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

    it "puts a ranged weapon in the other hand" do
      expect(Slot.for Item.new(Kind::Bow)).to eq Slot::Ranged
      expect(Slot.for Item.new(Kind::Sling)).to eq Slot::Ranged
    end

    it "puts ammunition in the quiver" do
      expect(Slot.for Item.new(Kind::Arrow)).to eq Slot::Quiver
      expect(Slot.for Item.new(Kind::Stone)).to eq Slot::Quiver
    end

    it "puts each piece of armor where that piece is worn" do
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

    it "says armor is being worn" do
      Slot.armors.each { |slot| expect(slot.note).to eq "being worn" }
    end

    it "gives every slot a sentence for each of the three things" do
      Slot.values.each do |slot|
        expect(slot.readied "it").not_to be_empty
        expect(slot.released "it").not_to be_empty
        expect(slot.vacant).not_to be_empty
      end
    end

    # Arrows are not held in the hand and they are not worn. Saying they are
    # sends somebody looking in the wrong place for them.
    it "puts what goes in the quiver in the quiver" do
      expect(Slot::Quiver.readied "12 arrows").to eq "You put 12 arrows in your quiver."
      expect(Slot::Quiver.released "12 arrows").to eq "You take 12 arrows out of your quiver."
    end

    it "holds what goes in a hand" do
      expect(Slot::Melee.readied "a mace").to eq "You are now holding a mace."
      expect(Slot::Ranged.readied "a bow").to eq "You are now holding a bow."
    end

    it "wears what goes on the body" do
      Slot.armors.each do |slot|
        expect(slot.readied "it").to eq "You are now wearing it."
        expect(slot.released "it").to eq "You are no longer wearing it."
      end
    end

    it "says an empty quiver the way Game#cannot_fire says it" do
      expect(Slot::Quiver.vacant).to eq "Your quiver is empty."
    end

    it "names the part of the body an empty armor slot is on" do
      expect(Slot::Head.vacant).to eq "You have nothing on your head."
      expect(Slot::Feet.vacant).to eq "You have nothing on your feet."
    end

    it "says an empty hand is a hand holding nothing" do
      expect(Slot::Melee.vacant).to eq "You are not holding a weapon."
      expect(Slot::Ranged.vacant).to eq "You are not holding a ranged weapon."
    end
  end
end
