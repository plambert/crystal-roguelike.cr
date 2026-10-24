require "../../roguelike"

module Roguelike
  module Replay
    # What checking one replay found.
    record Report,
      path : Path,
      turn : Int32,
      acts : Int32,
      checks : Int32,
      trouble : String? = nil,
      pauses : Int32 = 0,
      resumes : Int32 = 0 do
      # Whether the replay played out the way it was recorded.
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
          io << "verified " << @acts << " actions and " << @checks
          io << " checkpoints"
          io << ", across " << @resumes << (@resumes == 1 ? " load" : " loads") if @resumes > 0
          io << ", to turn " << @turn
        end
      end
    end

    # Plays a replay again and compares it against the run it recorded.
    #
    # The run is rebuilt from the header, then every action is performed in
    # the order it was recorded. At each checkpoint the fingerprint of the
    # rebuilt run is compared against the one in the file. The first
    # difference stops the check, and the report names the turn it was found
    # on and the turn of the last checkpoint that agreed. The fault is
    # somewhere between those two.
    #
    # A pause and a resume are compared the way a checkpoint is. The run is
    # played straight through them, because the actions and the rolls are
    # the same whether or not the process stopped in between. A resume that
    # goes back past actions the save does not hold puts the run back to the
    # pause first. See `Replay::Bookmarks`.
    #
    # The character looks after each action, which is what `Ui::Play#refresh`
    # does and what `Replay::Log` does. What the character remembers is part
    # of the run, so a check that did not look would differ from the run it
    # is checking for a reason that is not in the run.
    class Verifier
      # A run at the state the recording began from.
      #
      # A header with the whole run in it is read straight back. Otherwise
      # the seed digs the floor, the header names the character and says what
      # they had been told, and the character looks once. That is an ordinary
      # run at the moment before its first action.
      def self.rebuild(header : Header) : Game
        run = header.run
        return Game.from_json run if run

        rebuild header.seed, header.generate?, header.player, header.log
      end

      # :ditto:
      def self.rebuild(seed : UInt64, generate : Bool, player : String,
                       log : Array(String)) : Game
        rng = Rng.new seed
        game = generate ? Game.dug(rng) : Game.start(rng)

        game.player.name = player
        game.log.replace log
        game.look
        game
      end

      # What checking the file at *path* found.
      #
      # *force* checks a replay recorded by a build whose draw sequences have
      # since moved. The check is then worth as much as the reason the streams
      # moved.
      def self.check(path : Path | String, force : Bool = false) : Report
        new(Reading.read(path), force).run
      rescue error : Error | JSON::Error | ::File::Error
        Report.new Path.new(path), 0, 0, 0, error.message || error.class.name
      end

      # The file being checked.
      getter reading : Reading

      # Whether a build whose draw sequences moved is checked anyway.
      getter? force : Bool

      # The turn of the last checkpoint that agreed.
      @agreed : Int32

      # How many actions have been performed.
      @acts : Int32 = 0

      # How many checkpoints have agreed.
      @checks : Int32 = 0

      # How many pauses and resumes have agreed.
      @pauses : Int32 = 0
      @resumes : Int32 = 0

      def initialize(@reading : Reading, @force : Bool = false)
        @agreed = @reading.header.turn
      end

      # Checks the file.
      def run : Report
        moved = Streams.apart @reading.header.streams
        unless moved.empty? || force?
          return failed "recorded by a build whose draw sequences differ " \
                        "here: #{moved.join ", "}. Pass --force to check it anyway"
        end

        game = Verifier.rebuild @reading.header
        cursor = PlaybackCursor.new @reading, game
        return failed started(game) if cursor.opening

        walked cursor
      end

      # Performs every record and compares the final footer.
      private def walked(cursor : PlaybackCursor) : Report
        while step = cursor.advance
          if failure = step.failure
            return failed trouble(failure, step.record, cursor.game)
          end

          case step.record
          in Act
            @acts += 1
          in Check
            @checks += 1
            @agreed = step.record.turn
          in Pause
            @pauses += 1
          in Resume
            @resumes += 1
          end
        end

        if failure = cursor.finish
          return failed trouble(failure, nil, cursor.game)
        end

        done cursor.game
      end

      # Why a rebuilt run does not start where the file says it does.
      private def started(game : Game) : String
        return "the run does not start from seed #{@reading.header.seed}" if @reading.header.run

        "the run does not start from seed #{@reading.header.seed}. A run " \
        "carried on from a save is recorded with its whole state, and this " \
        "file has none, so it was recorded by a build that digs a different " \
        "floor from that seed\n" \
        "  recorded #{@reading.header.state}\n" \
        "  found    #{game.fingerprint like: @reading.header.state}"
      end

      # Which turns a difference is somewhere inside.
      private def window : String
        " (after turn #{@agreed}, which agreed)"
      end

      # The line describing a playback failure.
      private def trouble(failure : PlaybackFailure, record : Record?,
                          game : Game) : String
        case failure.problem
        in .opening?
          started game
        in .over?
          "turn #{failure.turn}: the run was over before the action#{window}"
        in .refused?
          "turn #{failure.turn}: #{failure.expected} was refused#{window}"
        in .fingerprint?
          "turn #{failure.turn}: the run differs#{window}\n" \
          "  recorded #{failure.expected}\n" \
          "  found    #{failure.found}"
        in .saved?
          what = case record
                 in Pause           then "the save"
                 in Resume          then "the loaded run"
                 in Act, Check, nil then "the run"
                 end
          "turn #{failure.turn}: #{what} differs#{window}\n" \
          "  recorded #{failure.expected} on turn #{failure.expected_turn}\n" \
          "  found    #{failure.found} on turn #{failure.found_turn}"
        in .resume_missing?
          "turn #{failure.turn}: the file resumes from pause " \
          "#{failure.pause}, which it does not hold"
        in .footer_turn?
          "the run ended on turn #{failure.found_turn} and the file " \
          "says turn #{failure.expected_turn}#{window}"
        in .footer_fingerprint?
          "turn #{failure.turn}: the run ends differently#{window}\n" \
          "  recorded #{failure.expected}\n" \
          "  found    #{failure.found}"
        in .footer_outcome?
          "the run ended #{failure.found} and the file says #{failure.expected}"
        end
      end

      private def done(game : Game) : Report
        Report.new @reading.path, game.turn, @acts, @checks, nil, @pauses,
          @resumes
      end

      private def failed(trouble : String) : Report
        Report.new @reading.path, @agreed, @acts, @checks, trouble, @pauses,
          @resumes
      end
    end
  end
end
