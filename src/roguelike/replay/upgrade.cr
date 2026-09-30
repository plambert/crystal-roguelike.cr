require "../../roguelike"

module Roguelike
  module Replay
    # A recorded run written out again, under this build's fingerprints.
    #
    # A format 1 file holds fingerprints taken with the message log in them,
    # and this build leaves the log out. So `Replay::Verifier` refuses one
    # and `Replay::Viewer` does not open one. The actions in such a file are
    # still good. This reads them, performs them again, and writes a format 2
    # file holding the same actions with the fingerprints this build takes.
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

        wanted = Path[::File.tempname "roguelike-upgrade", Naming::SUFFIX]
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

        read.records.each do |record|
          next unless record.is_a? Act
          next unless game.perform(record.action).refused?

          return "turn #{record.turn}: #{record.action.t} was refused"
        end

        nil
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
      def self.every_of(read : Reading) : Int32
        turns = read.records.compact_map { |record| record.as?(Check).try &.turn }
        return Log.every if turns.size < 2

        start = read.header.turn
        found = turns.each_with_index.min_of { |turn, index| (turn - start) // (index + 1) }
        found > 0 ? found : Log.every
      end
    end
  end
end
