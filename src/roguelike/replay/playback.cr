require "../../roguelike"

module Roguelike
  module Replay
    # One problem found while rebuilding a replay.
    enum PlaybackProblem
      Opening
      Over
      Refused
      Fingerprint
      Saved
      ResumeMissing
      FooterTurn
      FooterFingerprint
      FooterOutcome
    end

    # Why a replay did not match the run it records.
    record PlaybackFailure,
      problem : PlaybackProblem,
      turn : Int32,
      expected : String? = nil,
      found : String? = nil,
      expected_turn : Int32? = nil,
      found_turn : Int32? = nil,
      pause : Int32? = nil do
      # The concise message shared by replay export and dump.
      def consumer_message(record : Record?) : String
        case @problem
        in .opening?
          "the run does not start where it was recorded from. Check it with replay verify."
        in .over?, .refused?
          "turn #{@turn}: #{@expected} was refused"
        in .fingerprint?
          "turn #{@turn}: the run differs from what was recorded. Check it with replay verify."
        in .saved?
          if record.is_a?(Resume)
            "turn #{@turn}: the loaded run differs from what was recorded. Check it with replay verify."
          else
            "turn #{@turn}: the run differs from what was recorded. Check it with replay verify."
          end
        in .resume_missing?
          "turn #{@turn}: the file resumes from pause #{@pause}, which it does not hold"
        in .footer_turn?
          "the run ends on turn #{@found_turn}, but the file says turn #{@expected_turn}. " \
          "Check it with replay verify."
        in .footer_fingerprint?
          "turn #{@turn}: the run ends differently from what was recorded. Check it with replay verify."
        in .footer_outcome?
          "the run ended #{@found} and the file says #{@expected}. Check it with replay verify."
        end
      end
    end

    # One record and the result of applying and checking it.
    record PlaybackStep, record : Record, failure : PlaybackFailure? = nil

    # Rebuilds a replay one record at a time.
    class PlaybackCursor
      getter reading : Reading

      getter game : Game

      getter at : Int32

      getter bookmarks : Bookmarks

      getter seen : Vision? = nil

      def initialize(@reading : Reading, @game : Game, @at : Int32 = 0,
                     bookmarks : Bookmarks? = nil)
        @bookmarks = bookmarks || Bookmarks.for(@reading)
      end

      # The next record, without applying it.
      def next_record : Record?
        @reading.records[@at]?
      end

      # Rebuilds what the character sees and remembers.
      def look : Vision
        @seen = @game.look
      end

      # Whether the rebuilt run starts at the header's state.
      def opening : PlaybackFailure?
        found = @game.fingerprint like: @reading.header.state
        return if found == @reading.header.state

        PlaybackFailure.new PlaybackProblem::Opening, @reading.header.turn,
          @reading.header.state, found
      end

      # Applies the next record and checks its saved state.
      def advance : PlaybackStep?
        record = next_record
        return unless record

        @at += 1
        failure = case record
                  in Act    then action(record)
                  in Check  then checkpoint(record)
                  in Pause  then pause(record)
                  in Resume then resume(record)
                  end
        PlaybackStep.new record, failure
      end

      # Checks the final footer when the file carries a complete fingerprint.
      def finish : PlaybackFailure?
        PlaybackCursor.footer @reading, @game
      end

      # Checks the final footer without starting a record traversal.
      #
      # A malformed tail does not replace a complete footer. Reading clears
      # it only when another complete record follows.
      def self.footer(reading : Reading, game : Game) : PlaybackFailure?
        footer = reading.footer
        return unless footer
        state = footer.state
        return unless state

        unless game.turn == footer.turn
          return PlaybackFailure.new PlaybackProblem::FooterTurn, footer.turn,
            expected_turn: footer.turn, found_turn: game.turn
        end

        found = game.fingerprint like: state
        unless found == state
          return PlaybackFailure.new PlaybackProblem::FooterFingerprint,
            footer.turn, state, found
        end

        ending = game.outcome.to_s.downcase
        return if ending == footer.ending

        PlaybackFailure.new PlaybackProblem::FooterOutcome, footer.turn,
          footer.ending, ending
      end

      private def action(act : Act) : PlaybackFailure?
        if @game.over?
          return PlaybackFailure.new PlaybackProblem::Over, act.turn,
            act.action.t
        end

        verdict = @game.perform act.action
        if verdict.refused?
          return PlaybackFailure.new PlaybackProblem::Refused, act.turn,
            act.action.t
        end

        @seen = @game.look
        nil
      end

      private def checkpoint(check : Check) : PlaybackFailure?
        found = @game.fingerprint like: check.state
        return if found == check.state

        PlaybackFailure.new PlaybackProblem::Fingerprint, check.turn,
          check.state, found
      end

      private def pause(line : Pause) : PlaybackFailure?
        failure = saved(line.turn, line.state)
        return failure if failure

        @bookmarks.paused line, @game
        nil
      end

      private def resume(line : Resume) : PlaybackFailure?
        unless @bookmarks.seen? line
          return PlaybackFailure.new PlaybackProblem::ResumeMissing,
            line.turn, pause: line.pause
        end

        @game = @bookmarks.resumed line, @game
        saved line.turn, line.state
      end

      private def saved(turn : Int32, state : String) : PlaybackFailure?
        found = @game.fingerprint like: state
        return if found == state && @game.turn == turn

        PlaybackFailure.new PlaybackProblem::Saved, turn, state, found,
          turn, @game.turn
      end
    end
  end
end
