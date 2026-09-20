require "./item"
require "./rng"

module Roguelike
  # Where items come from.
  #
  # Everything here rolls on an `Rng`. A run reproduces from its seed, so a
  # spec that rolls ten thousand items twice gets the same ten thousand both
  # times.
  module Items
    # How often each condition comes up, out of the total of the three.
    CONDITIONS = {
      {Condition::Damaged, 25},
      {Condition::Plain, 65},
      {Condition::Masterwork, 10},
    }

    # How often each blessing comes up.
    #
    # Most things nobody has touched. A blessing is twice as common as a
    # curse. Both were equally common and the curse was halved, because an
    # item that cannot be put down again is the harshest thing a floor hands
    # out and it was handing one out every tenth item.
    BLESSINGS = {
      {Blessing::Cursed, 5},
      {Blessing::Uncursed, 85},
      {Blessing::Blessed, 10},
    }

    # How often each enchantment comes up on an item nobody has touched.
    #
    # The minus was halved along with the curse above. Between them they take
    # the share of enchantable items carrying a minus from 11.8 out of 100 to
    # 6.1.
    ENCHANTMENTS = {
      {-1, 3},
      {0, 81},
      {1, 12},
      {2, 3},
      {3, 1},
    }

    # The same, on a cursed item.
    #
    # A curse leans the other way. A cursed sword is usually worse than a
    # plain one.
    CURSED_ENCHANTMENTS = {
      {-3, 5},
      {-2, 20},
      {-1, 45},
      {0, 30},
    }

    # The same, on a blessed item.
    #
    # A blessing leans a plus the way a curse leans a minus, and harder. 85
    # out of 100 blessed weapons carry a plus, for a mean of +1.37 against
    # +0.18 on one nobody has touched.
    BLESSED_ENCHANTMENTS = {
      {0, 15},
      {1, 45},
      {2, 28},
      {3, 12},
    }

    # How many of a stacking kind turn up at once.
    #
    # A potion and a scroll stack but are not here. One turns up at a time.
    # A torch and a candle are not here either. Each burns down on its own, so
    # two of them are two entries rather than one stack of two.
    STACKS = {
      ItemKind::Arrow => 8..20,
      ItemKind::Stone => 6..15,
      ItemKind::Rock  => 2..6,
      ItemKind::Dart  => 3..8,
      ItemKind::Spike => 2..4,
    }

    # How often each kind turns up, out of the total of all of them.
    #
    # A dagger is common. A wand of striking is not. The numbers are relative
    # and nothing depends on their sum.
    WEIGHTS = {
      ItemKind::Dagger     => 40,
      ItemKind::ShortSword => 30,
      ItemKind::LongSword  => 14,
      ItemKind::Rapier     => 8,
      ItemKind::Mace       => 16,
      ItemKind::Spear      => 14,

      ItemKind::Sling => 12,
      ItemKind::Bow   => 10,
      ItemKind::Stone => 30,
      ItemKind::Arrow => 28,

      ItemKind::Rock => 30,
      ItemKind::Dart => 20,

      ItemKind::Cap           => 20,
      ItemKind::LeatherArmour => 18,
      ItemKind::ChainMail     => 6,
      ItemKind::Gloves        => 16,
      ItemKind::Boots         => 16,
      ItemKind::Shield        => 12,

      ItemKind::HealingPotion     => 34,
      ItemKind::IdentifyScroll    => 16,
      ItemKind::MappingScroll     => 10,
      ItemKind::RemoveCurseScroll => 8,
      ItemKind::BlessingScroll    => 6,
      ItemKind::TreasureScroll    => 9,
      ItemKind::DetectionScroll   => 9,
      ItemKind::DarknessScroll    => 6,
      ItemKind::BlindnessScroll   => 7,
      ItemKind::TeleportScroll    => 8,
      ItemKind::RepairScroll      => 8,
      ItemKind::HastePotion       => 10,
      ItemKind::SlowScroll        => 7,
      ItemKind::HasteScroll       => 4,
      ItemKind::LightWand         => 8,
      ItemKind::StrikingWand      => 5,

      ItemKind::Torch  => 22,
      ItemKind::Candle => 18,

      ItemKind::Spike => 7,
    }

    # One item of *kind*, with its variants rolled on *rng*.
    #
    # The blessing is rolled first. The enchantment then rolls on the table
    # that blessing leans toward, so a cursed sword is usually worse than a
    # plain one.
    #
    # *conditions* is the table the condition rolls on. `Loot` passes a
    # different one, because what a monster is carrying is more battered than
    # what is lying about the floor.
    def self.make(rng : Rng, kind : ItemKind, conditions = CONDITIONS) : Item
      blessing = pick rng, BLESSINGS
      condition = kind.enchantable? ? pick(rng, conditions) : Condition::Plain
      enchantment = kind.enchantable? ? pick(rng, enchantments_for(blessing)) : 0
      count = STACKS[kind]?.try { |range| rng.rand range } || 1

      Item.new kind, enchantment, condition, count, blessing: blessing
    end

    # Which enchantment table *blessing* rolls on.
    def self.enchantments_for(blessing : Blessing)
      case blessing
      in .cursed?   then CURSED_ENCHANTMENTS
      in .uncursed? then ENCHANTMENTS
      in .blessed?  then BLESSED_ENCHANTMENTS
      end
    end

    # One item of any kind, rolled on *rng*.
    def self.random(rng : Rng) : Item
      make rng, pick(rng, WEIGHTS)
    end

    # One of *choices*, picked by weight.
    #
    # *choices* is anything that yields a value and a weight. A weight of zero
    # or less is never picked.
    def self.pick(rng : Rng, choices)
      total = choices.sum { |pair| Math.max pair[1], 0 }
      raise ArgumentError.new "nothing to pick from" if total <= 0

      roll = rng.rand total

      choices.each do |value, weight|
        next if weight <= 0
        return value if roll < weight

        roll -= weight
      end

      raise "picked #{roll} of #{total} and fell off the end"
    end
  end
end
