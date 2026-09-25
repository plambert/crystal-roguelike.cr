require "../game"
require "./reading"
require "./streams"

module Roguelike
  module Replay
    # What checking one replay found.
    record Report,
      path : Path,
      turn : Int32,
      acts : Int32,
      checks : Int32,
      trouble : String? = nil do
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
          io << " checkpoints, to turn " << @turn
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
        game.log.lines.clear
        log.each { |line| game.log.lines << line }
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
        return failed started(game) unless game.fingerprint == @reading.header.state

        walked game
      end

      # Performs every action and compares every checkpoint.
      private def walked(game : Game) : Report
        @reading.records.each do |line|
          case line
          in Act
            trouble = acted game, line
            return failed trouble if trouble
          in Check
            trouble = checked game, line
            return failed trouble if trouble
          end
        end

        ended game
      end

      # Performs one action. Answers what went wrong, or `nil`.
      private def acted(game : Game, act : Act) : String?
        return "turn #{act.turn}: the run was over before the action" if game.over?

        verdict = game.perform act.action
        return "turn #{act.turn}: #{act.action.t} was refused#{window}" if verdict.refused?

        @acts += 1
        game.look
        nil
      end

      # Compares one checkpoint. Answers what went wrong, or `nil`.
      private def checked(game : Game, check : Check) : String?
        found = game.fingerprint
        unless found == check.state
          return "turn #{check.turn}: the run differs#{window}\n" \
                 "  recorded #{check.state}\n" \
                 "  found    #{found}"
        end

        @checks += 1
        @agreed = check.turn
        nil
      end

      # Compares the footer, if there is one to compare.
      #
      # A footer the exit handler wrote carries no fingerprint, and it is not
      # compared. The process went away while the run was being played, and
      # the turn it says may be past the last action that reached the file.
      # Everything up to that action has been checked already.
      private def ended(game : Game) : Report
        footer = @reading.footer
        return done game unless footer

        state = footer.state
        return done game unless state

        unless game.turn == footer.turn
          return failed "the run ended on turn #{game.turn} and the file " \
                        "says turn #{footer.turn}#{window}"
        end

        unless state == game.fingerprint
          return failed "turn #{footer.turn}: the run ends differently#{window}\n" \
                        "  recorded #{state}\n" \
                        "  found    #{game.fingerprint}"
        end

        ending = game.outcome.to_s.downcase
        return failed "the run ended #{ending} and the file says #{footer.ending}" unless ending == footer.ending

        done game
      end

      # Why a rebuilt run does not start where the file says it does.
      private def started(game : Game) : String
        return "the run does not start from seed #{@reading.header.seed}" if @reading.header.run

        "the run does not start from seed #{@reading.header.seed}. A run " \
        "carried on from a save is recorded with its whole state, and this " \
        "file has none, so it was recorded by a build that digs a different " \
        "floor from that seed\n" \
        "  recorded #{@reading.header.state}\n" \
        "  found    #{game.fingerprint}"
      end

      # Which turns a difference is somewhere inside.
      private def window : String
        " (after turn #{@agreed}, which agreed)"
      end

      private def done(game : Game) : Report
        Report.new @reading.path, game.turn, @acts, @checks
      end

      private def failed(trouble : String) : Report
        Report.new @reading.path, @agreed, @acts, @checks, trouble
      end
    end
  end
end
