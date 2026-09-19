module Roguelike
  # What using an item does.
  #
  # Nothing in the model holds a block. An item names its effect and `Game`
  # looks the name up. That is what lets an item go into a save file, and it
  # is the same rule a monster's attack pattern and a trap's trigger follow.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Effect
    # Nothing at all. What most items do when they are used.
    None

    # Puts hit points back.
    Heal

    # Names one carried kind the character has not found out.
    Identify

    # Writes the shape of the whole floor into what the character remembers.
    MapFloor

    # Makes the squares round the character glow for good.
    Light

    # Hits whatever it is aimed at.
    Strike

    # Blesses one carried item, or everything within reach.
    Bless

    # Takes a curse off one carried item, or off everything within reach.
    RemoveCurse

    # Whether using this needs a square to aim at.
    def aimed? : Bool
      strike?
    end

    # Whether using this may need a carried item to work on.
    #
    # Whether it does is not settled here. A blessed scroll of blessing
    # reaches everything and asks nothing, and a cursed one picks its own
    # target. `Game#choice_needed?` reads the item as well as the effect.
    def chosen? : Bool
      identify? || bless? || remove_curse?
    end

    # Whether the character has to see what they are choosing between before
    # they choose.
    #
    # A scroll of blessing marks what it finds first. The marks are half of
    # what the scroll does, and choosing without them is choosing blind. A
    # scroll of identify names one kind and needs nothing shown first.
    def marks? : Bool
      bless? || remove_curse?
    end
  end
end
