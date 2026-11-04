require "../../crystal-roguelike"

module Roguelike::Ui
  # Everything the character knows about one thing, written out.
  #
  # The sidebar writes a row in sixteen columns. This is the other half of
  # that bargain: point at a row and read the whole thing, with no
  # abbreviation and nothing left out.
  #
  # It says only what the character has found out. An unidentified potion is
  # named by its color and nothing is said about what drinking it would do.
  # A creature the character makes out only as a shape is a shape here too:
  # its species, its hit points and what it is doing all wait for light on it.
  module Detail
    # What armor that adds nothing to a blow says about it.
    UNHURRIED = "does not slow your attacks"

    # What is written about a thing too far off to make out more of.
    TOO_FAR = "too far off to make out more"

    # What to write about the item in *slot*, or `nil` for an empty slot.
    #
    # The first line is the slot, written out, so a person who pointed at
    # `qvr` is told it is the quiver.
    def self.about(game : Game, slot : Slot) : Array(String)?
      item = game.player.in_slot slot
      return unless item

      about game, item, slot: slot
    end

    # What to write about *item*.
    #
    # *regard* says how well the character has made it out. Short of
    # `Regard::Everything` this writes the kind and no more: a spear across
    # the room is a spear, and the notch in its blade and the curse on it
    # wait until somebody stands over it.
    def self.about(game : Game, item : Item,
                   regard : Regard = Regard::Everything,
                   slot : Slot? = nil) : Array(String)
      # The blessing is on a line of its own below, beside the mark a list
      # puts against the item. The blessing word in the name would be the
      # same thing twice.
      name = game.name item, regard: regard, blessing: false
      return [name, TOO_FAR] unless regard.everything?

      lines = [name]
      kind = item.kind

      lines << marked(Palette.slot(slot), slot.note) if slot
      lines << blessing(item) unless item.food? || item.remains? || item.reagent?
      lines << marked(Palette.burning, Palette::LIT_WORD) if item.lit?
      lines.concat facts(game, item)
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
      return [creature.kind.size.label, ExaminePane::MOVING] unless regard.everything?

      lines = [
        creature.label,
        creature.description,
        "hit points #{creature.hit_points}/#{creature.max_hit_points}",
        game.floor.doing(creature),
      ]
      ExaminePane.gear(creature, game.lore).try { |armed| lines << armed }
      lines
    end

    # What to write about *fitting*.
    def self.about(fitting : Fixture) : Array(String)
      [fitting.label, fitting.description]
    end

    # What to write about *terrain*.
    def self.about(terrain : Terrain) : Array(String)
      [terrain.label, terrain.description]
    end

    # The blessing of *item*, as the mark a list puts against it and the word
    # for that mark.
    #
    # The list has only the mark. The word is here. The column is then
    # readable without a key elsewhere.
    #
    # An item whose blessing is not worked out has no mark. The line is the
    # word alone.
    private def self.blessing(item : Item) : String
      word = Palette.blessing_word item
      mark = Palette.blessing item
      return word unless mark

      marked mark, word
    end

    # *look* and *word*, the mark first.
    private def self.marked(look : Look, word : String) : String
      "#{look.glyph} #{word}"
    end

    # What the box says of something nobody eats.
    NOTHING_EATS = "nothing eats this"

    # What the box says of a part kept for alchemy.
    KEPT = "worth keeping for alchemy"

    # The lines about what the item does, which depend on what it is.
    private def self.facts(game : Game, item : Item) : Array(String)
      case item.kind.item_class
      when .melee?, .thrown?  then hitting game, item
      when .ranged_weapon?    then shooting item
      when .ammunition?       then shot item
      when .armor?            then worn item
      when .light?            then burning item
      when .wand?             then charged item
      when .food?, .delicacy? then eaten item
      when .remains?          then [NOTHING_EATS]
      when .reagent?          then [NOTHING_EATS, KEPT]
      else                         [] of String
      end
    end

    # What a food is like to eat: how filling, what it does, and how fresh.
    private def self.eaten(item : Item) : Array(String)
      return [NOTHING_EATS] unless item.edible?

      lines = [filling(item.nourishment), item.category.label]
      Food.buff(item.kind).try { |status| lines << buffing(status) }
      lines << freshness(item)
      lines << corpse_use(item) if item.corpse?
      lines
    end

    # What can be done with the corpse *item*.
    private def self.corpse_use(item : Item) : String
      if item.butchery.beast? && item.freshness.fresh?
        return "cut it into meat, or eat it here when starving"
      end

      "eat it here when starving"
    end

    # How filling *points* of satiety are, in words.
    private def self.filling(points : Int32) : String
      case points
      when 1200.. then "a full meal"
      when 600..  then "a meal"
      when 300..  then "a light meal"
      else             "a snack"
      end
    end

    # What eating a fresh one of a family with the buff *status* does.
    private def self.buffing(status : Event::Status) : String
      case status
      when .well_fed?    then "fresh, it quickens you for a while"
      when .refreshed?   then "fresh, it slows your thirst for a while"
      when .steady_aim?  then "fresh, it steadies your aim for a while"
      when .steady_hand? then "fresh, it steadies your hand for a while"
      when .mending?     then "fresh, it closes your wounds faster for a long while"
      when .mighty?      then "fresh, it makes your blows hit harder for a long while"
      when .night_eyes?  then "fresh, it lets you see nearby in the dark for a long while"
      when .quickened?   then "fresh, it makes you much quicker for a long while"
      else                    "fresh, it does you good"
      end
    end

    # How fresh *item* is, and what that means for eating it.
    private def self.freshness(item : Item) : String
      return "it keeps" unless item.food_facts.spoils?

      case item.freshness
      in .fresh?  then "fresh"
      in .stale?  then "stale: it feeds half as much"
      in .rotten? then "rotten: eating it will make you sick"
      end
    end

    # What a weapon swung by hand does.
    #
    # A melee weapon says what the character would do with it in a turn, in
    # the armor they have on.
    private def self.hitting(game : Game, item : Item) : Array(String)
      melee = item.kind.item_class.melee?
      found = ["damage #{item.damage}"]
      found << pace(melee ? "swing" : "throw", item)
      found << "thrown #{item.kind.reach} squares" if item.kind.reach > 0
      found << rate(game, item) if melee
      found
    end

    # What the character does in one turn holding *item*, as "3.21 dps
    # against the orc".
    def self.rate(game : Game, item : Item? = game.player.wielded) : String
      against, whom = target game
      "#{dps game.player.per_turn(against, item)} dps against #{whom}"
    end

    # A damage rate written the way the game writes it, to two places.
    def self.dps(rate : Float64) : String
      "%.2f" % rate
    end

    # The armor class a damage rate is worked out against, and what to call
    # it.
    #
    # The creature being fought, while the bar for it shows. Otherwise
    # `Combat::REFERENCE`.
    def self.target(game : Game) : {Int32, String}
      creature = game.fought
      return {Combat::REFERENCE, "AC #{Combat::REFERENCE}"} unless creature

      {creature.armor_class, Naming.creature(creature, game.fought_regard)}
    end

    # How long one use of *item* takes, as a word and as a number.
    private def self.pace(verb : String, item : Item) : String
      cost = item.kind.swing
      "#{verb} #{Costs.pace_word cost} (#{cost})"
    end

    # What a ranged weapon does, and what it takes.
    private def self.shooting(item : Item) : Array(String)
      found = ["shoots #{item.kind.reach} squares", pace("shot", item)]
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

    # What a piece of armor does, where it goes, and what it does to the
    # pace.
    private def self.worn(item : Item) : Array(String)
      kind = item.kind
      where = kind.slot
      found = ["armor #{item.armor}"]
      found << "worn on the #{where.to_s.downcase}" if where
      return found << "does not change your pace" unless where.try(&.body?) || where.try(&.shield?)

      found << (where.try(&.body?) ? walking(kind.bulk) : "does not slow a step")
      blow = Costs.blow_drag [item]
      found << (blow > 0 ? "attacks #{Costs.share blow} slower (+#{percent blow}%)" : UNHURRIED)
      found
    end

    # What body armor of class *bulk* does to a step, against a normal turn.
    private def self.walking(bulk : Bulk) : String
      change = bulk.step - Costs::TURN
      return "#{bulk.label}: steps at a normal pace" if change.zero?

      word, sign = change > 0 ? {"slower", '+'} : {"quicker", '-'}
      "#{bulk.label}: steps #{Costs.share change.abs} #{word} (#{sign}#{percent change.abs}%)"
    end

    # *cost*, in energy, as a share of a turn out of a hundred.
    private def self.percent(cost : Int32) : Int32
      cost * 100 // Costs::TURN
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
