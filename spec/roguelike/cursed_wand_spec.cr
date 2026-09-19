require "../spec_helper"

Spectator.describe "a cursed wand" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Blessing = Roguelike::Blessing
  alias Slot = Roguelike::Slot

  EAST = {3, 2}

  # A lit one room floor with the character in the middle.
  def bare(seed : UInt64 = Playing::SEED) : Roguelike::Game
    floor = Roguelike::Floor.parse "room", "#####\n#...#\n#.<.#\n#...#\n#####"
    floor.clear_items 2, 2
    floor.ambient = 1

    Roguelike::Game.new Roguelike::World.new(seed, {"room" => floor}),
      Roguelike::Player.new("room", 2, 2)
  end

  def carrying(game : Roguelike::Game, kind : Kind,
               blessing : Blessing = Blessing::Uncursed) : {Char, Item}
    item = Item.new kind, blessing: blessing
    letter = game.player.inventory.add item
    raise "no room" unless letter
    {letter, item}
  end

  describe "zapping it" do
    it "works at full strength" do
      game = bare
      letter, wand = carrying game, Kind::LightWand, Blessing::Cursed
      before = wand.charges

      expect(game.zap letter).to be_true
      expect(wand.charges).to eq before.try &.-(1)
    end

    it "twists into the weapon hand" do
      game = bare
      letter, wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter

      expect(game.player.in_slot Slot::Melee).to be wand
      expect(wand.blessing_known?).to be_true
    end

    it "puts what was wielded back into the pack" do
      game = bare
      sword = Item.new Kind::LongSword
      held = game.player.inventory.add sword
      raise "no room" unless held
      game.wield held

      letter, _wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter

      expect(game.player.in_slot Slot::Melee).not_to be sword
      expect(game.player.inventory.has? held).to be_true
    end

    it "takes the other hand when a curse holds the weapon hand" do
      game = bare
      sword = Item.new Kind::LongSword, blessing: Blessing::Cursed
      held = game.player.inventory.add sword
      raise "no room" unless held
      game.wield held

      letter, wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter

      expect(game.player.in_slot Slot::Melee).to be sword
      expect(game.player.in_slot Slot::Ranged).to be wand
    end

    it "is refused with no hand free, and costs nothing" do
      game = bare
      two = [Slot::Melee, Slot::Ranged].map do |_slot|
        item = Item.new Kind::LongSword, blessing: Blessing::Cursed
        letter = game.player.inventory.add item
        raise "no room" unless letter
        {letter, item}
      end
      game.wield two[0][0]
      game.player.equipment.put Slot::Ranged, two[1][0]

      letter, wand = carrying game, Kind::LightWand, Blessing::Cursed
      charges = wand.charges
      turn = game.turn

      expect(game.zap letter).to be_false
      expect(game.turn).to eq turn
      expect(wand.charges).to eq charges
      expect(wand.blessing_known?).to be_true
      expect(game.log.last?.to_s).to contain "Neither hand"
    end
  end

  describe "with it in the hand" do
    it "cannot be taken off" do
      game = bare
      letter, _wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter

      expect(game.take_off Slot::Melee).to be_false
    end

    it "cannot be dropped" do
      game = bare
      letter, _wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter

      expect(game.drop letter).to be_false
    end

    it "hits like a fist" do
      game = bare
      letter, _wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter

      expect(game.player.damage).to eq Roguelike::Player::UNARMED
    end

    it "adds nothing to a swing" do
      game = bare
      bare_handed = game.player.to_hit
      letter, _wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter

      expect(game.player.to_hit).to eq bare_handed
    end

    it "stops the character shooting" do
      game = bare
      sword = Item.new Kind::LongSword, blessing: Blessing::Cursed
      held = game.player.inventory.add sword
      raise "no room" unless held
      game.wield held

      letter, _wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter

      expect(game.cannot_fire).to contain "nothing readied to shoot"
      expect(game.firing_reach).to eq 0
    end
  end

  describe "getting free of it" do
    it "goes cold when the last charge is spent" do
      game = bare
      letter, wand = carrying game, Kind::LightWand, Blessing::Cursed
      20.times { break if wand.spent?; game.zap letter }

      expect(wand.spent?).to be_true
      expect(wand.cursed?).to be_false
      expect(game.take_off Slot::Melee).to be_true
    end

    it "cracks in the hand now and then" do
      game = bare
      letter, wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter

      # A fresh creature for every swing, so the wand gets as many swings as
      # the roll needs, and the character is put back on their feet after
      # each one.
      400.times do
        break if wand.condition.damaged?

        game.floor.remove 3, 2
        target = Roguelike::Monster.new Roguelike::Species::Slime, 3, 2, "band-one"
        game.floor.place target
        game.attack target
        game.player.heal 100
      end

      expect(wand.condition.damaged?).to be_true
      expect(game.log.lines.any? &.includes?("cracks")).to be_true
    end

    it "can be put down once it has cracked" do
      game = bare
      letter, wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter
      wand.crack

      expect(game.take_off Slot::Melee).to be_true
      expect(game.drop letter).to be_true
    end

    it "does nothing once it has cracked" do
      game = bare
      letter, wand = carrying game, Kind::LightWand, Blessing::Cursed
      game.zap letter
      wand.crack
      charges = wand.charges

      expect(game.zap letter).to be_false
      expect(wand.charges).to eq charges
      expect(game.log.last?.to_s).to contain "cracked"
    end
  end

  describe "an uncursed wand" do
    it "stays in the pack" do
      game = bare
      letter, _wand = carrying game, Kind::LightWand
      game.zap letter

      expect(game.player.in_slot Slot::Melee).to be_nil
      expect(game.player.inventory.has? letter).to be_true
    end
  end
end
