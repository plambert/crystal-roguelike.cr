require "../../spec_helper"

Spectator.describe "the messages of the current turn" do
  alias Palette = Roguelike::Ui::Palette

  # The style the buffer drew the first cell of *text* in, on whichever row
  # holds it.
  def drawn(run : Playing::Run, text : String) : TermBuf::Style
    row = run.rows.index(&.includes?(text))
    raise "#{text.inspect} is not on the screen" unless row

    found = run.buffer.hit run.rows[row].index!(text), row
    raise "nothing is drawn at #{text.inspect}" unless found

    run.buffer.styles[found.cell.style]
  end

  # Writes *line* the way an action does and draws it.
  def write(run : Playing::Run, line : String) : Nil
    run.game.log.add line
    run.play.refresh
    run.render
  end

  describe "the log" do
    it "stamps a line with the round it was written in" do
      log = Roguelike::MessageLog.new
      log.add "first"
      log.next_round
      log.add "second"

      expect(log.round_of 0).to eq 0
      expect(log.round_of 1).to eq 1
    end

    it "counts the lines of the last closed round and later ones as current" do
      log = Roguelike::MessageLog.new
      log.add "first"
      log.next_round
      log.add "second"
      log.next_round
      log.add "third"

      expect(log.current).to eq 2
    end

    it "lets a line fall back two rounds after it was written" do
      log = Roguelike::MessageLog.new
      log.add "first"
      2.times { log.next_round }

      expect(log.current).to eq 0
    end

    it "keeps the rounds through a save and a load" do
      log = Roguelike::MessageLog.new
      log.add "first"
      log.next_round
      log.add "second"
      log.next_round

      back = Roguelike::MessageLog.from_json log.to_json

      expect(back.lines).to eq ["first", "second"]
      expect(back.rounds).to eq [0, 1]
      expect(back.current).to eq 1
    end

    it "reads a log saved without rounds as older than any round" do
      back = Roguelike::MessageLog.from_json %({"lines":["old","older"]})
      back.add "new"

      expect(back.rounds).to eq [-1, -1, 0]
      expect(back.current).to eq 1
    end

    it "drops the round with the line when the log is full" do
      log = Roguelike::MessageLog.new
      (Roguelike::MessageLog::LIMIT + 5).times { |count| log.add "line #{count}" }

      expect(log.rounds.size).to eq log.lines.size
    end

    it "keeps a run's rounds through a save and a load" do
      run = Playing.open
      run.press "h"
      before = run.game.log.rounds.dup

      back = Roguelike::Game.from_json run.game.to_json

      expect(back.log.rounds).to eq before
      expect(back.log.current).to eq run.game.log.current
    end
  end

  describe "the message pane" do
    it "draws a line from this turn in the bright colour" do
      run = Playing.open
      write run, "Something just happened."

      expect(drawn run, "Something just happened.").to eq Palette::MESSAGE_NEW
    end

    it "draws a line from an earlier turn in the ordinary colour" do
      run = Playing.open
      write run, "Something happened before."
      2.times { run.game.log.next_round }
      write run, "Something happens now."

      expect(drawn run, "Something happened before.").not_to eq Palette::MESSAGE_NEW
      expect(drawn run, "Something happens now.").to eq Palette::MESSAGE_NEW
    end

    it "brings a repeated line back into the current round" do
      log = Roguelike::MessageLog.new
      log.add "The granite blocks your way."
      2.times { log.next_round }
      log.add "The granite blocks your way."

      expect(log.size).to eq 1
      expect(log.current).to eq 1
    end

    it "keeps the bright colour distinct from the ordinary one" do
      run = Playing.open
      write run, "Old news."
      2.times { run.game.log.next_round }
      write run, "New news."

      old = drawn run, "Old news."
      fresh = drawn run, "New news."

      expect(fresh.foreground).not_to eq old.foreground
      expect(fresh.attributes).to eq TermBuf::Attributes::Bold
    end

    it "lets a turn's lines fall back when the next command is taken" do
      run = Playing.open
      run.clear_monsters
      20.times { run.press "h" }
      bumped = run.said

      expect(drawn run, bumped).to eq Palette::MESSAGE_NEW

      run.press "."
      run.press "."
      run.press "."

      expect(drawn run, bumped).not_to eq Palette::MESSAGE_NEW
    end

    it "draws every line a turn wrote in the bright colour" do
      run = Playing.open
      write run, "Alpha happened."
      write run, "Beta happened."

      expect(drawn run, "Alpha happened.").to eq Palette::MESSAGE_NEW
      expect(drawn run, "Beta happened.").to eq Palette::MESSAGE_NEW
    end

    it "holds at --More-- as before" do
      run = Playing.open
      6.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      run.render

      expect(run.rows[23]).to contain "--More--"
    end
  end
end
