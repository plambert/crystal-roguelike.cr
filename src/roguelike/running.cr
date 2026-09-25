module Roguelike
  # Why a walk or a rest stopped.
  #
  # A walk takes one step at a time in one direction, and each step is a whole
  # turn, so every other creature on the floor acts between one step and the
  # next. `Game#run` checks these after each step and stops on the first one
  # that holds.
  #
  # A rest takes one turn at a time and never moves. `Game#linger` checks the
  # same list, less the two reasons that are about the square stepped onto.
  enum Halt
    # The square ahead cannot be walked onto. A wall, a shut door, or a
    # creature standing in the way.
    Blocked

    # A creature is in sight that was not in sight at the step before.
    Creature

    # The character's hit points changed.
    Hurt

    # Something was written to the log during the step.
    Told

    # The character stepped onto a door.
    Doorway

    # The character stepped off a length of corridor onto a square with more
    # ways off it. A corridor reaching a junction and a corridor opening into
    # a room both do this. `Game#corridor?` says what counts as a corridor.
    Branch

    # The run ended. The character was killed, or took a staircase.
    Over

    # The walk went `Game::FURTHEST` squares without any of the others.
    Spent

    # The route ran out. The character is standing on the square they picked.
    # Only `Game#follow` answers this. A walk in a direction has no end to
    # reach.
    Arrived

    # The character's hit points are at their maximum. Only a rest answers
    # this, and it is what a rest is for.
    Healed

    # A creature the character can see is in sight. Only a rest answers this,
    # and only before its first turn. A creature that comes into sight during
    # a rest answers `Creature`.
    InSight
  end

  # What one walk did.
  record Running, steps : Int32, halt : Halt do
    # Whether the character moved at all.
    #
    # A walk that stops on its first square answers false. `Play` follows the
    # camera only when this is true.
    def moved? : Bool
      @steps > 0
    end
  end
end
