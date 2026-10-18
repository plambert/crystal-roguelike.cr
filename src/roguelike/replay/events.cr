require "compress/gzip"
require "json"
require "../../roguelike"

module Roguelike
  class Game
    # Sends what this run emits to *log*, in place of the log
    # `Replay::Log.opened` would open on the next action.
    def record_into(log : Replay::Log) : Nil
      @recorder = log
      @recorded = true
    end
  end

  module Replay
    # Writes the events file the live game would have written while it
    # recorded a replay log.
    #
    # The run is rebuilt from the header, or loaded from a save, and every
    # action is performed in order, the way `Replay::Verifier` does it. The
    # rebuilt run is given a `Sink` as its log. `Game#perform` then hands
    # `Events::Writer` each event and each action at the moments the live
    # game did, so the lines come out the same.
    #
    # Pause, resume and footer lines in the log become the same lines in the
    # events file. A footer followed by a resume closes the file, and the
    # resume opens it again in append mode.
    #
    # A run that spans releases is written in parts. This stops at the first
    # resume written by another version and says which version and which turn.
    # The binary of that version carries the file on from a save of the run
    # with `from_save` and `from_turn`.
    module Backfill
      # The run went through.
      DONE = 0

      # The log does not read, or the events file will not open.
      BROKEN = 1

      # The rebuilt run differs from the one the log recorded.
      DIFFERS = 2

      # The log goes on in another version.
      ELSEWHERE = 3

      # What writing one events file found.
      #
      # *status* is the exit status. *message* is the line for standard
      # error, or `nil` when the run went through.
      record Report, status : Int32, message : String? = nil, acts : Int32 = 0,
        turn : Int32 = 0 do
        def ok? : Bool
          @status == DONE
        end
      end

      # The log the game hands its events to while the run is rebuilt.
      #
      # It writes no replay log. `#act` commits the action's lines to the
      # events file, which is all the live log does with them.
      class Sink < Log
        def initialize(@game : Game, @events : Events::Writer?)
          @path = Path[::File::NULL]
          @started_at = Time.utc
          @every = Int32::MAX
          @due = Int32::MAX
          @file = ::File.new ::File::NULL, "w"
        end

        def act(action : Action) : Nil
          @events.try &.commit(action)
        end

        # Closes the events file, with a footer when *footer* says so.
        def done(footer : Bool) : Nil
          @events.try &.close(footer)
          @events = nil
          @file.close
        end
      end

      # The events file for the replay log at *log*.
      #
      # The name is `Events::Writer.path_for` the log. A log named `.gz` is
      # named as the log it was packed from.
      def self.path_for(log : Path) : Path
        Events::Writer.path_for Path[log.to_s.rchop(".gz")]
      end

      # Whether *version* is this binary's version. The build after `+g` is
      # left out, since a binary built for a backfill has a commit of its own.
      def self.ours?(version : String) : Bool
        version.split("+g", 2).first == VERSION
      end

      # Writes the events file of the replay log at *log* to *target*.
      #
      # With *from_save*, the run is loaded from that save and carried on from
      # the first resume on turn *from_turn*. The file at *target* is appended
      # to, and its header is not written again.
      def self.run(log : Path, target : Path? = nil, from_save : Path? = nil,
                   from_turn : Int32? = nil) : Report
        reading = Reading.read log
        Run.new(log, reading, target || path_for(log)).run(from_save, from_turn)
      rescue error : Error | JSON::Error | ::File::Error | IO::Error
        Report.new BROKEN, "#{log}: #{error.message}"
      end

      # One events file being written.
      class Run
        @log : Path
        @reading : Reading
        @out : Path

        # What the writer is told the replay log is called. The writer names
        # its file from it.
        @stand_in : Path

        # Where the writer puts the file. It is moved to *out* at the end
        # when the two differ.
        @work : Path

        # The record indices a footer comes just before. The size of the
        # records is in it when the log ends with a footer.
        @footers : Set(Int32)

        @bookmarks : Bookmarks
        @id : String
        @sink : Sink? = nil
        @acts : Int32 = 0

        def initialize(@log : Path, @reading : Reading, @out : Path)
          @stand_in = Path["#{@out.to_s.rchop Events::Writer::SUFFIX}#{Naming::SUFFIX}"]
          @work = Events::Writer.path_for @stand_in
          @footers = Run.footers @log
          @bookmarks = Bookmarks.for @reading
          @id = Submit.log_id @reading.header
        end

        # Writes the file. See `Backfill.run`.
        def run(from_save : Path?, from_turn : Int32?) : Report
          ::File.rename @out, @work if from_save && @work != @out && ::File.exists?(@out)

          begin
            if from_save && from_turn
              resumed from_save, from_turn
            else
              started
            end
          ensure
            @sink.try &.done(false)
            ::File.rename @work, @out if @work != @out && ::File.exists?(@work)
          end
        end

        # Rebuilds the run from the header and plays every record.
        private def started : Report
          header = @reading.header
          return elsewhere(header.turn, header.game_version) unless Backfill.ours?(header.game_version)

          game = Verifier.rebuild header
          return differs(header.turn, "the run does not start where the log does") unless game.agrees?(header.state)

          attach game, Events::Writer.started(game, @stand_in, @id,
            header.game_version)
          walked game, 0
        end

        # Loads the run from *save* and plays the records after the first
        # resume on turn *turn*.
        private def resumed(save : Path, turn : Int32) : Report
          records = @reading.records
          at = records.index { |line| line.is_a?(Resume) && line.turn == turn && Backfill.ours?(line.game_version) }
          unless at
            foreign = records.find { |line| line.is_a?(Resume) && line.turn == turn }
            return elsewhere(turn, foreign.game_version) if foreign.is_a?(Resume)

            return Report.new BROKEN, "#{@log}: no resume on turn #{turn}"
          end

          resume = records[at].as(Resume)
          game = Run.loaded save
          game.look
          unless game.agrees?(resume.state) && game.turn == resume.turn
            return differs(turn, "the save differs from the resume")
          end

          records[0...at].each do |line|
            @bookmarks.paused line, game if line.is_a?(Pause) && line.pause == resume.pause
          end

          attach game, Events::Writer.resumed(game, @stand_in, @id,
            resume.pause, resume.game_version)
          walked game, at + 1
        end

        # Plays the records from *start* on.
        private def walked(game : Game, start : Int32) : Report
          records = @reading.records
          (start...records.size).each do |index|
            footer if @footers.includes? index

            case line = records[index]
            in Act
              return differs(line.turn, "the run was over before the action") if game.over?
              return differs(line.turn, "#{line.action.t} was refused") if game.perform(line.action).refused?

              @acts += 1
              game.look
            in Check
              return differs(line.turn, "the run differs") unless game.agrees?(line.state)
            in Pause
              return differs(line.turn, "the save differs") unless held?(game, line.turn, line.state)

              @bookmarks.paused line, game
              @sink.try &.events.try &.pause(line.pause)
            in Resume
              @sink.try &.done(false)
              @sink = nil
              return elsewhere(line.turn, line.game_version) unless Backfill.ours?(line.game_version)

              unless @bookmarks.seen? line
                return Report.new BROKEN, "#{@log}: turn #{line.turn}: the log resumes " \
                                          "from pause #{line.pause}, which it does not hold"
              end

              game = @bookmarks.resumed line, game
              return differs(line.turn, "the loaded run differs") unless held?(game, line.turn, line.state)

              attach game, Events::Writer.resumed(game, @stand_in, @id,
                line.pause, line.game_version)
            end
          end

          footer if @footers.includes?(records.size)
          Report.new DONE, acts: @acts, turn: game.turn
        end

        # Whether *game* is at *turn* with the fingerprint *state*.
        private def held?(game : Game, turn : Int32, state : String) : Bool
          game.turn == turn && game.agrees?(state)
        end

        # Hands *game* a sink for *writer*.
        private def attach(game : Game, writer : Events::Writer?) : Nil
          raise ::File::Error.new("the events file did not open", file: @work.to_s) unless writer

          sink = Sink.new game, writer
          game.record_into sink
          @sink = sink
        end

        # Writes a footer line and closes the file.
        private def footer : Nil
          @sink.try &.done(true)
          @sink = nil
        end

        private def differs(turn : Int32, what : String) : Report
          Report.new DIFFERS, "#{@log}: turn #{turn}: #{what}", @acts, turn
        end

        # The line the backfill reads to hand the rest of the log on.
        private def elsewhere(turn : Int32, version : String) : Report
          Report.new ELSEWHERE, "#{@log}: turn #{turn} goes on in version #{version}",
            @acts, turn
        end

        # The run in the save at *path*. A bare game is read as well as a
        # save with its header.
        def self.loaded(path : Path) : Game
          text = ::File.read path
          begin
            Save::Held.from_json(text).game
          rescue JSON::SerializableError
            Game.from_json text
          end
        end

        # Where the footers of the log at *log* fall, as the number of
        # records before each one.
        def self.footers(log : Path) : Set(Int32)
          found = Set(Int32).new
          count = 0
          lines(log).each do |line|
            kind = begin
              Reading::Kind.from_json(line).type
            rescue JSON::ParseException
              nil
            end

            case kind
            when "act", "check", "pause", "resume" then count += 1
            when "footer"                          then found << count
            end
          end
          found
        end

        # The lines of the file at *log*, unpacked when it is named `.gz`.
        private def self.lines(log : Path) : Array(String)
          return ::File.read_lines log unless log.extension == ".gz"

          ::File.open log do |file|
            Compress::Gzip::Reader.open(file, &.gets_to_end).lines
          end
        end
      end
    end
  end
end
