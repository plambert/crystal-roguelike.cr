require "json"
require "./dice"
require "./effect"

module Roguelike
  # What sort of thing an item is.
  #
  # The class decides what a character can do with an item. A `Melee` weapon
  # goes in the hand. `Ammunition` goes in the quiver and needs a
  # `RangedWeapon`. `Thrown` needs nothing but an arm.
  enum ItemClass
    Melee
    RangedWeapon
    Ammunition
    Thrown
    Armour
    Potion
    Scroll
    Wand
    Light

    # Used on something else rather than worn, drunk or swung. A spike is
    # one. Nothing here goes in a slot.
    Tool

    # Coins. A character counts them rather than carrying them.
    Treasure

    # Whether a `+N` means anything on this class.
    def enchantable? : Bool
      melee? || ranged_weapon? || ammunition? || thrown? || armour?
    end

    # Whether several of these are held as one entry with a count.
    #
    # Ammunition and thrown weapons stack because a person carries dozens.
    # Potions and scrolls stack because two potions of one kind are
    # interchangeable. Tools stack because one spike is the same as another.
    # Wands do not, because two wands have different charges left.
    def stacks? : Bool
      ammunition? || thrown? || potion? || scroll? || tool? || treasure?
    end

    # Whether a character has to find out what one of these is.
    #
    # A sword is a sword on sight. A potion is a colour until somebody drinks
    # one.
    def disguised? : Bool
      potion? || scroll? || wand?
    end
  end

  # Where a piece of armour is worn.
  enum ArmourSlot
    Head
    Body
    Hands
    Feet
    Shield

    # What the slot is called, for a readout.
    def label : String
      to_s.downcase
    end
  end

  # How well made an item is, or how badly worn.
  #
  # A condition changes what an item does and what it is called. A damaged
  # sword hits for less. A masterwork one hits for more.
  enum Condition
    Damaged
    Plain
    Masterwork

    # The word that goes in an item's name. `nil` for a plain one, which is
    # called nothing at all.
    def label : String?
      case self
      in .damaged?    then "damaged"
      in .plain?      then nil
      in .masterwork? then "masterwork"
      end
    end

    # What this condition adds to a weapon's damage or a piece of armour's
    # rating.
    def modifier : Int32
      case self
      in .damaged?    then -1
      in .plain?      then 0
      in .masterwork? then 1
      end
    end
  end

  # Whether a god has touched an item, and which way.
  #
  # This is not the same thing as `Condition`. A condition is how well the
  # item was made and how worn it is. A blessing is what happens when it is
  # used, and whether it can be put down again.
  #
  # A blessing is hidden on each item until the character finds out. Two
  # identical swords may be blessed and cursed, so this cannot be learned per
  # kind the way a potion's colour is.
  enum Blessing
    Cursed
    Uncursed
    Blessed

    # The word that goes in an item's name, once the character knows.
    def label : String
      to_s.downcase
    end

    # Whether the item refuses to be taken off or put down.
    def sticks? : Bool
      cursed?
    end

    # What this does to how strongly an item works, as a percentage.
    #
    # A cursed potion of healing puts back half and a blessed one puts back
    # double. The item still works: a curse makes a thing worse rather than
    # useless.
    def potency : Int32
      case self
      in .cursed?   then 50
      in .uncursed? then 100
      in .blessed?  then 200
      end
    end
  end

  # Everything one kind of item is.
  record ItemFacts,
    label : String,
    plural : String,
    item_class : ItemClass,
    damage : Dice = Dice::NONE,
    armour : Int32 = 0,
    slot : ArmourSlot? = nil,
    ranged_weapon : ItemKind? = nil,
    charges : Int32 = 0,
    weight : Int32 = 10,
    light : Int32 = 0,
    range : Int32 = 0,
    effect : Effect = Effect::None,
    power : Dice = Dice::NONE,
    uncountable : Bool = false do
    # How far a thing nobody made for throwing goes, before its weight is
    # taken off.
    ARM = 10

    # How much weight costs one square of that.
    BURDEN = 20

    # How far a thing goes however heavy it is. It lands at the thrower's
    # feet.
    NEAR = 1

    # How far one of these goes when it is let go.
    #
    # A thing made for the job says so. A bow and a sling say how far they
    # shoot, and a dart and a rock say how far an arm sends them.
    #
    # Anything else goes as far as its weight allows. A dagger crosses a
    # room and a suit of chain mail goes one square.
    def reach : Int32
      return range if range > 0

      Math.max ARM - weight // BURDEN, NEAR
    end

    # Whether a `+N` means anything on this kind.
    def enchantable? : Bool
      item_class.enchantable?
    end

    # Whether several of these are held as one entry with a count.
    def stacks? : Bool
      item_class.stacks?
    end

    # Whether a character has to find out what one of these is.
    def disguised? : Bool
      item_class.disguised?
    end

    # Whether the name takes no article.
    def uncountable? : Bool
      uncountable
    end

    # Whether one of these can be set alight.
    def light? : Bool
      light > 0
    end
  end

  # Every kind of item there is.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name, and an old save has to keep meaning what it meant.
  enum ItemKind
    # Melee weapons.
    Dagger
    ShortSword
    LongSword
    Rapier
    Mace
    Spear

    # Ranged weapons and what they fire.
    Sling
    Bow
    Stone
    Arrow

    # Thrown by hand.
    Rock
    Dart

    # Armour.
    Cap
    LeatherArmour
    ChainMail
    Gloves
    Boots
    Shield

    # Drunk, read and zapped.
    HealingPotion
    IdentifyScroll
    MappingScroll
    LightWand
    StrikingWand

    # Carried for the light.
    Torch
    Candle

    # Counted rather than carried.
    Gold

    # Driven under a door.
    Spike

    # Read to bless one thing, or everything.
    BlessingScroll

    # Read to take a curse off.
    RemoveCurseScroll

    # Read to find the gold.
    TreasureScroll

    # Read to find what is lying about.
    DetectionScroll

    # Read to put the lights out.
    DarknessScroll

    # Read to blind something.
    BlindnessScroll

    # Read to go somewhere else on this floor.
    TeleportScroll

    # Read to take the damage out of something.
    RepairScroll

    # What this kind is.
    def facts : ItemFacts
      ItemKinds::FACTS[self]
    end

    # What one of these is called, when the character knows.
    def label : String
      facts.label
    end

    # What several are called.
    def plural : String
      facts.plural
    end

    # What sort of thing it is.
    def item_class : ItemClass
      facts.item_class
    end

    # What it does to whatever it hits.
    def damage : Dice
      facts.damage
    end

    # What it takes off an attack against whoever wears it.
    def armour : Int32
      facts.armour
    end

    # Where it is worn. `nil` for anything that is not armour.
    def slot : ArmourSlot?
      facts.slot
    end

    # What fires it. `nil` for anything that is not ammunition.
    def ranged_weapon : ItemKind?
      facts.ranged_weapon
    end

    # What this fires. `nil` for anything that is not a ranged weapon.
    #
    # The other way round from `#ranged_weapon`. The table names the weapon
    # the ammunition, because ammunition is what needs one.
    def ammunition : ItemKind?
      return unless item_class.ranged_weapon?

      ItemKind.values.find { |kind| kind.ranged_weapon == self }
    end

    # How many times it can be used before it is spent.
    def charges : Int32
      facts.charges
    end

    # How far one of these throws light once it is lit. Zero for anything
    # that does not burn.
    def light : Int32
      facts.light
    end

    # Whether one of these can be set alight.
    def light? : Bool
      facts.light?
    end

    # How far one of these goes when it is thrown or fired.
    def reach : Int32
      facts.reach
    end

    # What using one of these does. `None` for most things.
    def effect : Effect
      facts.effect
    end

    # How strong that effect is. The dice a potion heals for and the dice a
    # wand hits for.
    def power : Dice
      facts.power
    end

    # Whether a `+N` means anything on this kind.
    def enchantable? : Bool
      facts.enchantable?
    end

    # Whether several are held as one entry with a count.
    def stacks? : Bool
      facts.stacks?
    end

    # Whether a character has to find out what one of these is.
    def disguised? : Bool
      facts.disguised?
    end

    # Whether the name takes no article.
    #
    # "chain mail" is a substance and "boots" is a pair. Neither takes "a".
    def uncountable? : Bool
      facts.uncountable?
    end

    # The key a JSON object uses for this kind.
    #
    # `Lore` holds a `Hash(ItemKind, String)`. A JSON object key has to be a
    # string, and a save file that held the member number would break the
    # first time a member was inserted.
    def to_json_object_key : String
      to_s
    end

    # :ditto:
    def self.from_json_object_key?(key : String) : ItemKind?
      parse? key
    end

    # Every kind of the given class.
    def self.of_class(item_class : ItemClass) : Array(ItemKind)
      values.select { |kind| kind.item_class == item_class }
    end
  end

  # The table behind `ItemKind`. An enum body cannot hold it.
  module ItemKinds
    FACTS = {
      ItemKind::Dagger => ItemFacts.new("dagger", "daggers", ItemClass::Melee,
        damage: Dice.new(1, 4), weight: 10),
      ItemKind::ShortSword => ItemFacts.new("short sword", "short swords", ItemClass::Melee,
        damage: Dice.new(1, 6), weight: 30),
      ItemKind::LongSword => ItemFacts.new("long sword", "long swords", ItemClass::Melee,
        damage: Dice.new(1, 8), weight: 40),
      ItemKind::Rapier => ItemFacts.new("rapier", "rapiers", ItemClass::Melee,
        damage: Dice.new(1, 6, 1), weight: 25),
      ItemKind::Mace => ItemFacts.new("mace", "maces", ItemClass::Melee,
        damage: Dice.new(1, 6, 1), weight: 60),
      ItemKind::Spear => ItemFacts.new("spear", "spears", ItemClass::Melee,
        damage: Dice.new(1, 8), weight: 50),

      ItemKind::Sling => ItemFacts.new("sling", "slings",
        ItemClass::RangedWeapon, weight: 5, range: 12),
      ItemKind::Bow => ItemFacts.new("bow", "bows",
        ItemClass::RangedWeapon, weight: 30, range: 16),
      ItemKind::Stone => ItemFacts.new("stone", "stones", ItemClass::Ammunition,
        damage: Dice.new(1, 4), ranged_weapon: ItemKind::Sling, weight: 5),
      ItemKind::Arrow => ItemFacts.new("arrow", "arrows", ItemClass::Ammunition,
        damage: Dice.new(1, 6), ranged_weapon: ItemKind::Bow, weight: 2),

      ItemKind::Rock => ItemFacts.new("rock", "rocks", ItemClass::Thrown,
        damage: Dice.new(1, 3), weight: 10, range: 10),
      ItemKind::Dart => ItemFacts.new("dart", "darts", ItemClass::Thrown,
        damage: Dice.new(1, 4), weight: 2, range: 14),

      ItemKind::Cap => ItemFacts.new("cap", "caps", ItemClass::Armour,
        armour: 1, slot: ArmourSlot::Head, weight: 10),
      ItemKind::LeatherArmour => ItemFacts.new("leather armour", "suits of leather armour",
        ItemClass::Armour, armour: 2, slot: ArmourSlot::Body, weight: 100,
        uncountable: true),
      ItemKind::ChainMail => ItemFacts.new("chain mail", "suits of chain mail",
        ItemClass::Armour, armour: 4, slot: ArmourSlot::Body, weight: 300,
        uncountable: true),
      ItemKind::Gloves => ItemFacts.new("gloves", "pairs of gloves", ItemClass::Armour,
        armour: 1, slot: ArmourSlot::Hands, weight: 10, uncountable: true),
      ItemKind::Boots => ItemFacts.new("boots", "pairs of boots", ItemClass::Armour,
        armour: 1, slot: ArmourSlot::Feet, weight: 20, uncountable: true),
      ItemKind::Shield => ItemFacts.new("shield", "shields", ItemClass::Armour,
        armour: 2, slot: ArmourSlot::Shield, weight: 60),

      ItemKind::HealingPotion => ItemFacts.new("potion of healing", "potions of healing",
        ItemClass::Potion, weight: 20,
        effect: Effect::Heal, power: Dice.new(2, 4, 2)),
      ItemKind::IdentifyScroll => ItemFacts.new("scroll of identify", "scrolls of identify",
        ItemClass::Scroll, weight: 5, effect: Effect::Identify),
      ItemKind::MappingScroll => ItemFacts.new("scroll of magic mapping",
        "scrolls of magic mapping", ItemClass::Scroll, weight: 5,
        effect: Effect::MapFloor),
      ItemKind::LightWand => ItemFacts.new("wand of light", "wands of light",
        ItemClass::Wand, charges: 6, weight: 7, effect: Effect::Light),
      ItemKind::StrikingWand => ItemFacts.new("wand of striking", "wands of striking",
        ItemClass::Wand, charges: 5, weight: 7, range: 12,
        effect: Effect::Strike, power: Dice.new(2, 4)),

      ItemKind::Torch => ItemFacts.new("torch", "torches", ItemClass::Light,
        weight: 20, light: 6),
      ItemKind::Candle => ItemFacts.new("candle", "candles", ItemClass::Light,
        weight: 5, light: 3),

      ItemKind::Gold => ItemFacts.new("gold piece", "gold pieces", ItemClass::Treasure,
        weight: 1),

      ItemKind::Spike => ItemFacts.new("iron spike", "iron spikes", ItemClass::Tool,
        weight: 8),

      ItemKind::BlessingScroll => ItemFacts.new("scroll of blessing",
        "scrolls of blessing", ItemClass::Scroll, weight: 5,
        effect: Effect::Bless),
      ItemKind::RemoveCurseScroll => ItemFacts.new("scroll of remove curse",
        "scrolls of remove curse", ItemClass::Scroll, weight: 5,
        effect: Effect::RemoveCurse),
      ItemKind::TreasureScroll => ItemFacts.new("scroll of treasure detection",
        "scrolls of treasure detection", ItemClass::Scroll, weight: 5,
        effect: Effect::DetectTreasure),
      ItemKind::DetectionScroll => ItemFacts.new("scroll of item detection",
        "scrolls of item detection", ItemClass::Scroll, weight: 5,
        effect: Effect::DetectItems),
      ItemKind::DarknessScroll => ItemFacts.new("scroll of darkness",
        "scrolls of darkness", ItemClass::Scroll, weight: 5,
        effect: Effect::Darkness),
      ItemKind::BlindnessScroll => ItemFacts.new("scroll of blindness",
        "scrolls of blindness", ItemClass::Scroll, weight: 5,
        effect: Effect::Blind),
      ItemKind::TeleportScroll => ItemFacts.new("scroll of minor teleport",
        "scrolls of minor teleport", ItemClass::Scroll, weight: 5,
        effect: Effect::Teleport),
      ItemKind::RepairScroll => ItemFacts.new("scroll of repair",
        "scrolls of repair", ItemClass::Scroll, weight: 5,
        effect: Effect::Repair),
    }
  end
end
