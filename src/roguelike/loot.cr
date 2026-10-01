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

    # A kind or a whole class that does not turn up above some depth.
    #
    # *what* is an `ItemKind` or an `ItemClass`. *from* is the shallowest
    # floor it turns up on. A kind covered by a kind row and a class row
    # waits for the deeper of the two.
    record Gate, what : ItemKind | ItemClass, from : Int32 do
      # Whether this row is about *kind*.
      def covers?(kind : ItemKind) : Bool
        what = @what
        what.is_a?(ItemKind) ? what == kind : what == kind.item_class
      end
    end

    # What waits for a deeper floor, on the ground and in a monster's hands.
    #
    # The better weapons and the heavy armor wait, and so does anything
    # zapped. A new row holds a kind or a class back; nothing here makes
    # anything commoner.
    GATES = [
      Gate.new(ItemKind::LongSword, 2),
      Gate.new(ItemKind::Rapier, 2),
      Gate.new(ItemKind::Spear, 2),
      Gate.new(ItemKind::ChainMail, 3),
      Gate.new(ItemKind::Shield, 2),
      Gate.new(ItemClass::Wand, 2),
      Gate.new(ItemKind::StrikingWand, 3),
      Gate.new(ItemKind::HastePotion, 2),
      Gate.new(ItemKind::BlessingScroll, 2),
      Gate.new(ItemKind::HasteScroll, 3),
    ]

    # The highest `+N` anything turns up with, from floor 1 down. A floor
    # deeper than the last entry reads the last entry.
    #
    # A minus is never capped. A curse is as bad on floor 1 as anywhere.
    CEILINGS = [1, 1, 2, 2, 3]

    # How often a monster's ammunition comes out +1, out of a hundred, from
    # floor 1 down. A floor deeper than the last entry reads the last entry.
    #
    # The whole stack comes out +1 or none of it does.
    FLETCHED = [0, 0, 10, 20, 30]

    # The shallowest floor *kind* turns up on.
    def self.from(kind : ItemKind) : Int32
      GATES.select(&.covers?(kind)).max_of?(&.from) || 1
    end

    # How often ammunition a monster carries on the floor at *depth* is +1,
    # out of a hundred. `nil` holds nothing back.
    def self.fletched(depth : Int32?) : Int32
      return FLETCHED.last unless depth

      FLETCHED[(depth - 1).clamp(0, FLETCHED.size - 1)]
    end

    # Whether *kind* turns up on the floor at *depth*.
    def self.allowed?(kind : ItemKind, depth : Int32) : Bool
      from(kind) <= depth
    end

    # The highest `+N` on the floor at *depth*.
    def self.ceiling(depth : Int32) : Int32
      CEILINGS[(depth - 1).clamp(0, CEILINGS.size - 1)]
    end

    # *table* with every kind that waits for a floor deeper than *depth*
    # left out.
    def self.gated(table : Hash(ItemKind, Int32), depth : Int32) : Hash(ItemKind, Int32)
      table.select { |kind, _weight| allowed? kind, depth }
    end

    # What each species draws for, apart from a weapon and a light.
    #
    # A species is never given a draw for something it would not be carrying.
    # A slime has no hands, so there is no armor draw in its list at all
    # rather than an armor draw it almost never makes. An ant carries
    # nothing.
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

      Species::Ant => Array(Draw).new,

      Species::Jelly => [
        Draw.new(COINS, chance: 40, count: 1..10),
        Draw.new(SWALLOWED, chance: 10),
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
      ranged_weapon = as_kind(kind).ranged_weapon
      if ranged_weapon
        found << ranged_weapon
        ranged_weapon.ammunition.try { |ammunition| found << ammunition }
      end
      found
    end

    # What one creature of *kind* is carrying, rolled on *rng*.
    #
    # *rng* belongs to that one creature. `Game#equip` derives a stream from
    # where the creature stands, so adding an entry to a table shifts what
    # that creature carries and nothing else on the floor.
    #
    # *depth* is the floor it lives on. `nil` holds nothing back.
    #
    # Armor comes out cut for the creature's own size. That rolls nothing.
    #
    # The weapon comes first, so `Monster#outfit` readies it before anything
    # else that wants the hand.
    def self.for(kind : Kind | Species, rng : Rng, depth : Int32? = nil) : Array(Item)
      found = [] of Item
      size = kind.size

      draws(kind).each do |draw|
        taken = one draw, rng, depth, size
        found << taken if taken
      end

      found.concat shooting(as_kind(kind), rng, depth)
    end

    # What *kind* shoots with and how much it has to shoot, rolled on *rng*.
    # Empty for a kind with no `Kind#ranged_weapon`, which rolls nothing.
    #
    # `#for` rolls this after every draw, so a kind with no ranged weapon carries
    # what it carried before monsters shot.
    #
    # The ranged weapon rolls the way any other weapon a monster carries does.
    # The ammunition is sound, and `#fletched` says how often it is +1.
    def self.shooting(kind : Kind, rng : Rng, depth : Int32?) : Array(Item)
      ranged_weapon = kind.ranged_weapon
      ammunition = ranged_weapon.try &.ammunition
      return [] of Item unless ranged_weapon && ammunition

      weapon = Items.make rng, ranged_weapon, CONDITIONS, depth.try { |deep| ceiling deep }
      count = Math.max kind.quiver.roll(rng), 1
      plus = rng.rand(100) < fletched(depth) ? 1 : 0

      [weapon, Item.new(ammunition, plus, count: count)]
    end

    # The kind *kind* stands for.
    private def self.as_kind(kind : Kind | Species) : Kind
      kind.is_a?(Species) ? kind.default : kind
    end

    # What one draw produces. `nil` when it produces nothing.
    #
    # Anything that burns comes out alight, and `Game#lights` reads it as a
    # carried source.
    private def self.one(draw : Draw, rng : Rng, depth : Int32?, size : Size) : Item?
      return unless rng.rand(100) < draw.chance

      kinds = depth ? gated(draw.kinds, depth) : draw.kinds
      return if kinds.empty?

      kind = Items.pick rng, kinds
      return Item.new kind, count: rng.rand(draw.count) if kind.item_class.treasure?

      item = Items.make rng, kind, CONDITIONS, depth.try { |deep| ceiling deep }, size
      item.kindle
      item
    end
  end
end
