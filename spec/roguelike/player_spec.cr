require "../spec_helper"

Spectator.describe Roguelike::Player do
  subject(player) { described_class.new "proving-ground", 6, 5 }

  it "stands where it was put" do
    expect(player.at).to eq({6, 5})
    expect(player.floor).to eq "proving-ground"
  end

  describe "#move_to" do
    it "goes where it is put" do
      player.move_to 7, 9

      expect(player.at).to eq({7, 9})
    end

    it "takes a pair as well as two numbers" do
      player.move_to({7, 9})

      expect(player.at).to eq({7, 9})
    end
  end

  describe "#at?" do
    it "knows which square it is standing on" do
      expect(player.at?(6, 5)).to be_true
      expect(player.at?(6, 6)).to be_false
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      again = described_class.from_json player.to_json

      expect(again.at).to eq player.at
      expect(again.floor).to eq player.floor
    end

    # A save that stored the floor twice would hold one copy in the world and
    # one under the player. The two copies would then need to stay in step.
    it "names the floor rather than holding one" do
      stored = JSON.parse player.to_json

      expect(stored["floor"]).to eq "proving-ground"
    end

    it "keeps the scores, the level and the hit points" do
      hurt = described_class.new "proving-ground", 6, 5,
        attributes: Roguelike::Attributes.new(14, 11, 16, 9, 13)
      hurt.gain 100
      hurt.hurt 5

      again = described_class.from_json hurt.to_json

      expect(again.attributes.to_a).to eq hurt.attributes.to_a
      expect(again.level).to eq hurt.level
      expect(again.experience).to eq hurt.experience
      expect(again.hit_points).to eq hurt.hit_points
      expect(again.max_hit_points).to eq hurt.max_hit_points
    end
  end

  describe "derived stats" do
    alias Kind = Roguelike::ItemKind
    alias Item = Roguelike::Item
    alias Slot = Roguelike::Slot

    # A character carrying *items* with each one readied where it belongs.
    def armed(items : Array(Item),
              attributes : Roguelike::Attributes = Roguelike::Attributes.new) : Roguelike::Player
      player = Roguelike::Player.new "proving-ground", 6, 5, attributes: attributes

      items.each do |item|
        letter = player.inventory.add item
        slot = Slot.for item
        player.equipment.put slot, letter if letter && slot
      end

      player
    end

    describe "#damage" do
      it "is a small roll with bare hands" do
        expect(armed([] of Item).damage).to eq Roguelike::Player::UNARMED
      end

      it "is the wielded weapon's dice" do
        expect(armed([Item.new Kind::LongSword]).damage).to eq Roguelike::Dice.new(1, 8)
      end

      it "works in the enchantment and the condition" do
        sword = Item.new Kind::LongSword, enchantment: 2,
          condition: Roguelike::Condition::Masterwork

        expect(armed([sword]).damage).to eq Roguelike::Dice.new(1, 8, 3)
      end

      it "works in a damaged weapon as a penalty" do
        sword = Item.new Kind::LongSword, condition: Roguelike::Condition::Damaged

        expect(armed([sword]).damage).to eq Roguelike::Dice.new(1, 8, -1)
      end

      it "adds the strength modifier" do
        strong = Roguelike::Attributes.new strength: 16

        expect(armed([Item.new(Kind::LongSword)], strong).damage)
          .to eq Roguelike::Dice.new(1, 8, 3)
      end

      it "takes the strength modifier off a weak character" do
        weak = Roguelike::Attributes.new strength: 6

        expect(armed([Item.new(Kind::LongSword)], weak).damage)
          .to eq Roguelike::Dice.new(1, 8, -2)
      end

      # A bow is in the ranged slot. It is not what the character swings.
      it "ignores what is not in the hand" do
        expect(armed([Item.new(Kind::Bow), Item.new(Kind::Arrow)]).damage)
          .to eq Roguelike::Player::UNARMED
      end
    end

    describe "#armour_class" do
      it "is nothing with nothing on" do
        expect(armed([] of Item).armour_class).to eq 0
      end

      it "counts one piece" do
        expect(armed([Item.new Kind::ChainMail]).armour_class).to eq 4
      end

      it "adds every piece worn" do
        worn = [Kind::ChainMail, Kind::Shield, Kind::Cap, Kind::Boots, Kind::Gloves]
          .map { |kind| Item.new kind }

        expect(armed(worn).armour_class).to eq 4 + 2 + 1 + 1 + 1
      end

      it "works in the enchantment and the condition" do
        mail = Item.new Kind::ChainMail, enchantment: 1,
          condition: Roguelike::Condition::Masterwork

        expect(armed([mail]).armour_class).to eq 6
      end

      it "adds the dexterity modifier" do
        quick = Roguelike::Attributes.new dexterity: 18

        expect(armed([Item.new(Kind::ChainMail)], quick).armour_class).to eq 8
      end

      it "never goes below nothing" do
        clumsy = Roguelike::Attributes.new dexterity: 3

        expect(armed([] of Item, clumsy).armour_class).to eq 0
      end

      it "ignores a weapon" do
        expect(armed([Item.new Kind::LongSword]).armour_class).to eq 0
      end
    end

    describe "#wielded, #ranged_weapon and #quivered" do
      it "each answer what is in their slot" do
        player = armed [Item.new(Kind::Mace), Item.new(Kind::Sling),
                        Item.new(Kind::Stone, count: 12)]

        expect(player.wielded.try &.kind).to eq Kind::Mace
        expect(player.ranged_weapon.try &.kind).to eq Kind::Sling
        expect(player.quivered.try &.kind).to eq Kind::Stone
      end

      it "each answer nothing for an empty slot" do
        player = armed [] of Item

        expect(player.wielded).to be_nil
        expect(player.ranged_weapon).to be_nil
        expect(player.quivered).to be_nil
      end
    end

    it "keeps the equipment through JSON" do
      player = armed [Item.new(Kind::LongSword), Item.new(Kind::ChainMail)]
      again = Roguelike::Player.from_json player.to_json

      expect(again.equipment).to eq player.equipment
      expect(again.wielded.try &.kind).to eq Kind::LongSword
      expect(again.armour_class).to eq 4
    end
  end

  describe "hit points" do
    it "starts at full health" do
      expect(player.hit_points).to eq player.max_hit_points
      expect(player.alive?).to be_true
    end

    it "comes from constitution and level" do
      tough = described_class.new "floor", 0, 0,
        attributes: Roguelike::Attributes.new(constitution: 16)

      expect(tough.max_hit_points)
        .to eq Roguelike::Advancement.max_hit_points(1, 16)
      expect(tough.max_hit_points).to be > player.max_hit_points
    end

    it "falls when the character is hurt" do
      player.hurt 3

      expect(player.hit_points).to eq player.max_hit_points - 3
    end

    it "stops at nothing rather than going below it" do
      player.hurt 1_000

      expect(player.hit_points).to eq 0
      expect(player.alive?).to be_false
    end

    it "goes back up when the character heals" do
      player.hurt 5

      expect(player.heal(3)).to eq 3
      expect(player.hit_points).to eq player.max_hit_points - 2
    end

    it "heals no further than full health" do
      player.hurt 2

      expect(player.heal(1_000)).to eq 2
      expect(player.hit_points).to eq player.max_hit_points
    end
  end

  describe "#gain" do
    it "adds experience without a level at first" do
      expect(player.gain(1)).to eq 0
      expect(player.experience).to eq 1
      expect(player.level).to eq 1
    end

    it "raises the level at the threshold" do
      expect(player.gain(Roguelike::Advancement.threshold(2))).to eq 1
      expect(player.level).to eq 2
    end

    it "raises it more than once for a large gain" do
      expect(player.gain(Roguelike::Advancement.threshold(4))).to eq 3
      expect(player.level).to eq 4
    end

    # A character who levels up mid fight is better off than before, and is
    # not suddenly at full health either.
    it "adds the hit points the level gained, and no more" do
      player.hurt 5
      hurt = player.hit_points
      before = player.max_hit_points

      player.gain Roguelike::Advancement.threshold(2)

      expect(player.hit_points).to eq hurt + (player.max_hit_points - before)
      expect(player.hit_points).to be < player.max_hit_points
    end

    it "ignores a gain of nothing" do
      expect(player.gain(0)).to eq 0
      expect(player.gain(-5)).to eq 0
      expect(player.experience).to eq 0
    end

    it "counts down to the next level" do
      player.gain 5

      expect(player.to_next_level).to eq Roguelike::Advancement.threshold(2) - 5
    end
  end
end
