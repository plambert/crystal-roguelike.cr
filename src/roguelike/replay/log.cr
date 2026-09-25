require "../version"
require "./lines"
require "./naming"
require "./streams"
require "./verifier"

module Roguelike
  module Replay
    # A run written down as it is played.
    #
    # The file is JSON Lines. A header, one `act` line per action, a `check`
    # line every so many turns, and a footer. Every line is flushed as it is
    # written, so a run that ends in a crash leaves a file that reads.
    #
    # `Game#perform` is the one thing that writes here. `.pattern` says where
    # the files go, and a run with no pattern set records nothing. The setting
    # is on the class because it comes from the command line and holds for
    # every run the process plays, including the second one somebody asks for
    # and the one a character carries on from a save.
    #
    # A log looks for the character before it takes a fingerprint. `Game#look`
    # is what puts what the character can see into what they remember, and
    # what they remember is part of the run. `Ui::Play` looks after every
    # action it performs. A driver that does not look would record a run whose
    # map never fills in, and `Replay::Verifier` would rebuild a different
    # one. Looking here makes the two agree whatever drives the game.
    class Log
      # How many turns there are between two checkpoints.
      EVERY = 25

      # Where the files go, or `nil` for a process recording nothing.
      class_property pattern : String? = nil

      # How many turns there are between two checkpoints.
      class_property every : Int32 = EVERY

      # What is being recorded. `human` for a person at the keyboard.
      class_property source : String = "human"

      # Whether the floor was dug from the seed. `--no-generate` clears it.
      class_property? generate : Bool = true

      # The logs of runs that have not ended.
      @@open = [] of Log

      # Whether the exit handler is installed.
      @@watching = false

      # A log for *game*, or `nil` when this process records nothing.
      #
      # A file that will not open stops the recording and not the run. The
      # reason goes to stderr, where it stays in the scrollback after the
      # terminal is handed back.
      def self.opened(game : Game) : Log?
        found = @@pattern
        return unless found

        watch
        new game, found
      rescue error : ::File::Error
        STDERR.puts "replay log: #{error.message}"
        nil
      end

      # Writes a footer to every log still open, and closes it.
      #
      # *error* is the exception the process is going out on, or `nil` for one
      # that is not. A run the game itself ended has already been closed, so
      # what is left here is a run that was still being played.
      def self.ended(error : Exception?) : Nil
        @@open.dup.each &.ended(error)
      end

      # Installs the exit handler, once.
      private def self.watch : Nil
        return if @@watching

        @@watching = true
        at_exit { |_status, error| ended error }
      end

      # The run being recorded.
      getter game : Game

      # The file being written.
      getter path : Path

      # When recording began.
      getter started_at : Time

      # The turn the next checkpoint is due on.
      @due : Int32

      @file : File

      def initialize(@game : Game, pattern : String)
        @started_at = Time.utc
        @path = Naming.resolve pattern, @game.player.name, @game.world.seed,
          @started_at
        @file = File.new @path, "w"
        @due = @game.turn + Log.every

        @game.look
        write header
        @@open << self
      end

      # Writes *action* down, and whatever follows it.
      #
      # The character looks before the fingerprint is taken, so a checkpoint
      # holds what they know as well as where they are.
      def act(action : Action) : Nil
        write Act.new @game.turn, action
        @game.look

        if @game.turn >= @due
          write Check.new @game.turn, @game.fingerprint
          while @due <= @game.turn
            @due += Log.every
          end
        end

        over if @game.over?
      end

      # Whether this log is still being written to.
      getter? open : Bool = true

      # Writes the footer of a run the game ended, and closes the file.
      private def over : Nil
        finish Footer.new @game.turn, Replay.word_for(@game.outcome),
          @game.outcome.to_s.downcase, Time.utc, @game.fingerprint
      end

      # Writes the footer of a run the process went out from under.
      #
      # It carries no fingerprint. The run did not reach a state anything
      # would compare it against, and a verifier reads this file up to the
      # last action and stops there.
      def ended(error : Exception?) : Nil
        return unless open?

        finish Footer.new @game.turn, error ? "crash" : "truncated",
          @game.outcome.to_s.downcase, Time.utc
      end

      # Writes *footer* and closes the file.
      private def finish(footer : Footer) : Nil
        write footer
        @file.close
        @open = false
        @@open.delete self
      end

      # The header, which says how the run this records began.
      private def header : Header
        state = @game.fingerprint

        Header.new game_version: "#{VERSION}+g#{BUILD}",
          crystal_version: Crystal::VERSION,
          seed: @game.world.seed,
          generate: Log.generate?,
          streams: Streams.current,
          player: @game.player.name,
          source: Log.source,
          started_at: @started_at,
          turn: @game.turn,
          log: @game.log.lines.dup,
          state: state,
          run: rebuilt?(state) ? nil : @game.to_json
      end

      # Whether the seed, the name and the log rebuild the run as it stands.
      #
      # They do for a run started fresh, which is every run a person plays
      # from the title screen. They do not for one a character carried on
      # from a save, and that run's whole state goes in the header instead.
      private def rebuilt?(state : String) : Bool
        Verifier.rebuild(@game.world.seed, Log.generate?, @game.player.name,
          @game.log.lines).fingerprint == state
      rescue
        false
      end

      # Writes one line and flushes it.
      private def write(line : Header | Act | Check | Footer) : Nil
        @file.puts line.to_json
        @file.flush
      end
    end
  end
end
