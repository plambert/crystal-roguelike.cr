module Roguelike
  # How well the character has made something out.
  #
  # Seeing a thing and knowing what it is are two different things. A spear
  # across a hall is a spear, and the character has to walk up to it before
  # they can see the notch in the blade or feel the curse on it. A creature
  # standing between the character and a torch is an outline, and the
  # character makes out how big it is and nothing else.
  #
  # This is a game rule rather than a drawing decision, which is why it lives
  # here rather than under `Ui`. How near somebody must be to read a label
  # decides what the readouts say, what a tooltip says and what a menu says,
  # and all three have to agree.
  #
  # The members run from least made out to most, so `#at_least` can take the
  # better of two looks.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Regard
    # Nothing at all. The character has never laid eyes on it.
    Nothing

    # A shape and no more: how big it is, and nothing else. This is what a
    # creature showing against light behind it gives.
    Shape

    # What sort of thing it is. A spear, a scroll, a potion. Not which spear,
    # not what is written on the scroll, not what is in the bottle.
    Kind

    # Everything about it. This is what standing over a thing gives.
    Everything

    # Whether anything at all was made out.
    def made_out? : Bool
      !nothing?
    end

    # This regard, or *other* when *other* made more out.
    #
    # A square looked at twice keeps the closer look. Walking away from a
    # spear the character has stood over does not turn a cursed -2 spear back
    # into a spear.
    def at_least(other : Regard) : Regard
      self > other ? self : other
    end
  end

  # The rules behind `Regard`.
  #
  # An enum body cannot hold these: a name with a number after it in one is a
  # member of the enum rather than a constant.
  module Regards
    # How near the character must be to make out everything about an item
    # lying on the floor.
    #
    # Eight squares. A torch throws light six squares, so a character
    # carrying one makes a thing out a step or two before they stand on it.
    # A lit room is wider than eight squares across, so the far side of one
    # still holds things the character can see and cannot name, which is the
    # point: a room should be worth walking into. Eight is also what a goblin
    # and an orc notice at, so a person reads a label at about the range they
    # are noticed at.
    READING = 8

    # What an item lying *apart* steps away is made out as.
    def self.of_item(apart : Int32) : Regard
      apart <= READING ? Regard::Everything : Regard::Kind
    end

    # :ditto:, for an item at *spot* looked at from *origin*.
    def self.of_item(origin : {Int32, Int32}, spot : {Int32, Int32}) : Regard
      of_item Route.apart(origin, spot)
    end
  end
end
