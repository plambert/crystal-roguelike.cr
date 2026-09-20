module Roguelike::Ui
  # What an item is called where there is no room for what it is called.
  #
  # `Lore#name` writes the whole thing: "a blessed masterwork +1 chain mail".
  # The sidebar has 22 columns and a slot word takes six of them, so it writes
  # "bls mwk +1 chain" instead. Nothing is dropped: every word is shortened
  # rather than left out, so two items that read differently in full read
  # differently here.
  #
  # A tooltip and every menu write the whole name. This is for the column.
  module Naming
    # What each condition is shortened to.
    CONDITIONS = {
      Condition::Damaged    => "dmg",
      Condition::Plain      => "",
      Condition::Masterwork => "mwk",
    }

    # What each blessing is shortened to.
    #
    # Nothing for uncursed. Most things are uncursed, and a column of "unc"
    # says less than a blank does.
    BLESSINGS = {
      Blessing::Cursed   => "crs",
      Blessing::Uncursed => "",
      Blessing::Blessed  => "bls",
    }

    # The kinds whose own label is too long for a column.
    #
    # Everything else keeps its label. A dagger is a dagger in both.
    KINDS = {
      ItemKind::ShortSword        => "short swd",
      ItemKind::LongSword         => "long swd",
      ItemKind::LeatherArmour     => "leather",
      ItemKind::ChainMail         => "chain",
      ItemKind::HealingPotion     => "healing potion",
      ItemKind::IdentifyScroll    => "identify scroll",
      ItemKind::MappingScroll     => "mapping scroll",
      ItemKind::BlessingScroll    => "blessing scroll",
      ItemKind::RemoveCurseScroll => "uncurse scroll",
      ItemKind::TreasureScroll    => "treasure scroll",
      ItemKind::DetectionScroll   => "detect scroll",
      ItemKind::DarknessScroll    => "dark scroll",
      ItemKind::BlindnessScroll   => "blind scroll",
      ItemKind::TeleportScroll    => "teleport scroll",
      ItemKind::LightWand         => "light wand",
      ItemKind::StrikingWand      => "striking wand",
      ItemKind::Gold              => "gold",
    }

    # What *item* is called, as *lore* knows it, short enough for a column.
    #
    #     14 +1 arrow
    #     bls mwk +1 chain
    #     swirly potion
    #     ZELGO MER scroll
    #
    # The count goes in front and the noun stays singular. "14 arrow" is one
    # column shorter than "14 arrows" and says the same thing in a list.
    def self.short(lore : Lore, item : Item) : String
      words = [] of String
      words << item.count.to_s if item.count > 1
      words << BLESSINGS[item.blessing] if item.blessing_known?
      words << CONDITIONS[item.condition]
      words << Lore.enchantment(item.enchantment) unless item.enchantment.zero?
      words << noun lore, item

      words.reject(&.empty?).join ' '
    end

    # What *item* is, without the count and without the variants.
    #
    # A kind nobody has found out is named by what it looks like: "swirly
    # potion" rather than "potion of healing". A kind with no look rolled for
    # it at all falls back to its own name, which is what a floor built by
    # hand for a spec gives.
    private def self.noun(lore : Lore, item : Item) : String
      kind = item.kind
      look = lore.known?(kind) ? nil : lore.appearance(kind)
      return KINDS[kind]? || kind.label unless look

      case kind.item_class
      when .potion? then "#{look} potion"
      when .wand?   then "#{look} wand"
      when .scroll? then "#{look} scroll"
      else               KINDS[kind]? || kind.label
      end
    end
  end
end
