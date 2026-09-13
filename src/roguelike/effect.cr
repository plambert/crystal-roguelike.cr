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

    # Whether using this needs a square to aim at.
    def aimed? : Bool
      strike?
    end

    # Whether using this needs a carried item to work on.
    def chosen? : Bool
      identify?
    end
  end
end
