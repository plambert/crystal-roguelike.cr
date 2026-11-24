require "../roguelike"

module Roguelike
  # Whether one item is better than another, as far as the character can
  # tell.
  #
  # Everything here reads what the character knows. The enchantment and the
  # condition of a thing are known when its kind is, and a blessing is known
  # only when the item says so. An answer the character could not reach is
  # `nil`.
  module Appraisal
    # Whether *item* is better than what *player* has readied where it
    # would go. `nil` when that cannot be known, and for anything that is
    # not a melee weapon or a piece of armor.
    #
    # A melee weapon is better when it does more damage in a turn than the
    # weapon in the hand, or than bare hands. Armor is better when it takes
    # more off an attack than the piece in its slot, or than nothing. A
    # shield of the wrong size counts what `Item#misfit` costs it.
    #
    # A thing known to be cursed is never better, and neither is armor
    # that does not fit.
    def self.better?(item : Item, player : Player, lore : Lore) : Bool?
      return unless lore.known? item.kind
      return false if item.known_cursed?

      case item.kind.item_class
      when .melee? then sharper? item, player, lore
      when .armor? then stouter? item, player, lore
      end
    end

    # What bare hands do in one turn.
    def self.bare_hands : Float64
      Player::UNARMED.average / (Costs.swing(nil) / Costs::TURN)
    end

    # Whether the weapon *item* does more in a turn than what is swung now.
    private def self.sharper?(item : Item, player : Player, lore : Lore) : Bool?
      held = player.wielded
      return item.damage_per_turn > bare_hands unless held && Player.swung?(held)
      return unless lore.known? held.kind

      item.damage_per_turn > held.damage_per_turn
    end

    # Whether the armor *item* takes more off an attack than what is worn in
    # its slot now.
    private def self.stouter?(item : Item, player : Player, lore : Lore) : Bool?
      slot = Slot.for item
      return unless slot
      return false unless item.fits? Player::SIZE

      worn = player.in_slot slot
      return item.armor(Player::SIZE) > 0 unless worn
      return unless lore.known? worn.kind

      item.armor(Player::SIZE) > worn.armor(Player::SIZE)
    end
  end
end
