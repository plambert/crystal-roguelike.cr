module Roguelike
  module Replay
    # Which draw sequence each part of the game is on.
    #
    # `Rng#derive` gives every part of the game a stream of its own. A change
    # to the order a part draws in changes what that seed produces there and
    # nowhere else. A replay recorded before the change no longer plays out
    # the same way.
    #
    # A header holds this table as it stood when the run was recorded.
    # `Replay::Verifier` compares it against the build it is running on and
    # names the parts that moved. A person then knows the replay is stale
    # rather than the run being wrong.
    #
    # Raise a number by hand when a change moves that part's draws. Adding a
    # draw, taking one out and reordering two all count. Changing a number
    # the draw is compared against does not: that is a rule change, and
    # `Roguelike::VERSION` is what says a rule changed.
    module Streams
      # Each part of the game and the version of its draw sequence.
      #
      # `generator` covers the rooms, the cuts between them, the corridors,
      # the doors, the sconces, the creatures and the staircases. Those are
      # separate streams and one algorithm. `lore` is the appearances a run
      # rolls for its potions, its scrolls and its wands. `combat`,
      # `handling`, `use` and `wander` are the four counters on the run.
      #
      # The stream the name suggestion draws from is not here. It names
      # nobody and nothing in the run.
      VERSIONS = {
        "generator"  => 1,
        "litter"     => 1,
        "loot"       => 1,
        "ammunition" => 1,
        "lore"       => 1,
        "combat"     => 1,
        "handling"   => 1,
        "use"        => 1,
        "wander"     => 1,
      }

      # This build's table, as a header holds it.
      def self.current : Hash(String, Int32)
        VERSIONS.dup
      end

      # The parts whose version in *recorded* differs from this build's.
      #
      # A part in one table and not the other is named too. Adding a part and
      # taking one out both change what a seed produces.
      def self.apart(recorded : Hash(String, Int32)) : Array(String)
        names = (recorded.keys + VERSIONS.keys).uniq!.sort!
        names.reject { |name| recorded[name]? == VERSIONS[name]? }
      end
    end
  end
end
