require "./item"

module Roguelike
  # Where one thing a character has readied is held.
  #
  # Three slots are weapons and five are armour. `ArmourSlot` names the five
  # on its own, because `ItemFacts#slot` says where a piece of armour is worn
  # and nothing but armour is worn anywhere.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  #
  # The order is the order a readout writes them. The weapon comes first
  # because it is the one a person checks every turn.
  enum Slot
    # What the character swings.
    Melee

    # What the character shoots with.
    Ranged

    # What the character shoots.
    Quiver

    Head
    Body
    Hands
    Feet
    Shield

    # What the slot is called, for a readout.
    def label : String
      case self
      in .melee?  then "weapon"
      in .ranged? then "ranged weapon"
      in .quiver? then "quiver"
      in .head?   then "head"
      in .body?   then "body"
      in .hands?  then "hands"
      in .feet?   then "feet"
      in .shield? then "shield"
      end
    end

    # What the inventory writes beside an item held here.
    #
    # NetHack's wording. A person reading the list has to see which sword is
    # in their hand.
    def note : String
      case self
      in .melee?  then "weapon in hand"
      in .ranged? then "ranged weapon in hand"
      in .quiver? then "in quiver"
      in .head?   then "being worn"
      in .body?   then "being worn"
      in .hands?  then "being worn"
      in .feet?   then "being worn"
      in .shield? then "being worn"
      end
    end

    # What is said when *name* goes into this slot.
    #
    # A sword is held, a helmet is worn, and arrows go in the quiver. One
    # sentence for all three would say arrows are held, which would send a
    # reader looking for them in their hand.
    def readied(name : String) : String
      case self
      in .quiver?                                  then "You put #{name} in your quiver."
      in .melee?, .ranged?                         then "You are now holding #{name}."
      in .head?, .body?, .hands?, .feet?, .shield? then "You are now wearing #{name}."
      end
    end

    # What is said when *name* comes out of this slot.
    def released(name : String) : String
      case self
      in .quiver?                                  then "You take #{name} out of your quiver."
      in .melee?, .ranged?                         then "You are no longer holding #{name}."
      in .head?, .body?, .hands?, .feet?, .shield? then "You are no longer wearing #{name}."
      end
    end

    # What is said when somebody empties this slot and it is already empty.
    #
    # `Game#cannot_fire` says the same thing about an empty quiver.
    def vacant : String
      case self
      in .melee?                                   then "You are not holding a weapon."
      in .ranged?                                  then "You are not holding a ranged weapon."
      in .quiver?                                  then "Your quiver is empty."
      in .head?, .body?, .hands?, .feet?, .shield? then "You have nothing on your #{label}."
      end
    end

    # Whether this slot holds a weapon rather than armour.
    def weapon? : Bool
      melee? || ranged? || quiver?
    end

    # Whether this slot holds armour.
    def armour? : Bool
      !weapon?
    end

    # Which piece of armour goes here. `nil` for a weapon slot.
    def armour_slot : ArmourSlot?
      case self
      in .head?                      then ArmourSlot::Head
      in .body?                      then ArmourSlot::Body
      in .hands?                     then ArmourSlot::Hands
      in .feet?                      then ArmourSlot::Feet
      in .shield?                    then ArmourSlot::Shield
      in .melee?, .ranged?, .quiver? then nil
      end
    end

    # Whether *item* can go here.
    def accepts?(item : Item) : Bool
      wanted = Slot.for item
      return false unless wanted

      wanted == self
    end

    # Where *item* goes when the character readies it.
    #
    # One key readies anything. A sword goes in the hand, a bow goes in the
    # other hand, and arrows go in the quiver. A person should not have to
    # remember which key each of those takes.
    #
    # Answers `nil` for anything that is not readied at all. A potion is
    # drunk rather than held.
    def self.for(item : Item) : Slot?
      case item.kind.item_class
      when .melee?, .thrown? then Melee
      when .ranged_weapon?   then Ranged
      when .ammunition?      then Quiver
      when .armour?          then item.kind.slot.try { |worn| Slot.for worn }
      else                        nil
      end
    end

    # The slot a piece of armour worn at *slot* goes in.
    def self.for(slot : ArmourSlot) : Slot
      case slot
      in .head?   then Head
      in .body?   then Body
      in .hands?  then Hands
      in .feet?   then Feet
      in .shield? then Shield
      end
    end

    # Every weapon slot, in order.
    def self.weapons : Array(Slot)
      values.select &.weapon?
    end

    # Every armour slot, in order.
    def self.armours : Array(Slot)
      values.select &.armour?
    end
  end
end
