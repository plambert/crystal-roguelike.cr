require "json"
require "../../roguelike"

module Roguelike
  module Events
    # What the facts call the character wherever they name a species.
    PLAYER = "player"

    # The dice a blow rolls for damage, and the damage they came to.
    #
    # *total* is `nil` for a miss, which rolls no damage.
    record Roll, dice : String, total : Int32? = nil do
      include JSON::Serializable
    end

    # Which facts about an item the character had made out.
    #
    # Enchantment is always known today. The flag is here so that a reader
    # needs no change on the day it is not.
    record Known, kind : Bool, enchantment : Bool, blessing : Bool do
      include JSON::Serializable
    end

    # One item as the game holds it.
    #
    # *known* is set for the character's own things and `nil` for a
    # creature's. Nothing a creature holds is the character's to learn.
    class ItemFacts
      include JSON::Serializable

      getter kind : ItemKind
      getter count : Int32?
      getter enchantment : Int32?
      getter blessing : Blessing?
      getter condition : Condition?
      getter known : Known?

      def initialize(@kind : ItemKind, @count : Int32? = nil,
                     @enchantment : Int32? = nil, @blessing : Blessing? = nil,
                     @condition : Condition? = nil, @known : Known? = nil)
      end

      # *item* as it is now. *lore* is the character's, for one of their own
      # things, and `nil` for a creature's.
      def self.of(item : Item, lore : Lore?) : ItemFacts
        known = lore.try do |found|
          Known.new found.known?(item.kind), true, item.blessing_known?
        end

        new item.kind, item.count, item.enchantment, item.blessing,
          item.condition, known
      end
    end

    # What the events file adds to one event.
    #
    # Every field is optional, and each event sets the ones that fit it. A
    # field the event already has keeps the event's value. *attacker* is
    # added only where the event left it out, which is a shot from a creature
    # the character could not see. A missing *attacker* still means the
    # character, and *attacker_species* tells the two apart.
    class Facts
      include JSON::Serializable

      getter attacker : Int32?
      getter attacker_species : String?
      getter target_species : String?
      getter roll : Roll?
      getter weapon : ItemFacts?
      getter launcher : ItemFacts?
      getter left : Int32?
      getter level : Int32?
      getter hp : {Int32, Int32}?
      getter item_facts : ItemFacts?

      def initialize(*, @attacker : Int32? = nil,
                     @attacker_species : String? = nil,
                     @target_species : String? = nil, @roll : Roll? = nil,
                     @weapon : ItemFacts? = nil, @launcher : ItemFacts? = nil,
                     @left : Int32? = nil, @level : Int32? = nil,
                     @hp : {Int32, Int32}? = nil,
                     @item_facts : ItemFacts? = nil)
      end

      # The name the facts give *creature*, or `PLAYER` for `nil`.
      #
      # It is the kind spelled as its JSON spells it, such as
      # `goblin_warrior`.
      def self.species(creature : Monster?) : String
        creature ? creature.kind.to_s.underscore : PLAYER
      end
    end
  end
end
