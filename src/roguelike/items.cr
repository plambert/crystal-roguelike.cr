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

    # How often each enchantment comes up.
    #
    # Most things are plain. A cursed item is about as common as a blessed
    # one, and both are rarer than nothing at all.
    ENCHANTMENTS = {
      {-2, 3},
      {-1, 9},
      {0, 70},
      {1, 12},
      {2, 5},
      {3, 1},
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
    def self.make(rng : Rng, kind : ItemKind) : Item
      condition = kind.enchantable? ? pick(rng, CONDITIONS) : Condition::Plain
      enchantment = kind.enchantable? ? pick(rng, ENCHANTMENTS) : 0
      count = STACKS[kind]?.try { |range| rng.rand range } || 1

      Item.new kind, enchantment, condition, count
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
