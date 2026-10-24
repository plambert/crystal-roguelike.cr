require "../../roguelike"

module Roguelike
  module Replay
    # The messages of a recorded run, one line each, with the turn they came on.
    #
    # The fingerprint leaves the message log out, so `replay verify` cannot
    # see a build that picks a different sentence and changes nothing else.
    # Dumping the same replay with two builds and comparing the output shows
    # the wording change at the turn it happened.
    #
    # The run is rebuilt from the header and every action is performed in the
    # order it was recorded, the way `Replay::Verifier` does it. Each line the
    # game adds to its log is written as the turn, a tab and the message.
    #
    # The fingerprints are compared as the run goes. The messages after a
    # difference say nothing about the build, so the lines of an action are
    # held back until the next checkpoint agrees. A difference stops the dump
    # with a report, and the lines since the last agreeing checkpoint are not
    # written.
    #
    # Only lines the game adds while performing actions are here. A line a
    # run's ui writes outside `Game#perform` is not in the replay and does
    # not appear. A repeated message gets a count on the line already
    # written, and the dump does not write that line again.
    module Dump
      # What dumping one replay found.
      record Report,
        path : Path,
        turn : Int32,
        lines : Int32,
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
            io << "dumped " << @lines << " messages, to turn " << @turn
          end
        end
      end

      # Writes the messages of the run in *source* to *to*. Answers what was
      # written.
      def self.run(source : Path | String, to : IO) : Report
        from = Path.new source
        read = Reading.read source
        game = Verifier.rebuild read.header
        cursor = PlaybackCursor.new read, game

        if cursor.opening
          return Report.new from, 0, 0,
            "the run does not start where it was recorded from. " \
            "Check it with replay verify."
        end

        written from, cursor, to
      end

      # Writes the messages of every action left on *cursor*.
      private def self.written(from : Path, cursor : PlaybackCursor,
                               to : IO) : Report
        mark = cursor.game.log.written
        held = [] of String
        count = 0

        flush = -> {
          held.each do |line|
            to << line << '\n'
            count += 1
          end
          held.clear
        }

        while cursor.next_record
          step = cursor.advance
          break unless step
          game = cursor.game

          if failure = step.failure
            return Report.new from, game.turn, count,
              trouble(failure, step.record)
          end

          case step.record
          in Act
            fresh = {game.log.written - mark, game.log.lines.size}.min
            game.log.lines.last(fresh).each do |text|
              held << "#{game.turn}\t#{text}"
            end
            mark = game.log.written
          in Check, Pause
            flush.call
          in Resume
            flush.call
            mark = game.log.written
          end
        end

        if failure = cursor.finish
          return Report.new from, cursor.game.turn, count,
            trouble(failure, nil)
        end

        flush.call
        Report.new from, cursor.game.turn, count
      end

      # The line describing a playback failure.
      private def self.trouble(failure : PlaybackFailure,
                               record : Record?) : String
        failure.consumer_message record
      end
    end
  end
end
