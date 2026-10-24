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
      pause : Int32? = nil

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
      # Exit-handler footers have no final fingerprint, so their turn may be
      # beyond the actions in the file. A cut-off line can leave an earlier
      # footer behind.
      def self.footer(reading : Reading, game : Game) : PlaybackFailure?
        return if reading.truncated?
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
