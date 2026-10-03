require "../../roguelike"

module Roguelike
  module Replay
    # A recorded run written out again, under this build's fingerprints.
    #
    # A format 1 file holds fingerprints taken with the message log in them,
    # and this build leaves the log out. So `Replay::Verifier` refuses one
    # and `Replay::Viewer` does not open one. The actions in such a file are
    # still good. This reads them, performs them again, and writes a file in
    # this build's format holding the same actions with the fingerprints this
    # build takes. The pauses and the resumes of a run carried on across a
    # save are written again where they stood.
    #
    # The seed, the character, what wrote the file and the time the run
    # started all carry over, so the new file is the same run.
    #
    # What is lost is the check. The new file records what this build does
    # with those actions. A later build that does something else with them is
    # reported against this one, and a difference between this build and the
    # build that first recorded the run is gone.
    module Upgrade
      # Writes the run in *source* to *target*, under this build's
      # fingerprints. Answers what the new file holds.
      #
      # A refused action stops the work and the report names the turn.
      # *target* is left alone in that case, because the run is written to a
      # file of its own and moved into place once it is whole.
      def self.run(source : Path | String, target : Path | String) : Report
        to = Path.new target
        read = Reading.read source, fingerprints: false

        # Beside the target, not in the temporary directory: a rename cannot
        # cross from one drive or filesystem to another, and on Windows the
        # temporary directory is often on a different drive from the run.
        wanted = Path[::File.tempname "roguelike-upgrade", Naming::SUFFIX, dir: (to.parent.to_s.presence || ".")]
        trouble = written read, wanted

        if trouble
          ::File.delete? wanted
          return Report.new to, 0, 0, 0, trouble
        end

        ::File.rename wanted, to
        Verifier.check to
      end

      # Performs every action of *read* into a log at *where*.
      #
      # Answers what went wrong, or `nil`. The settings on `Replay::Log` hold
      # for every run the process plays, so they are read first and put back
      # however this ends.
      private def self.written(read : Reading, where : Path) : String?
        held = {
          pattern:    Log.pattern,
          every:      Log.every,
          generate:   Log.generate?,
          source:     Log.source,
          started_at: Log.started_at,
          ended_at:   Log.ended_at,
          paused_at:  Log.paused_at,
          resumed_at: Log.resumed_at,
        }

        begin
          played read, where
        ensure
          Log.ended nil
          Log.pattern = held[:pattern]
          Log.every = held[:every]
          Log.generate = held[:generate]
          Log.source = held[:source]
          Log.started_at = held[:started_at]
          Log.ended_at = held[:ended_at]
          Log.paused_at = held[:paused_at]
          Log.resumed_at = held[:resumed_at]
        end
      end

      # :ditto:
      private def self.played(read : Reading, where : Path) : String?
        header = read.header

        Log.pattern = where.to_s
        Log.every = every_of read
        Log.generate = header.generate?
        Log.source = header.source
        Log.started_at = header.started_at
        Log.ended_at = read.footer.try &.ended_at

        game = Verifier.rebuild header
        bookmarks = Bookmarks.for read

        read.records.each do |record|
          case record
          in Act
            next unless game.perform(record.action).refused?

            return "turn #{record.turn}: #{record.action.t} was refused"
          in Check
            next
          in Pause
            Log.paused_at = record.at
            game.pause
            bookmarks.paused record, game
          in Resume
            return "turn #{record.turn}: the file resumes from a pause it does not hold" unless bookmarks.seen? record

            game = resumed record, game, bookmarks, where
          end
        end

        nil
      end

      # The run *resume* carries on, with its log closed and opened again.
      #
      # That is what a process that stops and one that loads the save do. The
      # log written so far gets a footer when actions follow its last pause,
      # and the next action writes the resume line.
      private def self.resumed(resume : Resume, game : Game,
                               bookmarks : Bookmarks, where : Path) : Game
        Log.ended nil
        game = bookmarks.resumed resume, game
        game.carry_on Carried.new(where.to_s, resume.at, resume.turn,
          where.to_s, resume.pause)
        Log.resumed_at = resume.at
        game
      end

      # How many turns there were between two checkpoints in *read*.
      #
      # `--replay-every` sets it, so a file recorded with something other
      # than the default keeps the spacing it was recorded with and its
      # checkpoints land on the turns they landed on before.
      #
      # The *k*th checkpoint is written on the first action at or after
      # *k* times the spacing past the turn the file starts on. An action of
      # several turns can run past that turn, so a checkpoint lands late and
      # never early. The spacing is then the smallest of each checkpoint's
      # distance from the start divided by its count. A file with fewer than
      # two checkpoints says nothing about it, and the setting in force is
      # used.
      #
      # A file says how far apart its checkpoints are in its header from
      # format 3 on. Before that only the checkpoints before the first resume
      # are read, because a resume that goes back past actions starts the
      # turns again.
      def self.every_of(read : Reading) : Int32
        read.header.every.try { |found| return found }

        first = read.records.take_while { |record| !record.is_a?(Resume) }
        turns = first.compact_map { |record| record.as?(Check).try &.turn }
        return Log.every if turns.size < 2

        start = read.header.turn
        found = turns.each_with_index.min_of { |turn, index| (turn - start) // (index + 1) }
        found > 0 ? found : Log.every
      end
    end
  end
end
