require "json"
require "../action"

module Roguelike
  module Replay
    # Which shape the lines of a file are in.
    #
    # A reader refuses a file whose number is above its own. A number is
    # raised when a field changes meaning or goes away. A field added beside
    # the ones already there does not raise it, because a reader of the older
    # shape ignores what it does not know.
    FORMAT = 1

    # What a run was written down with, and where it started.
    #
    # The first line of the file. `#state` is the fingerprint of the run just
    # before the first action, and it is what `Replay::Verifier` rebuilds and
    # compares against.
    #
    # `#seed`, `#player` and `#log` are what the rebuild takes. A run dug from
    # a seed and then named is the whole of an ordinary run's start. `#run`
    # carries the state itself for a run that started some other way, which a
    # character carried on from a save did.
    class Header
      include JSON::Serializable

      getter type : String = "header"

      getter format : Int32 = FORMAT

      # The game this was recorded by, with the commit it was built from.
      getter game_version : String

      # The compiler that built it. A stdlib draw can move between releases.
      getter crystal_version : String

      # The seed the run was dug from.
      getter seed : UInt64

      # Whether the floor was dug from the seed. False for the floor that
      # ships with the game, which `--no-generate` plays.
      getter? generate : Bool

      # The draw sequence each part of the game was on. See `Streams`.
      getter streams : Hash(String, Int32)

      # The character's name, as they typed it.
      getter player : String

      # What wrote the file. `human` for a person at the keyboard.
      getter source : String

      # When recording began.
      getter started_at : Time

      # The turn recording began on. Zero for a run recorded from its start.
      getter turn : Int32

      # What the character had been told when recording began.
      #
      # The log is part of the run and so part of the fingerprint. A run
      # writes two lines before the first turn and one more when the
      # character is named.
      getter log : Array(String)

      # The fingerprint of the run just before the first action.
      getter state : String

      # The whole run at that point, for one the seed does not rebuild.
      #
      # `nil` for an ordinary run, which is every run started fresh. A
      # character carried on from a save has one here, because the state they
      # carried on from is not a function of the seed.
      getter run : String?

      def initialize(@game_version : String, @crystal_version : String,
                     @seed : UInt64, @generate : Bool,
                     @streams : Hash(String, Int32), @player : String,
                     @source : String, @started_at : Time, @turn : Int32,
                     @log : Array(String), @state : String,
                     @run : String? = nil)
      end
    end

    # One action the character took.
    #
    # One line per action `Game#perform` allowed. `#turn` is the turn the run
    # had reached when the action was over. It is for reading and for saying
    # where a mismatch is. Playback follows the order of the lines.
    class Act
      include JSON::Serializable

      getter type : String = "act"

      getter turn : Int32

      getter action : Action

      def initialize(@turn : Int32, @action : Action)
      end
    end

    # The fingerprint of the run, every so many turns.
    #
    # Two runs that agree here and differ at the next one differ somewhere in
    # between. That is a smaller thing to search than a whole run.
    class Check
      include JSON::Serializable

      getter type : String = "check"

      getter turn : Int32

      getter state : String

      def initialize(@turn : Int32, @state : String)
      end
    end

    # How the run ended.
    #
    # `#outcome` is the word `bots/PROTOCOL.md` section 3.1 asks for.
    # `#ending` is the game's own `Outcome`, in lower case. The game has a
    # third ending, which is the character climbing back out, and the spec has
    # no word for it. Both are here so that neither reading is lost.
    #
    # `#state` is the fingerprint the run ended on. It is `nil` on a footer
    # written by the exit handler, because that footer is written after the
    # last action rather than at it.
    class Footer
      include JSON::Serializable

      getter type : String = "footer"

      getter turn : Int32

      getter outcome : String

      getter ending : String

      getter state : String?

      getter ended_at : Time

      def initialize(@turn : Int32, @outcome : String, @ending : String,
                     @ended_at : Time, @state : String? = nil)
      end
    end

    # What the footer says about a run the game itself ended.
    #
    # `Playing` is a run the recording stopped in the middle of. The process
    # went away while the character was still alive.
    def self.word_for(outcome : Outcome) : String
      case outcome
      in .won?     then "win"
      in .died?    then "death"
      in .left?    then "quit"
      in .playing? then "truncated"
      end
    end
  end
end
