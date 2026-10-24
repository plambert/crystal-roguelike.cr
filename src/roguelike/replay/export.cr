require "../../roguelike"

module Roguelike
  module Replay
    # A recorded run written out as what the character saw and what they did.
    #
    # A policy learned from scratch sees a death long before it sees a
    # staircase, so it is warmed up on runs somebody else played. This is where those runs come from.
    #
    # The run is rebuilt from the header and every action is performed in the
    # order it was recorded, the way `Replay::Verifier` does it. Before each
    # action the observation and the legal actions are written down, which is
    # what the character knew when that action was chosen. The fingerprints
    # are compared as they go, so an export stops rather than writing pairs
    # from a run that no longer plays out the way it was recorded.
    #
    # A run carried on from a save is one run. A resume that goes back past
    # actions the save does not hold puts the run back to the pause, so the
    # turns of the pairs after it start again from the pause's turn. The
    # pairs before it are still decisions somebody made, and they stay.
    #
    # The file is JSON Lines. A header line says where it came from, a `pair`
    # line holds one decision, and a footer line says how the run ended.
    module Export
      # What version of this file this build writes.
      #
      # Format 2 adds `depth` to each observation. A format 1 file reads
      # the same way, with no depth.
      FORMAT = 2

      # What exporting one replay found.
      record Report,
        path : Path,
        turn : Int32,
        pairs : Int32,
        trouble : String? = nil do
        # Whether the whole run was written out.
        def ok? : Bool
          @trouble.nil?
        end

        # The line a person reads.
        def to_s(io : IO) : Nil
          io << @path << ": "
          trouble = @trouble

          if trouble
            io << trouble
          else
            io << "exported " << @pairs << " pairs, to turn " << @turn
          end
        end
      end

      # The header of an exported file.
      struct Opening
        include JSON::Serializable

        getter type : String = "export"

        getter format : Int32 = FORMAT

        # What the run was recorded by, and what is writing it out now.
        getter recorded_by : String

        getter exported_by : String

        getter seed : UInt64

        getter player : String

        # What wrote the replay this came from. `human` or `bot`.
        getter source : String

        # How many actions the replay holds.
        getter actions : Int32

        def initialize(@recorded_by : String, @exported_by : String,
                       @seed : UInt64, @player : String, @source : String,
                       @actions : Int32)
        end
      end

      # One decision, which is what the character knew and what they did.
      struct Pair
        include JSON::Serializable

        getter type : String = "pair"

        getter turn : Int32

        getter obs : Observation

        # Every action the game would have taken at this point.
        #
        # A policy learned from these needs it, because the loss is over the
        # actions that were open rather than over every action there is.
        # `--no-legal` leaves it out, and it is most of the size of a line.
        getter legal : Array(Action)?

        getter action : Action

        def initialize(@turn : Int32, @obs : Observation,
                       @legal : Array(Action)?, @action : Action)
        end
      end

      # The footer of an exported file.
      struct Closing
        include JSON::Serializable

        getter type : String = "footer"

        getter turn : Int32

        getter pairs : Int32

        # How the run ended, or `nil` for a file with no footer.
        getter outcome : String?

        def initialize(@turn : Int32, @pairs : Int32, @outcome : String?)
        end
      end

      # Writes the run in *source* to *to*. Answers what was written.
      #
      # *legal* writes the legal actions beside each observation. It is most
      # of the size of a line and a policy trained on these wants it.
      def self.run(source : Path | String, to : IO,
                   legal : Bool = true) : Report
        from = Path.new source
        read = Reading.read source
        game = Verifier.rebuild read.header
        cursor = PlaybackCursor.new read, game

        if cursor.opening
          return Report.new from, 0, 0,
            "the run does not start where it was recorded from. " \
            "Check it with replay verify."
        end

        written from, read, cursor, to, legal
      end

      # Writes every pair of *read*, performing each action as it goes.
      private def self.written(from : Path, read : Reading, cursor : PlaybackCursor,
                               to : IO, legal : Bool) : Report
        acts = read.records.count &.is_a?(Act)
        opening(read, acts).to_json to
        to << '\n'

        pairs = 0
        seen = cursor.look

        while line = cursor.next_record
          if act = line.as?(Act)
            game = cursor.game
            Pair.new(game.turn, Observation.of(game, seen),
              legal ? game.legal(seen) : nil, act.action).to_json to
            to << '\n'
            pairs += 1
          end

          step = cursor.advance
          break unless step
          if failure = step.failure
            return Report.new from, cursor.game.turn, pairs,
              trouble(failure, step.record)
          end

          seen = if step.record.is_a?(Resume)
                   cursor.look
                 else
                   cursor.seen || seen
                 end
        end

        if failure = cursor.finish
          return Report.new from, cursor.game.turn, pairs,
            trouble(failure, nil)
        end

        Closing.new(cursor.game.turn, pairs, read.footer.try &.outcome).to_json to
        to << '\n'

        Report.new from, cursor.game.turn, pairs
      end

      # The line describing a playback failure.
      private def self.trouble(failure : PlaybackFailure,
                               record : Record?) : String
        case failure.problem
        in .opening?
          "the run does not start where it was recorded from. Check it with replay verify."
        in .over?, .refused?
          "turn #{failure.turn}: #{failure.expected} was refused"
        in .fingerprint?
          "turn #{failure.turn}: the run differs from what was recorded. " \
          "Check it with replay verify."
        in .saved?
          if record.is_a?(Resume)
            "turn #{failure.turn}: the loaded run differs from what was " \
            "recorded. Check it with replay verify."
          else
            "turn #{failure.turn}: the run differs from what was recorded. " \
            "Check it with replay verify."
          end
        in .resume_missing?
          "turn #{failure.turn}: the file resumes from pause " \
          "#{failure.pause}, which it does not hold"
        in .footer_turn?
          "the run ends on turn #{failure.found_turn}, but the file says " \
          "turn #{failure.expected_turn}. Check it with replay verify."
        in .footer_fingerprint?
          "turn #{failure.turn}: the run ends differently from what was " \
          "recorded. Check it with replay verify."
        in .footer_outcome?
          "the run ended #{failure.found} and the file says " \
          "#{failure.expected}. Check it with replay verify."
        end
      end

      # The header line, which says where these pairs came from.
      private def self.opening(read : Reading, actions : Int32) : Opening
        Opening.new recorded_by: read.header.game_version,
          exported_by: "#{VERSION}+g#{BUILD}",
          seed: read.header.seed,
          player: read.header.player,
          source: read.header.source,
          actions: actions
      end
    end
  end
end
