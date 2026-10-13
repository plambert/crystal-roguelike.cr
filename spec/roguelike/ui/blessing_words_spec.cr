require "../../spec_helper"

Spectator.describe Roguelike::Ui::BlessingWords do
  alias BlessingWords = Roguelike::Ui::BlessingWords

  # Each accent in *line* as the text it covers and its style.
  def marked(line : String) : Array({String, TermBuf::Style})
    BlessingWords.accents(line).map { |mark| {line[mark.start, mark.size], mark.style} }
  end

  describe ".accents" do
    it "marks blessed in white and cursed in red" do
      expect(marked "a blessed dagger and a cursed ring")
        .to eq [{"blessed", BlessingWords::BLESSED}, {"cursed", BlessingWords::CURSED}]
    end

    it "colors the underline and nothing else" do
      expect(BlessingWords::BLESSED.underline).to eq TermBuf::Underline::Single
      expect(BlessingWords::BLESSED.underline_color).to eq TermBuf::Color.rgb(0xFF, 0xFF, 0xFF)
      expect(BlessingWords::CURSED.underline_color).to eq Roguelike::Ui::Palette::RED
      expect(BlessingWords::CURSED.foreground.default?).to be_true
    end

    it "matches at the start of a sentence" do
      expect(marked "Cursed! It will not come off.").to eq [{"Cursed", BlessingWords::CURSED}]
      expect(marked "Blessed water.").to eq [{"Blessed", BlessingWords::BLESSED}]
    end

    it "leaves uncursed and longer words alone" do
      expect(marked "an uncursed ring").to be_empty
      expect(marked "the accursed blessedness").to be_empty
    end

    it "finds the word beside punctuation and a repeat count" do
      expect(marked "The ring is cursed. (x 3)").to eq [{"cursed", BlessingWords::CURSED}]
    end
  end

  describe "the message pane" do
    it "underlines the word and keeps the log's text" do
      run = Playing.open
      run.game.log.add "You feel that the ring is cursed."
      run.play.refresh
      run.render

      row = run.rows.index!(&.includes?("ring is cursed."))
      column = run.rows[row].index!("cursed.")
      style = ->(at : Int32) do
        found = run.buffer.hit at, row
        raise "nothing is drawn at #{at}, #{row}" unless found
        run.buffer.styles[found.cell.style]
      end

      expect(style.call(column).underline).to eq TermBuf::Underline::Single
      expect(style.call(column + 5).underline).to eq TermBuf::Underline::Single
      expect(style.call(column + 6).underline).to eq TermBuf::Underline::None
      expect(style.call(column - 2).underline).to eq TermBuf::Underline::None
      expect(run.game.log.lines.last).to eq "You feel that the ring is cursed."
    end
  end
end
