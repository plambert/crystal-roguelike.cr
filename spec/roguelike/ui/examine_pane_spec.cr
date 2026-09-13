require "../../spec_helper"

Spectator.describe Roguelike::Ui::ExaminePane do
  alias Terrain = Roguelike::Terrain

  let(floor) { Roguelike::Floor.parse "sample", "#####\n#.<+=\n#,,,%\n##>##" }
  subject(pane) { described_class.new }

  # A dark hall with a goblin standing against a lit square behind it.
  #
  # The character is at the west end. The lit square at the east end is what
  # the goblin shows against.
  BACKLIT = [
    "############",
    "#<.....g..*#",
    "############",
  ]

  # What a character at the west end of `BACKLIT` can see.
  def against_the_light : {Roguelike::Floor, Roguelike::Vision}
    floor = Roguelike::Floor.parse "backlit", BACKLIT
    floor.place Roguelike::Monster.new(Roguelike::Species::Goblin, 7, 1, "band-one")

    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {floor.id => floor}),
      Roguelike::Player.new(floor.id, 1, 1)

    {floor, game.sight}
  end

  describe "a shape against the light" do
    it "says its size rather than its name" do
      floor, seen = against_the_light

      pane.show floor, 7, 1, nil, seen

      expect(pane.where.text).to eq "7, 1"
      expect(pane.what.text).to eq Roguelike::Size::Small.label
      expect(pane.detail.text).to eq Roguelike::Ui::ExaminePane::MOVING
    end

    it "says nothing about what it is doing" do
      floor, seen = against_the_light

      pane.show floor, 7, 1, nil, seen

      expect(pane.doing.hidden?).to be_true
    end

    it "draws it in the colour every shape is drawn in" do
      floor, seen = against_the_light

      pane.show floor, 7, 1, nil, seen

      expect(pane.what.style).to eq Roguelike::Ui::Palette::SHAPE
    end

    it "still says out of sight for a dark square with nothing on it" do
      floor, seen = against_the_light

      pane.show floor, 5, 1, nil, seen

      expect(pane.what.text).to eq Roguelike::Ui::ExaminePane::UNSEEN
    end
  end

  describe "#show" do
    it "writes where, what, and a sentence about it" do
      pane.show floor, 2, 1

      expect(pane.where.text).to eq "2, 1"
      expect(pane.what.text).to eq "staircase up"
      expect(pane.detail.text).to eq "a staircase leading up"
    end

    it "draws what it names in the colour that square is drawn in" do
      pane.show floor, 4, 1

      expect(pane.what.style).to eq Roguelike::Ui::Palette[Terrain::Sandstone].style
    end

    it "tells the three rocks apart, which the map draws alike" do
      pane.show floor, 0, 0
      granite = pane.what.text

      pane.show floor, 4, 1
      sandstone = pane.what.text

      pane.show floor, 4, 2
      shale = pane.what.text

      expect([granite, sandstone, shale]).to eq ["granite", "sandstone", "shale"]
    end

    it "tells the two floors apart" do
      pane.show floor, 1, 1
      stone = pane.what.text

      pane.show floor, 1, 2
      dirt = pane.what.text

      expect([stone, dirt]).to eq ["stone floor", "dirt floor"]
    end

    it "shows the coordinates it had been hiding" do
      pane.show floor, 2, 1

      expect(pane.where.hidden?).to be_false
    end
  end

  describe "#clear" do
    it "says there is nothing to say" do
      pane.show floor, 2, 1
      pane.clear

      expect(pane.what.text).to eq Roguelike::Ui::ExaminePane::NOTHING
      expect(pane.detail.text).to be_empty
    end

    # An empty label still takes a row. A blank row under the rule reads as
    # something missing.
    it "hides the coordinates rather than leaving a blank row" do
      pane.show floor, 2, 1
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
