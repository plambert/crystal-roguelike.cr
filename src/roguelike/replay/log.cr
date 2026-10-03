require "../../roguelike"

module Roguelike
  module Replay
    # A run written down as it is played.
    #
    # The file is JSON Lines. A header, one `act` line per action, a `check`
    # line every so many turns, a `pause` line at every save, and a footer.
    # Every line is flushed as it is written, so a run that ends in a crash
    # leaves a file that reads.
    #
    # A run carried on from a save goes on in the file it began in. The save
    # names the file and the pause, and the first action after the load
    # writes a `resume` line there. When that file is gone the run starts a
    # file of its own, whose header names the save.
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

      # Where every run goes when `--replay-log` names nowhere, or `nil`.
      #
      # A test build sets it to `.test_logs` as it starts. Nothing else does,
      # so an ordinary build records only what `--replay-log` asks for.
      class_property always : Path? = nil

      # What the test logs directory is called under the game's own.
      TEST_LOGS = "test_logs"

      # Where a test build writes its logs.
      #
      # Beside the saves, under the XDG state directory. See
      # `Save::Store.default`.
      def self.test_logs : Path
        Path[Save.state_home] / "roguelike" / TEST_LOGS
      end

      # The pattern a run records to, given what `--replay-log` said.
      #
      # `--replay-log` wins. Without it a test build writes to `.always`, and
      # the directory is made so that `Naming` names a file inside it.
      def self.pattern_for(given : String?) : String?
        return given if given

        found = @@always
        return unless found

        Dir.mkdir_p found
        found.to_s
      rescue error : ::File::Error
        STDERR.puts "replay log: #{error.message}"
        nil
      end

      # How many turns there are between two checkpoints.
      class_property every : Int32 = EVERY

      # What is being recorded. `human` for a person at the keyboard.
      class_property source : String = "human"

      # When a log says recording began, or `nil` for the moment it opens.
      #
      # `Replay::Upgrade` sets it, so a run written out again carries the
      # time it was played rather than the time it was written out.
      class_property started_at : Time? = nil

      # When a log says recording stopped, or `nil` for the moment it does.
      #
      # `Replay::Upgrade` sets it, for the reason `.started_at` is set.
      class_property ended_at : Time? = nil

      # When the next pause says the save was written, or `nil` for now.
      class_property paused_at : Time? = nil

      # When the next resume says the save was loaded, or `nil` for now.
      class_property resumed_at : Time? = nil

      # Whether the floor was dug from the seed. `--no-generate` clears it.
      class_property? generate : Bool = true

      # The logs of runs that have not ended.
      @@open = [] of Log

      # Whether the exit handler is installed.
      @@watching = false

      # A log for *game*, or `nil` when this process records nothing.
      #
      # A run carried on from a save goes on in the log the save names, when
      # that log is there and is this run's. Otherwise it starts a log of its
      # own, and the header says which save it came from.
      #
      # A file that will not open stops the recording and not the run. The
      # reason goes to stderr, where it stays in the scrollback after the
      # terminal is handed back.
      def self.opened(game : Game) : Log?
        found = @@pattern
        return unless found

        watch
        carried = game.carried
        continued = carried.try { |from| continuing game, from }
        return new(game, continued, carried.try(&.pause) || 0) if continued

        new game, found, carried
      rescue error : ::File::Error
        STDERR.puts "replay log: #{error.message}"
        nil
      end

      # The log *game* goes on in, or `nil` for one it cannot.
      #
      # The save names a file. A file moved along with the state directory is
      # looked for by its name in `.always` as well. It has to start with this
      # run's seed and character and hold the pause the save names.
      private def self.continuing(game : Game, carried : Carried) : Path?
        named = carried.log
        pause = carried.pause
        return unless named && pause

        where = [Path[named]]
        @@always.try { |dir| where << dir / Path[named].basename }
        where.find do |path|
          next false unless ::File.exists? path

          read = Reading.read path, fingerprints: false
          read.header.seed == game.world.seed &&
            read.header.player == game.player.name &&
            read.records.any? { |line| line.as?(Pause).try(&.pause) == pause }
        rescue Error | JSON::Error | ::File::Error
          false
        end
      end

      # Writes a footer to every log that has actions since its last pause,
      # and closes each one.
      #
      # `Session` runs this as a signal stops the process. The process dies
      # of the signal straight after, and `at_exit` handlers do not run, so
      # this is the only footer such a run gets.
      def self.signalled : Nil
        @@open.dup.each &.ended(nil, "signal")
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

      # How many turns there are between two checkpoints in this file.
      @every : Int32

      # How many pauses the file holds.
      getter pauses : Int32 = 0

      # Whether an action has been written since the last pause.
      #
      # A log closed with nothing since its last pause is paused rather than
      # cut off, and it gets no footer.
      @acted : Bool = false

      @file : File

      # A new file for *game*, named from *pattern*.
      #
      # *carried* is the save the run was loaded from, when the log that save
      # names could not be continued. The header says so.
      def initialize(@game : Game, pattern : String, carried : Carried? = nil)
        @started_at = Log.started_at || Time.utc
        @path = Naming.resolve pattern, @game.player.name, @game.world.seed,
          @started_at
        @file = File.new @path, "w"
        @every = Log.every
        @due = @game.turn + @every

        @game.look
        write header(carried)
        @@open << self
      end

      # The file at *path* again, carrying the run on from *pause*.
      #
      # The checkpoints keep the turns they were due on. The *k*th lands on
      # the first action at or past *k* times the spacing after the turn the
      # file began on, whichever process wrote it.
      def initialize(@game : Game, @path : Path, pause : Int32)
        read = Reading.read @path, fingerprints: false
        @started_at = read.header.started_at
        @every = read.header.every || Log.every
        @pauses = read.pauses
        @due = read.header.turn + @every
        while @due <= @game.turn
          @due += @every
        end

        Log.trimmed @path
        @file = File.new @path, "a"

        @game.look
        write Resume.new pause, @game.turn, @game.fingerprint,
          Log.resumed_at || Time.utc, "#{VERSION}+g#{BUILD}"
        @@open << self
      end

      # Cuts off a last line that was not written whole.
      #
      # A process killed part way through a write leaves one. A line written
      # after it would join it, and the file would no longer read.
      protected def self.trimmed(path : Path) : Nil
        ::File.open path, "r+" do |file|
          size = file.size
          return if size.zero?

          file.seek size - 1
          return if file.read_byte == '\n'.ord

          file.rewind
          whole = file.gets_to_end.rindex('\n').try(&.+ 1) || 0
          file.truncate whole
        end
      end

      # Writes *action* down, and whatever follows it.
      #
      # The character looks before the fingerprint is taken, so a checkpoint
      # holds what they know as well as where they are.
      def act(action : Action) : Nil
        write Act.new @game.turn, action
        @acted = true
        @game.look

        if @game.turn >= @due
          write Check.new @game.turn, @game.fingerprint
          while @due <= @game.turn
            @due += @every
          end
        end

        over if @game.over?
      end

      # Writes a pause, as a save of the run is about to be written. Answers
      # what the save names, or `nil` for a log that is closed.
      def pause : Mark?
        return unless open?

        @pauses += 1
        write Pause.new @pauses, @game.turn, @game.fingerprint,
          Log.paused_at || Time.utc
        @acted = false
        Mark.new @path.to_s, @pauses
      end

      # Whether this log is still being written to.
      getter? open : Bool = true

      # Writes the footer of a run the game ended, and closes the file.
      private def over : Nil
        finish Footer.new @game.turn, Replay.word_for(@game.outcome),
          @game.outcome.to_s.downcase, Log.ended_at || Time.utc,
          @game.fingerprint
      end

      # Writes the footer of a run the process went out from under.
      #
      # It carries no fingerprint. The run did not reach a state anything
      # would compare it against, and a verifier reads this file up to the
      # last action and stops there.
      #
      # A log with nothing written since its last pause gets no footer. The
      # save holds the run, and a later process carries it on here. An error
      # still gets one, because the crash is worth knowing about.
      #
      # *cause* is `signal` for a process stopped by one.
      def ended(error : Exception?, cause : String? = nil) : Nil
        return unless open?
        return finish nil if @pauses > 0 && !@acted && error.nil?

        finish Footer.new @game.turn, error ? "crash" : "truncated",
          @game.outcome.to_s.downcase, Log.ended_at || Time.utc, cause: cause
      end

      # Writes *footer*, when there is one, and closes the file.
      #
      # A file closed with a footer is offered for sending. One closed
      # without, which is a run paused at a save, was offered with the save.
      private def finish(footer : Footer?) : Nil
        write footer if footer
        @file.close
        @open = false
        @@open.delete self

        Submit.closed @game, @path, @pauses if footer
      end

      # The header, which says how the run this records began.
      private def header(carried : Carried?) : Header
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
          run: rebuilt?(state) ? nil : @game.to_json,
          every: @every,
          continued: carried
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
      private def write(line : Header | Act | Check | Pause | Resume | Footer) : Nil
        @file.puts line.to_json
        @file.flush
      end
    end
  end
end
