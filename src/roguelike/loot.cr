require "../roguelike"

module Roguelike
  # What a monster is carrying when it is put on a floor.
  #
  # Everything here rolls on an `Rng`, so a run reproduces from its seed. A
  # spec that rolls ten thousand goblins twice gets the same ten thousand
  # both times.
  #
  # A kind makes several draws rather than one. Each is rolled on its own,
  # so a goblin can come up with a weapon and no armor, with both, or with
  # neither. One table of everything a goblin might have would make those
  # exclusive, and a goblin with a sword and no boots is the ordinary case.
  module Loot
    # One roll a kind makes for what it is carrying.
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

    # What a kind with no weapon of its own draws when it is armed.
    #
    # Weighted toward the plain weapons. An orc is far more likely to have a
    # dagger than a rapier.
    WEAPONS = {
      ItemKind::Dagger     => 40,
      ItemKind::ShortSword => 25,
      ItemKind::Spear      => 15,
      ItemKind::Mace       => 12,
      ItemKind::LongSword  => 6,
      ItemKind::Rapier     => 2,
    }

    # What it is wearing.
    ARMOR = {
      ItemKind::Cap          => 30,
      ItemKind::Gloves       => 22,
      ItemKind::Boots        => 22,
      ItemKind::LeatherArmor => 18,
      ItemKind::Shield       => 6,
      ItemKind::ChainMail    => 2,
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
      ItemKind::HastePotion       => 8,
      ItemKind::SlowScroll        => 6,
      ItemKind::HasteScroll       => 3,
      ItemKind::LightWand         => 10,
      ItemKind::StrikingWand      => 6,
    }

    # Coins. One kind, so the weight says nothing; the count is what varies.
    COINS = {ItemKind::Gold => 1}

    # What each species draws for, apart from a weapon and a light.
    #
    # A species is never given a draw for something it would not be carrying.
    # A slime has no hands, so there is no armor draw in its list at all
    # rather than an armor draw it almost never makes.
    DRAWS = {
      Species::Slime => [
        Draw.new(COINS, chance: 70, count: 1..12),
        Draw.new(SWALLOWED, chance: 8),
      ],

      Species::Goblin => [
        Draw.new(ARMOR, chance: 35),
        Draw.new(COINS, chance: 60, count: 3..25),
      ],

      Species::Orc => [
        Draw.new(ARMOR, chance: 55),
        Draw.new(COINS, chance: 70, count: 8..45),
      ],
    }

    # The draws *kind* makes.
    #
    # Its weapon first: the one it always carries, or a roll on `WEAPONS` as
    # often as `Kind#armed` says. Then what its species draws for. Then a
    # light, as often as `Kind#light` says.
    def self.draws(kind : Kind) : Array(Draw)
      found = [] of Draw
      weapon = kind.weapon

      if weapon
        found << Draw.new({weapon => 1}, chance: 100)
      elsif kind.armed > 0
        found << Draw.new(WEAPONS, chance: kind.armed)
      end

      found.concat DRAWS[kind.species]
      found << Draw.new(LIGHTS, chance: kind.light) if kind.light > 0
      found
    end

    # :ditto:
    def self.draws(species : Species) : Array(Draw)
      draws species.default
    end

    # Every kind of item *kind* could be carrying.
    #
    # A spec asserts that nothing outside this ever turns up.
    def self.kinds(kind : Kind | Species) : Set(ItemKind)
      found = Set(ItemKind).new
      draws(kind).each { |draw| draw.kinds.each_key { |item| found << item } }
      found
    end

    # What one creature of *kind* is carrying, rolled on *rng*.
    #
    # *rng* belongs to that one creature. `Game#equip` derives a stream from
    # where the creature stands, so adding an entry to a table shifts what
    # that creature carries and nothing else on the floor.
    def self.for(kind : Kind | Species, rng : Rng) : Array(Item)
      found = [] of Item

      draws(kind).each do |draw|
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
