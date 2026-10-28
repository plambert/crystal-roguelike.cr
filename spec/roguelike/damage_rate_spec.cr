require "../spec_helper"

Spectator.describe "what a fighter does in a turn" do
  alias Combat = Roguelike::Combat
  alias Dice = Roguelike::Dice
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Player = Roguelike::Player
  alias Slot = Roguelike::Slot

  # A character of plain scores holding *weapon* and wearing *armor*.
  def fighter(weapon : Kind?, armor : Array(Kind) = [] of Kind) : Player
    player = Player.new "room", 0, 0
    ([weapon].compact + armor).each do |kind|
      item = Item.new kind, blessing_known: true
      letter = player.inventory.add(item) || raise "pack full"
      player.equipment.put(Slot.for(item) || raise("no slot"), letter)
    end
    player
  end

  describe "the chance to land" do
    it "counts the faces that land" do
      expect(Combat.hit_chance 0, 0).to eq 0.55
      expect(Combat.hit_chance 0, 2).to eq 0.45
      expect(Combat.hit_chance 3, 2).to eq 0.6
    end

    it "keeps the face that always lands and the one that never does" do
      expect(Combat.hit_chance -50, 0).to eq 0.05
      expect(Combat.hit_chance 50, 0).to eq 0.95
    end
  end

  describe "the damage of a landed blow" do
    it "is the mean of the dice" do
      expect(Combat.mean_damage Dice.new(1, 6)).to eq 3.5
      expect(Combat.mean_damage Dice.new(2, 6, 1)).to eq 8.0
    end

    it "counts a total under the least as the least" do
      expect(Combat.mean_damage Dice.new(1, 2, -1)).to eq 1.0
    end
  end

  describe "the rate" do
    it "gives a short sword in leather armor 1.58 against armor class 2" do
      player = fighter Kind::ShortSword, [Kind::LeatherArmor]

      expect(player.swing).to eq 100
      expect(player.per_turn 2).to be_close(0.45 * 3.5, 1e-9)
    end

    it "gives an unarmored dagger 1.50" do
      expect(fighter(Kind::Dagger).per_turn 2).to be_close(1.5, 1e-9)
    end

    it "gives a mace in chain mail and a shield 1.40" do
      player = fighter Kind::Mace, [Kind::ChainMail, Kind::Shield]

      expect(player.swing).to eq 145
      expect(player.per_turn 2).to be_close(0.45 * 4.5 * 100 / 145, 1e-9)
    end

    it "rates a weapon in the pack as if it were in the hand" do
      player = fighter Kind::Dagger, [Kind::ChainMail]
      sword = Item.new Kind::LongSword

      expect(player.per_turn 2, sword).to eq fighter(Kind::LongSword, [Kind::ChainMail]).per_turn(2)
    end

    it "reads the same numbers a blow rolls with" do
      player = fighter Kind::ShortSword, [Kind::ChainMail]

      expect(player.per_turn 4).to eq Combat.per_turn(player.to_hit, 4, player.damage, player.swing)
    end
  end
end
