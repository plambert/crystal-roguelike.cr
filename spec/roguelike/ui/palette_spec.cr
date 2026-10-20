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
      (0..Palette.ramp.top).each do |step|
        wall = Palette.ramp[Palette.sandstone, step]
        ground = Palette.ramp[Palette.dirt, step]

        expect(apart wall, ground).to be > 25
      end
    end

    it "keeps a granite wall apart from a stone floor at the same light" do
      (0..Palette.ramp.top).each do |step|
        wall = Palette.ramp[Palette.granite, step]
        ground = Palette.ramp[Palette.stone, step]

        expect(apart wall, ground).to be > 10
      end
    end
  end

  # A game about darkness needs a known black. A pale theme would turn the
  # dim end of the ramp into the high-contrast end.
  describe "the ground the map is painted on" do
    it "is set on every shaded look rather than left to the terminal" do
      (0..Palette.ramp.top).each do |step|
        shaded = Palette.shaded Palette[Terrain::StoneFloor], step

        expect(shaded.style.background).to eq Palette.ground
      end
    end

    it "is set on a square nobody has seen" do
      expect(Palette.unseen.style.background).to eq Palette.ground
    end

    it "stays the same at every step" do
      grounds = (0..Palette.ramp.top).map do |step|
        Palette.shaded(Palette[Terrain::Granite], step).style.background
      end

      expect(grounds.uniq.size).to eq 1
    end

    it "is darker than the dimmest thing drawn on it" do
      dimmest = Palette.ramp[Palette.stone, Palette::REMEMBERED].foreground

      expect(Palette.ground.red).to be < dimmest.red
      expect(Palette.ground.green).to be < dimmest.green
      expect(Palette.ground.blue).to be < dimmest.blue
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

    it "draws in the flame color" do
      lit = Roguelike::Fixture.new Roguelike::FixtureKind::Sconce, true

      expect(Palette[lit].style).to eq Palette.flame
    end
  end
end

Spectator.describe "Roguelike::Ui::Palette.rebuild" do
  alias Palette = Roguelike::Ui::Palette
  alias Theme = Roguelike::Ui::Theme

  after_each { Palette.rebuild Theme::DEFAULT }

  # Something to tell two ramps apart by.
  PROBE = TermBuf::Style::DEFAULT.fg TermBuf::Color.rgb(0xC0, 0xC0, 0xC0)

  def signature(value : Roguelike::Ui::Widgets::Ramp) : String
    (0..value.top).map { |step| value[PROBE, step] }.inspect
  end

  def signature(value : Hash) : String
    value.transform_values { |each| signature each }.inspect
  end

  def signature(value) : String
    value.inspect
  end

  # What every reader on the palette answers.
  def drawn : Hash(String, String)
    found = {} of String => String
    {% for method in Roguelike::Ui::Palette::Table.methods %}
      {% unless %w[initialize theme].includes? method.name.stringify %}
        found[{{ method.name.stringify }}] = signature Palette.{{ method.name }}
      {% end %}
    {% end %}
    found
  end

  # The readers whose answer changes when *key* is set to a new color.
  def changed_by(key : String) : Array(String)
    Palette.rebuild Theme::DEFAULT
    before = drawn
    Palette.rebuild Theme::DEFAULT.with(key, TermBuf::Color.rgb(0x01, 0x02, 0x03))
    after = drawn

    before.keys.reject { |name| before[name] == after[name] }.sort!
  end

  it "changes what reads a changed color and nothing else" do
    expect(changed_by "red").to eq %w[cursed_word health red threat]
    expect(changed_by "granite").to eq %w[granite looks]
    expect(changed_by "shadow").to eq %w[ramp shadow]
    expect(changed_by "ground").to eq %w[ground ground_style spotlit unseen]
    expect(changed_by "flame").to eq %w[flame lights tints]
    expect(changed_by "header_ground").to eq %w[header header_ground header_title]
  end

  it "changes something for every color" do
    Theme.keys.each do |key|
      expect(changed_by key).not_to be_empty
    end
  end

  it "answers the default styles again after a rebuild from the default" do
    before = drawn
    Palette.rebuild Theme::DEFAULT.with("red", TermBuf::Color.rgb(1, 2, 3))
    Palette.rebuild Theme::DEFAULT

    expect(drawn).to eq before
  end
end
