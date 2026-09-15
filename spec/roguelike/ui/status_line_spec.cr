require "../../spec_helper"

Spectator.describe Roguelike::Ui::StatusLine do
  alias Which = Roguelike::Attributes::Which

  # How wide a window holds the whole row.
  #
  # The character starts with a short sword readied, and the weapon's name is
  # on the row, so the row is as long as it ever is from turn zero. The pairs
  # after the attributes are read least often, so they are cut first on
  # anything narrower.
  WHOLE = 150

  # The status row of a run, as the screen drew it.
  def written(run : Playing::Run) : String
    run.rows.find(&.includes?("hp:")) || ""
  end

  describe "what it says" do
    it "writes the hit points over the maximum" do
      run = Playing.open
      player = run.game.player

      expect(written(run)).to contain "hp: #{player.hit_points}/#{player.max_hit_points}"
    end

    it "writes the floor and the experience" do
      run = Playing.open

      expect(written(run)).to contain "lv: 1"
      expect(written(run)).to contain "xp: 0/#{Roguelike::Advancement.threshold(2)}"
    end

    it "writes the turn" do
      run = Playing.open columns: WHOLE, rows: 24
      run.press "l"

      expect(written(run)).to contain "turn: 1"
    end

    it "writes every score" do
      run = Playing.open columns: WHOLE, rows: 24
      line = written run

      Which.values.each do |which|
        expect(line).to contain which.short.downcase
      end
    end

    it "counts the gold" do
      run = Playing.open

      expect(run.play.status_line.bar["gold"]?.try &.text).to eq "0"
    end

    # At eighty columns this pair is cut from the row. The bar still holds it,
    # and a wider window shows it.
    it "writes where the character stands" do
      run = Playing.open

      expect(run.play.status_line.bar["at"]?.try &.text)
        .to eq "#{run.at[0]},#{run.at[1]}"
    end

    it "follows the character as it moves" do
      run = Playing.open
      run.press "l"

      expect(run.play.status_line.bar["at"]?.try &.text)
        .to eq "#{run.at[0]},#{run.at[1]}"
    end
  end

  describe "the experience pair" do
    it "shows the count alone at the last floor" do
      line = described_class.new
      game = Playing.open.game
      game.player.gain Int32::MAX
      line.show game

      expect(line.bar["xp"]?.try &.text).to eq game.player.experience.to_s
    end
  end

  describe "the hit point colour" do
    def coloured(hit_points : Int32) : TermBuf::Style?
      line = described_class.new
      game = Playing.open.game
      game.player.hurt game.player.max_hit_points - hit_points
      line.show game

      line.bar["hp"]?.try &.style
    end

    it "is the bar's own while the character is well" do
      expect(coloured(8)).to be_nil
    end

    it "changes once the character is half down" do
      expect(coloured(4)).to eq Roguelike::Ui::StatusLine::HURT
    end

    it "changes again once the character is nearly out" do
      expect(coloured(2)).to eq Roguelike::Ui::StatusLine::DYING
    end
  end

  describe "a narrow window" do
    # The bar cuts from the right and marks the cut. The pairs are added in
    # the order they matter, so the ones kept are the ones a person needs.
    it "keeps the hit points and cuts the rest" do
      run = Playing.open columns: 46, rows: 20
      line = written run

      expect(line).to contain "hp:"
      expect(line).to contain "…"
      expect(line).not_to contain "mouse"
    end

    it "keeps everything when there is room" do
      run = Playing.open columns: WHOLE, rows: 24

      expect(written(run)).not_to contain "…"
      expect(written(run)).to contain "mouse: on"
    end
  end

  describe "the mouse pair" do
    it "says what the terminal is doing" do
      run = Playing.open columns: WHOLE, rows: 24
      run.play.mousing = false
      run.render

      expect(written(run)).to contain "mouse: off"
    end
  end

  describe "drawn" do
    it "draws what it drew last time" do
      run = Playing.open columns: 100, rows: 24
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/status-line.txt", drawn)
    end
  end
end
