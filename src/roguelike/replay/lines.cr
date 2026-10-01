require "json"
require "../../roguelike"

module Roguelike
  module Replay
    # Which shape the lines of a file are in.
    #
    # A reader refuses a file whose number is not its own. A number is raised
    # when a field changes meaning or goes away. A field added beside the
    # ones already there does not raise it, because a reader of the older
    # shape ignores what it does not know.
    #
    # Format 2 is the first whose fingerprints leave the message log out. A
    # format 1 file holds fingerprints taken with the log in them, so every
    # checkpoint in one differs from what this build takes.
    #
    # Format 3 adds the `pause` and `resume` lines, which carry one run across
    # a save and a load. A reader of format 2 would pass over them, and a run
    # that went back to an earlier save would then play wrongly, so the
    # number is raised. A format 2 file has neither line and reads as it
    # always did.
    FORMAT = 3

    # The formats this build reads.
    READS = 2..FORMAT

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

      # How many turns there are between two checkpoints.
      #
      # A run carried on from a save keeps the spacing it began with. `nil` in
      # a file written before format 3.
      getter every : Int32?

      # The save this run was carried on from, when its own log was not found.
      #
      # `nil` for a run recorded from its start. A run carried on into the log
      # it began has a `resume` line instead.
      getter continued : Carried?

      def initialize(@game_version : String, @crystal_version : String,
                     @seed : UInt64, @generate : Bool,
                     @streams : Hash(String, Int32), @player : String,
                     @source : String, @started_at : Time, @turn : Int32,
                     @log : Array(String), @state : String,
                     @run : String? = nil, @every : Int32? = nil,
                     @continued : Carried? = nil)
      end
    end

    # Where a saved run's log is, and the pause the save was written at.
    #
    # `Save::Held` carries one. A save written before format 3, or by a
    # process recording nothing, carries none.
    class Mark
      include JSON::Serializable

      # The log file.
      getter log : String

      # The number of the `pause` line written with the save.
      getter pause : Int32

      def initialize(@log : String, @pause : Int32)
      end
    end

    # The save a run was carried on from.
    #
    # `Game#carried` holds one between the load and the first action, which
    # is when the log opens. A header holds one when the log the save named
    # could not be continued.
    class Carried
      include JSON::Serializable

      # The save file.
      getter save : String

      # When the save was written.
      getter saved_at : Time

      # The turn the save was written on.
      getter turn : Int32

      # The log the save named, or `nil` for a save that named none.
      getter log : String?

      # The pause the save was written at, or `nil`.
      getter pause : Int32?

      def initialize(@save : String, @saved_at : Time, @turn : Int32,
                     @log : String? = nil, @pause : Int32? = nil)
      end
    end

    # A save was written here.
    #
    # The run may go on in the same process, as it does after a staircase,
    # or the process may stop, as it does after a quit. Either way the save
    # holds the run as it stands at this line. `#pause` counts from one
    # within the file, and the save names it.
    class Pause
      include JSON::Serializable

      getter type : String = "pause"

      getter pause : Int32

      getter turn : Int32

      # The fingerprint of the run the save holds.
      getter state : String

      getter at : Time

      def initialize(@pause : Int32, @turn : Int32, @state : String,
                     @at : Time)
      end
    end

    # A save was loaded, and the run goes on from pause `#pause`.
    #
    # The actions after this line were played by the process that loaded the
    # save. When actions follow the pause in the file before this line, the
    # process that wrote them went away without saving, and the run goes back
    # to the state at the pause.
    #
    # `#state` is the fingerprint of the run as it was loaded. It differs from
    # the pause's when the save did not hold the whole run.
    class Resume
      include JSON::Serializable

      getter type : String = "resume"

      getter pause : Int32

      getter turn : Int32

      getter state : String

      getter at : Time

      # The build that carried the run on.
      getter game_version : String

      def initialize(@pause : Int32, @turn : Int32, @state : String,
                     @at : Time, @game_version : String)
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
    # `#outcome` is the word the recording format asks for. `#ending` is the
    # game's own `Outcome`, in lower case. The game has a third ending, which
    # is the character climbing back out, and the format has no word for it. Both are here so that neither reading is lost.
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

      # What stopped the process, for a footer the game did not write.
      # `signal` for one it was sent. `nil` otherwise.
      getter cause : String?

      def initialize(@turn : Int32, @outcome : String, @ending : String,
                     @ended_at : Time, @state : String? = nil,
                     @cause : String? = nil)
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
