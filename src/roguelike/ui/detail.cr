module Roguelike::Ui
  # Everything the character knows about one item, written out.
  #
  # The sidebar writes an item in sixteen columns. This is the other half of
  # that bargain: point at a row and read the whole thing, with no
  # abbreviation and nothing left out.
  #
  # It says only what the character has found out. An unidentified potion is
  # named by its colour and nothing is said about what drinking it would do.
  module Detail
    # What to write about the item in *slot*, or `nil` for an empty slot.
    #
    # The first line is the slot, written out, so a person who pointed at
    # `qvr` is told it is the quiver.
    def self.about(game : Game, slot : Slot) : Array(String)?
      item = game.player.in_slot slot
      return unless item

      [slot.label] + about game, item
    end

    # What to write about *item*.
    def self.about(game : Game, item : Item) : Array(String)
      lines = [game.name item]
      kind = item.kind

      lines.concat facts(item)
      lines << "weight #{item.weight}"
      lines << "cursed: it will not come off" if item.blessing_known? && item.cursed?

      unless game.lore.known? kind
        lines << "nobody has found out what this is"
      end

      lines
    end

    # The lines about what the item does, which depend on what it is.
    private def self.facts(item : Item) : Array(String)
      case item.kind.item_class
      when .melee?, .thrown? then hitting item
      when .ranged_weapon?   then shooting item
      when .ammunition?      then shot item
      when .armour?          then worn item
      when .light?           then burning item
      when .wand?            then charged item
      else                        [] of String
      end
    end

    # What a weapon swung by hand does.
    private def self.hitting(item : Item) : Array(String)
      found = ["damage #{item.damage}"]
      found << "thrown #{item.kind.reach} squares" if item.kind.reach > 0
      found
    end

    # What a ranged weapon does, and what it takes.
    private def self.shooting(item : Item) : Array(String)
      found = ["shoots #{item.kind.reach} squares"]
      ammunition = item.kind.ammunition
      found << "takes #{ammunition.plural}" if ammunition
      found
    end

    # What ammunition does, and what fires it.
    private def self.shot(item : Item) : Array(String)
      found = ["damage #{item.damage}"]
      weapon = item.kind.ranged_weapon
      found << "shot from a #{weapon.label}" if weapon
      found
    end

    # What a piece of armour does, and where it goes.
    private def self.worn(item : Item) : Array(String)
      found = ["armour #{item.armour}"]
      where = item.kind.slot
      found << "worn on the #{where.to_s.downcase}" if where
      found
    end

    # How far something burning throws light, and whether it is alight.
    private def self.burning(item : Item) : Array(String)
      ["lights #{item.kind.light} squares", item.lit? ? "alight" : "not lit"]
    end

    # How many uses a wand has left.
    private def self.charged(item : Item) : Array(String)
      left = item.charges
      return [] of String unless left

      ["charges #{left}/#{item.kind.charges}"]
    end
  end
end
