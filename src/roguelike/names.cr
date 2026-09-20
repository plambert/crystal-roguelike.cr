require "./rng"
require "./save"

module Roguelike
  # Names to offer somebody who has not thought of one.
  #
  # The question at the start of a run comes with a name already on the line.
  # A person who has one of their own types over it. A person who has not
  # presses `Enter`.
  #
  # Everything here rolls on an `Rng`, so `--seed N` twice offers the same
  # name twice.
  module Names
    # What a syllable starts with.
    STARTS = %w[b br c ch d dr f g gr h j k kr l m n p r s sh sk st t th tr
      v w z]

    # What it turns on.
    #
    # Vowels only. A group ending in a consonant, like "ar", piles up against
    # an ending like "ld" and makes a name nobody can say.
    VOWELS = %w[a e i o u ae ai ea ei ia io ou]

    # What the name ends with.
    ENDS = %w[n r l s th ck rn ld st m nd rk ss ll x]

    # How many names `.free` tries before it gives up and offers a taken one.
    TRIES = 20

    # The shortest name worth offering.
    #
    # Three letters comes out as an English word about as often as not, and
    # being offered "Lol" is not the start anybody wants.
    LEAST = 4

    # One name, rolled on *rng*.
    #
    # One syllable or two, and then an ending. That is three letters at the
    # short end and nine at the long one, which fits the status panel without
    # being cut.
    def self.roll(rng : Rng) : String
      made = one rng
      while made.size < LEAST
        made = one rng
      end

      made
    end

    # One roll, whatever it comes out as.
    private def self.one(rng : Rng) : String
      syllables = 1 + rng.rand(2)

      made = String.build do |line|
        syllables.times do
          line << STARTS[rng.rand STARTS.size]
          line << VOWELS[rng.rand VOWELS.size]
        end

        line << ENDS[rng.rand ENDS.size]
      end

      made.capitalize
    end

    # A name *store* has nobody saved under, rolled on *rng*.
    #
    # Offering a name already taken would have the question refuse its own
    # suggestion. With no store, or with every roll taken, the last roll is
    # offered anyway and the question says what is wrong with it.
    def self.free(rng : Rng, store : Save::Store? = nil) : String
      found = roll rng
      return found unless store

      TRIES.times do
        return found unless store.holds? found

        found = roll rng
      end

      found
    end
  end
end
