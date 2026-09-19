module Roguelike
  # How much attention an item has had, and when that is enough to tell a
  # blessing from a curse.
  #
  # Nothing here holds state and nothing here rolls. `Game` adds the gain
  # every turn and rolls against the numbers below.
  module Handling
    # What one turn in a slot is worth.
    #
    # A person notices the weight of what they are swinging or wearing far
    # sooner than they notice a thing at the bottom of the pack.
    WORN = 3

    # What one turn merely carried is worth.
    CARRIED = 1

    # The least handling at which anything is noticed.
    #
    # An item picked up and dropped again in the same room tells the
    # character nothing.
    LEAST = 10

    # The average handling at which it is noticed.
    #
    # The roll past `LEAST` is geometric, so the median is about 72 rather
    # than this. A worn item reaches this in about 34 turns and a carried one
    # in about 100.
    MEAN = 100

    # The chance in `SPAN` that this turn is the one, for a gain of one.
    #
    # The expected handling at the reveal is `LEAST` plus `SPAN`, which is
    # `MEAN`.
    SPAN = MEAN - LEAST
  end
end
