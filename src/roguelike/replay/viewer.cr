require "../game"
require "./reading"
require "./streams"
require "./verifier"

module Roguelike
  module Replay
    # A recorded run, played back for somebody watching it.
    #
    # `Replay::Verifier` plays a file from one end to the other and answers
    # whether it matched. This plays the same file one action at a time, and
    # it goes backwards as well as forwards. It owns no terminal and no
    # widget. `Ui::Play` draws the game it holds.
    #
    # The snapshots are what make going backwards quick. A run of five
    # thousand actions takes about six seconds to play from its start, and
    # that is too slow to step back through. Every `EVERY` actions the whole
    # run is written to a file, and a jump backwards reads the nearest file
    # and performs the actions after it.
    #
    # Nothing here performs an action the file does not hold.
    class Viewer
      # How many actions there are between two snapshots.
      EVERY = 250

      # What a snapshot file is called, before its numbers.
      PREFIX = "roguelike-replay-"

      # What a snapshot file ends with.
      SUFFIX = ".json"

      # The file being played.
      getter reading : Reading

      # The run as it stands. A jump backwards puts another one here.
      getter game : Game

      # Every action of the file, in the order it was recorded.
      getter acts : Array(Act)

      # How many of those actions have been performed.
      getter at : Int32 = 0

      # The first place the rebuilt run differed from the file, or `nil`.
      #
      # A difference is reported once and the run plays on. Watching a run is
      # worth doing after the build has moved under it, and `replay verify`
      # is what answers whether a file still matches.
      getter trouble : String? = nil

      # The checkpoints, under how many actions come before each.
      @checks : Hash(Int32, Array(Check))

      # Which snapshots are written, in the order they were written.
      @kept = [] of Int32

      # The file at *path*, ready to play.
      def self.open(path : Path | String) : Viewer
        new Reading.read(path)
      end

      def initialize(@reading : Reading)
        @acts = [] of Act
        @checks = Hash(Int32, Array(Check)).new

        @reading.records.each do |record|
          case record
          in Act   then @acts << record
          in Check then (@checks[@acts.size] ||= [] of Check) << record
          end
        end

        @game = Verifier.rebuild @reading.header
        Viewer.sweep
        started
        keep
      end

      # Records what is already wrong before the first action.
      private def started : Nil
        moved = Streams.apart @reading.header.streams
        note "the build's draw sequences differ here: #{moved.join ", "}" unless moved.empty?
        note "the run does not start where the file says it does" unless @game.fingerprint == @reading.header.state
      end

      # How many actions the file holds.
      def size : Int32
        @acts.size
      end

      # The turn the run has reached.
      def turn : Int32
        @game.turn
      end

      # The turn the file's last action is on.
      def last_turn : Int32
        @acts.last?.try(&.turn) || @reading.header.turn
      end

      # Whether every action has been performed.
      def done? : Bool
        @at >= @acts.size
      end

      # Performs the next action. Answers whether there was one to perform.
      def forward : Bool
        return false if done?

        act = @acts[@at]
        verdict = @game.perform act.action
        @at += 1
        @game.look

        note "turn #{act.turn}: #{act.action.t} was refused" if verdict.refused?
        compared
        keep if (@at % EVERY).zero?
        true
      end

      # Takes one action back. Answers whether there was one to take back.
      def back : Bool
        goto @at - 1
      end

      # Puts the run where *wanted* actions have been performed.
      #
      # A number outside the file is pulled to the nearest end of it. The
      # answer is whether the run moved.
      def goto(wanted : Int32) : Bool
        target = wanted.clamp 0, @acts.size
        return false if target == @at

        restore target if target < @at
        while @at < target
          forward
        end

        true
      end

      # Puts the run on turn *wanted*, or on the first turn after it.
      #
      # A turn past the end of the file leaves the run at the end.
      def to_turn(wanted : Int32) : Bool
        found = @acts.index { |act| act.turn >= wanted }
        goto found ? found + 1 : @acts.size
      end

      # Compares the checkpoints that stand where the run now stands.
      private def compared : Nil
        found = @checks[@at]?
        return unless found

        state = @game.fingerprint
        found.each do |check|
          note "turn #{check.turn}: the run differs from the file" unless state == check.state
        end
      end

      # Records *what* as the first difference. A later one is dropped.
      private def note(what : String) : Nil
        @trouble ||= what
      end

      # Writes the run as it stands, under how many actions are behind it.
      #
      # A file that will not open stops the snapshots and not the viewing.
      # `#restore` reads whatever was written and rebuilds from the header
      # when nothing was.
      private def keep : Nil
        return if @kept.includes? @at

        File.write Viewer.file_at(@at), @game.to_json
        @kept << @at
      rescue error : ::File::Error
        STDERR.puts "replay viewer: #{error.message}"
      end

      # Puts the run back to the nearest snapshot at or before *target*.
      private def restore(target : Int32) : Nil
        found = @kept.select { |index| index <= target }.max?

        if found
          @game = Game.from_json File.read(Viewer.file_at found)
          @at = found
          return
        end

        @game = Verifier.rebuild @reading.header
        @at = 0
      rescue ::File::Error | JSON::Error
        @game = Verifier.rebuild @reading.header
        @at = 0
      end

      # Takes this viewer's snapshots away.
      #
      # The caller runs it however the viewing stops, which includes an
      # exception and a signal.
      def close : Nil
        @kept.each { |index| File.delete? Viewer.file_at index }
        @kept.clear
      end

      # Where the snapshot of *index* actions goes.
      def self.file_at(index : Int32) : Path
        Path[Dir.tempdir] / "#{PREFIX}#{Process.pid}-#{index}#{SUFFIX}"
      end

      # Which process wrote *name*, or `nil` for a name no viewer wrote.
      def self.owner(name : String) : Int64?
        return unless name.starts_with?(PREFIX) && name.ends_with?(SUFFIX)

        rest = name[PREFIX.size...(name.size - SUFFIX.size)]
        rest.split('-', 2).first?.try &.to_i64?
      end

      # Takes away the snapshots of viewers that are gone.
      #
      # A viewer removes its own files as it stops, so what is left here came
      # from one that was killed. A process id is handed out again once the
      # process it named is gone, so a file whose id belongs to a running
      # process is left where it is.
      def self.sweep : Nil
        Dir.each_child(Dir.tempdir) do |name|
          pid = owner name
          next unless pid
          next if pid == Process.pid
          next if Process.exists? pid

          File.delete? Path[Dir.tempdir] / name
        end
      rescue error : ::File::Error
        STDERR.puts "replay viewer: #{error.message}"
      end
    end
  end
end
