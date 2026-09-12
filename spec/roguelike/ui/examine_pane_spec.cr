require "../../spec_helper"

Spectator.describe Roguelike::Ui::ExaminePane do
  alias Terrain = Roguelike::Terrain

  let(level) { Roguelike::Level.parse "sample", "#####\n#.<+=\n#,,,%\n##>##" }
  subject(pane) { described_class.new }

  describe "#show" do
    it "writes where, what, and a sentence about it" do
      pane.show level, 2, 1

      expect(pane.where.text).to eq "2, 1"
      expect(pane.what.text).to eq "staircase up"
      expect(pane.detail.text).to eq "a staircase leading up"
    end

    it "draws what it names in the colour that square is drawn in" do
      pane.show level, 4, 1

      expect(pane.what.style).to eq Roguelike::Ui::Palette[Terrain::Sandstone].style
    end

    it "tells the three rocks apart, which the map draws alike" do
      pane.show level, 0, 0
      granite = pane.what.text

      pane.show level, 4, 1
      sandstone = pane.what.text

      pane.show level, 4, 2
      shale = pane.what.text

      expect([granite, sandstone, shale]).to eq ["granite", "sandstone", "shale"]
    end

    it "tells the two floors apart" do
      pane.show level, 1, 1
      stone = pane.what.text

      pane.show level, 1, 2
      dirt = pane.what.text

      expect([stone, dirt]).to eq ["stone floor", "dirt floor"]
    end

    it "shows the coordinates it had been hiding" do
      pane.show level, 2, 1

      expect(pane.where.hidden?).to be_false
    end
  end

  describe "#clear" do
    it "says there is nothing to say" do
      pane.show level, 2, 1
      pane.clear

      expect(pane.what.text).to eq Roguelike::Ui::ExaminePane::NOTHING
      expect(pane.detail.text).to be_empty
    end

    # An empty label still takes a row. A blank row under the rule reads as
    # something missing.
    it "hides the coordinates rather than leaving a blank row" do
      pane.show level, 2, 1
      pane.clear

      expect(pane.where.hidden?).to be_true
    end
  end

  describe "before anything" do
    it "starts cleared" do
      expect(pane.what.text).to eq Roguelike::Ui::ExaminePane::NOTHING
      expect(pane.where.hidden?).to be_true
    end
  end
end
