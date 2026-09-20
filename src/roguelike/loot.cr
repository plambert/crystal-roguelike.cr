require "./item"
require "./items"
require "./rng"
require "./species"

module Roguelike
  # What a monster is carrying when it is put on a floor.
  #
  # Everything here rolls on an `Rng`, so a run reproduces from its seed. A
  # spec that rolls ten thousand goblins twice gets the same ten thousand
  # both times.
  #
  # A species makes several draws rather than one. Each is rolled on its own,
  # so a goblin can come up with a weapon and no armour, with both, or with
  # neither. One table of everything a goblin might have would make those
  # exclusive, and a goblin with a sword and no boots is the ordinary case.
  module Loot
    # One roll a species makes for what it is carrying.
    #
    # *kinds* is what the draw may produce, by weight. *chance* is how often
    # it produces anything at all, out of a hundred. *count* is how many,
    # which only a counted kind reads.
    record Draw,
      kinds : Hash(ItemKind, Int32),
      chance : Int32,
      count : Range(Int32, Int32) = 1..1

    # How well made a piece a monster is carrying turns out to be.
    #
    # Most of what a monster has is battered. Some of it is sound. A little
    # of it is better than what is lying about the floor, which rolls on
    # `Items::CONDITIONS` instead and comes up plain far more often.
    CONDITIONS = {
      {Condition::Damaged, 60},
      {Condition::Plain, 32},
      {Condition::Masterwork, 8},
    }

    # What a creature carrying a weapon has.
    #
    # Weighted toward the plain weapons. A goblin is far more likely to have
    # a dagger than a rapier.
    WEAPONS = {
      ItemKind::Dagger     => 40,
      ItemKind::ShortSword => 25,
      ItemKind::Spear      => 15,
      ItemKind::Mace       => 12,
      ItemKind::LongSword  => 6,
      ItemKind::Rapier     => 2,
    }

    # What it is wearing.
    ARMOUR = {
      ItemKind::Cap           => 30,
      ItemKind::Gloves        => 22,
      ItemKind::Boots         => 22,
      ItemKind::LeatherArmour => 18,
      ItemKind::Shield        => 6,
      ItemKind::ChainMail     => 2,
    }

    # What it is carrying for the light. It comes out alight.
    LIGHTS = {
      ItemKind::Torch  => 65,
      ItemKind::Candle => 35,
    }

    # What a slime has swallowed and not digested.
    SWALLOWED = {
      ItemKind::HealingPotion     => 44,
      ItemKind::IdentifyScroll    => 16,
      ItemKind::MappingScroll     => 10,
      ItemKind::RemoveCurseScroll => 8,
      ItemKind::BlessingScroll    => 6,
      ItemKind::TreasureScroll    => 8,
      ItemKind::DetectionScroll   => 8,
      ItemKind::DarknessScroll    => 5,
      ItemKind::BlindnessScroll   => 6,
      ItemKind::TeleportScroll    => 7,
      ItemKind::RepairScroll      => 7,
      ItemKind::LightWand         => 10,
      ItemKind::StrikingWand      => 6,
    }

    # Coins. One kind, so the weight says nothing; the count is what varies.
    COINS = {ItemKind::Gold => 1}

    # What each species draws for.
    #
    # A species is never given a draw for something it would not be carrying.
    # A slime has no hands, so there is no weapon draw in its list at all
    # rather than a weapon draw it almost never makes.
    DRAWS = {
      Species::Slime => [
        Draw.new(COINS, chance: 70, count: 1..12),
        Draw.new(SWALLOWED, chance: 8),
      ],

      Species::Goblin => [
        Draw.new(WEAPONS, chance: 80),
        Draw.new(ARMOUR, chance: 35),
        Draw.new(LIGHTS, chance: 25),
        Draw.new(COINS, chance: 60, count: 3..25),
      ],

      Species::Orc => [
        Draw.new(WEAPONS, chance: 90),
        Draw.new(ARMOUR, chance: 55),
        Draw.new(LIGHTS, chance: 20),
        Draw.new(COINS, chance: 70, count: 8..45),
      ],
    }

    # The draws *species* makes.
    def self.draws(species : Species) : Array(Draw)
      DRAWS[species]
    end

    # Every kind *species* could be carrying.
    #
    # A spec asserts that nothing outside this ever turns up.
    def self.kinds(species : Species) : Set(ItemKind)
      found = Set(ItemKind).new
      draws(species).each { |draw| draw.kinds.each_key { |kind| found << kind } }
      found
    end

    # What one creature of *species* is carrying, rolled on *rng*.
    #
    # *rng* belongs to that one creature. `Game#equip` derives a stream from
    # where the creature stands, so adding an entry to a table shifts what
    # that creature carries and nothing else on the floor.
    def self.for(species : Species, rng : Rng) : Array(Item)
      found = [] of Item

      draws(species).each do |draw|
        taken = one draw, rng
        found << taken if taken
      end

      found
    end

    # What one draw produces. `nil` when it produces nothing.
    #
    # Anything that burns comes out alight, and `Game#lights` reads it as a
    # carried source.
    private def self.one(draw : Draw, rng : Rng) : Item?
      return unless rng.rand(100) < draw.chance

      kind = Items.pick rng, draw.kinds
      return Item.new kind, count: rng.rand(draw.count) if kind.item_class.treasure?

      item = Items.make rng, kind, CONDITIONS
      item.kindle
      item
    end
  end
end
