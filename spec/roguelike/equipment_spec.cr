require "../spec_helper"

Spectator.describe Roguelike::Equipment do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Slot = Roguelike::Slot

  subject(equipment) { described_class.new }

  it "starts empty" do
    expect(equipment.empty?).to be_true
    expect(equipment.size).to eq 0
    expect(equipment[Slot::Melee]).to be_nil
  end

  describe "#put" do
    it "fills a slot" do
      equipment.put Slot::Melee, 'a'

      expect(equipment[Slot::Melee]).to eq 'a'
      expect(equipment.empty?).to be_false
    end

    it "answers what was there" do
      equipment.put Slot::Melee, 'a'

      expect(equipment.put Slot::Melee, 'b').to eq 'a'
      expect(equipment[Slot::Melee]).to eq 'b'
    end

    it "answers nothing for a slot that was empty" do
      expect(equipment.put Slot::Body, 'a').to be_nil
    end

    # One item is in one place. A dart wielded and then quivered is in the
    # quiver, not in both.
    it "takes a letter out of the slot that had it" do
      equipment.put Slot::Melee, 'a'
      equipment.put Slot::Quiver, 'a'

      expect(equipment[Slot::Melee]).to be_nil
      expect(equipment[Slot::Quiver]).to eq 'a'
      expect(equipment.size).to eq 1
    end
  end

  describe "#slot_of" do
    it "says which slot holds a letter" do
      equipment.put Slot::Feet, 'c'

      expect(equipment.slot_of 'c').to eq Slot::Feet
      expect(equipment.readied? 'c').to be_true
    end

    it "answers nothing for a letter nothing holds" do
      expect(equipment.slot_of 'c').to be_nil
      expect(equipment.readied? 'c').to be_false
    end
  end

  describe "#clear and #release" do
    it "empties a slot and answers what was in it" do
      equipment.put Slot::Head, 'd'

      expect(equipment.clear Slot::Head).to eq 'd'
      expect(equipment[Slot::Head]).to be_nil
    end

    it "takes a letter out and answers the slot it was in" do
      equipment.put Slot::Head, 'd'

      expect(equipment.release 'd').to eq Slot::Head
      expect(equipment.empty?).to be_true
    end

    it "answers nothing for a letter nothing holds" do
      expect(equipment.release 'd').to be_nil
    end
  end

  describe "#entries" do
    it "reads in the order Slot names the slots" do
      equipment.put Slot::Feet, 'c'
      equipment.put Slot::Melee, 'a'
      equipment.put Slot::Body, 'b'

      expect(equipment.entries).to eq [{Slot::Melee, 'a'}, {Slot::Body, 'b'},
                                       {Slot::Feet, 'c'}]
    end

    it "reads only the armour for #worn" do
      equipment.put Slot::Melee, 'a'
      equipment.put Slot::Body, 'b'

      expect(equipment.worn).to eq [{Slot::Body, 'b'}]
    end
  end

  describe "#clean" do
    # A readied item that leaves the inventory leaves its slot. Nothing else
    # has to remember to empty the slot.
    it "drops a slot whose letter the inventory no longer holds" do
      inventory = Roguelike::Inventory.new
      inventory.add Item.new Kind::LongSword
      inventory.add Item.new Kind::Cap

      equipment.put Slot::Melee, 'a'
      equipment.put Slot::Head, 'b'
      inventory.remove 'b'
      equipment.clean inventory

      expect(equipment[Slot::Melee]).to eq 'a'
      expect(equipment[Slot::Head]).to be_nil
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      equipment.put Slot::Melee, 'a'
      equipment.put Slot::Body, 'B'

      again = described_class.from_json equipment.to_json

      expect(again).to eq equipment
      expect(again[Slot::Body]).to eq 'B'
    end

    # A JSON object key has to be a string and a letter is a Char, so the
    # stored form is a list of pairs. Inventory stores its letters the same
    # way.
    it "stores a list of pairs" do
      equipment.put Slot::Melee, 'a'
      stored = JSON.parse equipment.to_json

      expect(stored[0]["slot"]).to eq "Melee"
      expect(stored[0]["letter"]).to eq "a"
    end

    it "skips a pair naming a slot that no longer exists" do
      again = described_class.from_json %([{"slot":"Antlers","letter":"a"}])

      expect(again.empty?).to be_true
    end
  end
end
