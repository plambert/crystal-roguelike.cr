module Roguelike
  # Why a run stopped.
  #
  # A run takes one step at a time in one direction, and each step is a whole
  # turn, so every other creature on the floor acts between one step and the
  # next. `Game#run` checks these after each step and stops on the first one
  # that holds.
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

    # The run went `Game::FURTHEST` squares without any of the others.
    Spent
  end

  # What one run did.
  record Running, steps : Int32, halt : Halt do
    # Whether the character moved at all.
    #
    # A run that stops on its first square answers false. `Play` follows the
    # camera only when this is true.
    def moved? : Bool
      @steps > 0
    end
  end
end
