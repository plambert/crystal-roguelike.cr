module Roguelike::Ui
  # Everything the character knows about one thing, written out.
  #
  # The sidebar writes a row in sixteen columns. This is the other half of
  # that bargain: point at a row and read the whole thing, with no
  # abbreviation and nothing left out.
  #
  # It says only what the character has found out. An unidentified potion is
  # named by its colour and nothing is said about what drinking it would do.
  # A creature the character makes out only as a shape is a shape here too:
  # its species, its hit points and what it is doing all wait for light on it.
  module Detail
    # What is written about a thing too far off to make out more of.
    TOO_FAR = "too far off to make out more"

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
    #
    # *regard* says how well the character has made it out. Short of
    # `Regard::Everything` this writes the kind and no more: a spear across
    # the room is a spear, and the notch in its blade and the curse on it
    # wait until somebody stands over it.
    def self.about(game : Game, item : Item,
                   regard : Regard = Regard::Everything) : Array(String)
      name = game.name item, regard: regard
      return [name, TOO_FAR] unless regard.everything?

      lines = [name]
      kind = item.kind

      lines.concat facts(item)
      lines << "weight #{item.weight}"
      lines << "cursed: it will not leave a slot" if item.blessing_known? && item.cursed?

      unless game.lore.known? kind
        lines << "nobody has found out what this is"
      end

      lines
    end

    # What to write about *creature*, as far as the character has made it out.
    #
    # `Regard::Shape` is a creature standing against light behind it. Its size
    # is what reaches the character, so its size and that it is moving are all
    # this says. Its species, its hit points and what it is doing all wait for
    # light on it.
    #
    # `nil` for a creature the character cannot see at all.
    def self.about(game : Game, creature : Monster, regard : Regard) : Array(String)?
      return unless regard.made_out?
      return [creature.species.size.label, ExaminePane::MOVING] unless regard.everything?

      [
        creature.label,
        creature.description,
        "hit points #{creature.hit_points}/#{creature.max_hit_points}",
        game.floor.awareness(creature).label,
      ]
    end

    # What to write about *fitting*.
    def self.about(fitting : Fixture) : Array(String)
      [fitting.label, fitting.description]
    end

    # What to write about *terrain*.
    def self.about(terrain : Terrain) : Array(String)
      [terrain.label, terrain.description]
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
