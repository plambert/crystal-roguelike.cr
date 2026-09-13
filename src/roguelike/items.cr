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
    # Most things nobody has touched. A blessed item is about as common as a
    # cursed one.
    BLESSINGS = {
      {Blessing::Cursed, 10},
      {Blessing::Uncursed, 80},
      {Blessing::Blessed, 10},
    }

    # How often each enchantment comes up on an item nobody has touched.
    ENCHANTMENTS = {
      {-1, 6},
      {0, 78},
      {1, 12},
      {2, 3},
      {3, 1},
    }

    # The same, on a cursed item.
    #
    # A curse leans the other way. A cursed sword is usually worse than a
    # plain one, which is what makes finding out worth the trouble.
    CURSED_ENCHANTMENTS = {
      {-3, 5},
      {-2, 20},
      {-1, 45},
      {0, 30},
    }

    # The same, on a blessed item.
    BLESSED_ENCHANTMENTS = {
      {0, 30},
      {1, 45},
      {2, 20},
      {3, 5},
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

      ItemKind::HealingPotion  => 34,
      ItemKind::IdentifyScroll => 16,
      ItemKind::MappingScroll  => 10,
      ItemKind::LightWand      => 8,
      ItemKind::StrikingWand   => 5,

      ItemKind::Torch  => 22,
      ItemKind::Candle => 18,
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
