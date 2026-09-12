require "../../spec_helper"

Spectator.describe Roguelike::Ui::Palette do
  alias Palette = Roguelike::Ui::Palette
  alias Terrain = Roguelike::Terrain

  # A wall catches the light and a floor does not. A floor drawn as brightly
  # as the wall beside it gives a room no edge.
  describe "how bright each thing starts" do
    it "draws every wall brighter than the floor of the same room" do
      expect(Palette[Terrain::Granite].style.foreground.green)
        .to be > Palette[Terrain::StoneFloor].style.foreground.green
      expect(Palette[Terrain::Sandstone].style.foreground.green)
        .to be > Palette[Terrain::DirtFloor].style.foreground.green
    end

    it "draws an item brighter than the floor it lies on" do
      weapon = Palette[Roguelike::Item.new Roguelike::ItemKind::LongSword]

      expect(weapon.style.foreground.green)
        .to be > Palette[Terrain::StoneFloor].style.foreground.green
    end
  end

  # A dim sandstone wall and a lit dirt floor are both brown. Telling them
  # apart is what the hues are for.
  describe "how far apart two things of one family are" do
    def apart(first : TermBuf::Style, second : TermBuf::Style) : Float64
      one = first.foreground
      two = second.foreground

      Math.sqrt(((one.red - two.red) ** 2 + (one.green - two.green) ** 2 +
                 (one.blue - two.blue) ** 2).to_f)
    end

    it "keeps a sandstone wall apart from a dirt floor at the same light" do
      (0..Palette::RAMP.top).each do |step|
        wall = Palette::RAMP[Palette::SANDSTONE, step]
        ground = Palette::RAMP[Palette::DIRT, step]

        expect(apart wall, ground).to be > 25
      end
    end

    it "keeps a granite wall apart from a stone floor at the same light" do
      (0..Palette::RAMP.top).each do |step|
        wall = Palette::RAMP[Palette::GRANITE, step]
        ground = Palette::RAMP[Palette::STONE, step]

        expect(apart wall, ground).to be > 10
      end
    end
  end

  describe "a lit sconce" do
    # `!` is the potion glyph. A burning bracket is the same bracket it was
    # before somebody put a light in it.
    it "draws as the bracket it is rather than as a potion" do
      lit = Roguelike::Fixture.new Roguelike::FixtureKind::Sconce, true
      dark = Roguelike::Fixture.new Roguelike::FixtureKind::Sconce, false

      expect(Palette[lit].glyph).to eq '|'
      expect(Palette[dark].glyph).to eq '|'
      expect(Palette[lit].style).not_to eq Palette[dark].style
    end

    it "draws in the flame colour" do
      lit = Roguelike::Fixture.new Roguelike::FixtureKind::Sconce, true

      expect(Palette[lit].style).to eq Palette::FLAME
    end
  end
end
