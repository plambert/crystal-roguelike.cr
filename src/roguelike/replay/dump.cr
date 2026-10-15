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

        unless game.agrees? read.header.state
          return Report.new from, 0, 0,
            "the run does not start where it was recorded from. " \
            "Check it with replay verify."
        end

        written from, read, game, to
      end

      # Writes the messages of every action of *read*.
      private def self.written(from : Path, read : Reading, game : Game,
                               to : IO) : Report
        bookmarks = Bookmarks.for read
        mark = game.log.written
        held = [] of String
        count = 0

        flush = -> {
          held.each do |line|
            to << line << '\n'
            count += 1
          end
          held.clear
        }

        read.records.each do |line|
          case line
          in Act
            verdict = game.perform line.action
            if verdict.refused?
              return Report.new from, game.turn, count,
                "turn #{line.turn}: #{line.action.t} was refused"
            end

            game.look
            fresh = {game.log.written - mark, game.log.lines.size}.min
            game.log.lines.last(fresh).each do |text|
              held << "#{game.turn}\t#{text}"
            end
            mark = game.log.written
          in Check, Pause
            unless game.agrees?(line.state)
              return Report.new from, game.turn, count,
                "turn #{line.turn}: the run differs from what was recorded. " \
                "Check it with replay verify."
            end

            flush.call
            bookmarks.paused line, game if line.is_a? Pause
          in Resume
            unless bookmarks.seen? line
              return Report.new from, game.turn, count,
                "turn #{line.turn}: the file resumes from pause " \
                "#{line.pause}, which it does not hold"
            end

            game = bookmarks.resumed line, game
            unless game.agrees?(line.state)
              return Report.new from, game.turn, count,
                "turn #{line.turn}: the loaded run differs from what was " \
                "recorded. Check it with replay verify."
            end

            flush.call
            mark = game.log.written
          end
        end

        state = read.footer.try &.state
        if state && !game.agrees?(state)
          return Report.new from, game.turn, count,
            "turn #{game.turn}: the run ends differently from what was " \
            "recorded. Check it with replay verify."
        end

        flush.call
        Report.new from, game.turn, count
      end
    end
  end
end
