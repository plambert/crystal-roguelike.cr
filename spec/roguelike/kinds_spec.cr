require "../spec_helper"

Spectator.describe Roguelike::Kind do
  alias Kind = Roguelike::Kind
  alias Kinds = Roguelike::Kinds
  alias Monster = Roguelike::Monster
  alias Palette = Roguelike::Ui::Palette
  alias Species = Roguelike::Species

  # How far the colour of a creature must stand out from the ground, as a
  # contrast ratio.
  CONTRAST = 4.5

  # The relative luminance of *color*, as the contrast ratio reads it.
  def luminance(color : TermBuf::Color) : Float64
    channels = [color.red, color.green, color.blue].map do |channel|
      value = channel / 255.0
      value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
    end

    0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
  end

  describe "every kind" do
    it "has a name, a sentence and numbers that make sense" do
      Kind.each do |kind|
        expect(kind.label).not_to be_empty
        expect(kind.plural).not_to be_empty
        expect(kind.description).not_to be_empty
        expect(kind.hit_points).to be > 1
        expect(kind.hit_dice.minimum).to be > 1
        expect(kind.experience).to be > 0
        expect(kind.weight).to be > 0
        expect(kind.speed).to be > 0
        expect(kind.light).to be_between(0, 100)
        expect(kind.depths.begin).to be >= 1
        expect(kind.depths.end).to be >= kind.depths.begin
      end
    end

    it "draws as the letter of its species" do
      Kind.each { |kind| expect(kind.mark).to eq kind.species.mark }
    end

    it "has a colour no other kind of its species has" do
      Species.each do |species|
        colors = species.kinds.map { |kind| Palette[kind].style.foreground }

        expect(colors.uniq.size).to eq colors.size
      end
    end

    it "stands out from the ground" do
      ground = luminance Palette::GROUND

      Kind.each do |kind|
        found = luminance Palette[kind].style.foreground
        ratio = (found + 0.05) / (ground + 0.05)

        expect(ratio).to be >= CONTRAST
      end
    end
  end

  describe "the default kind of a species" do
    it "is the creature the species was before it had kinds" do
      expect(Species::Slime.default).to eq Kind::WhiteSlime
      expect(Species::Goblin.default).to eq Kind::GoblinWarrior
      expect(Species::Orc.default).to eq Kind::Orc

      expect(Kind::WhiteSlime.hit_points).to eq 6
      expect(Kind::GoblinWarrior.hit_points).to eq 9
      expect(Kind::Orc.hit_points).to eq 14
    end

    it "is what a floor file's letter names" do
      Species.each { |species| expect(Kind.from_mark? species.mark).to eq species.default }
    end

    it "belongs to its species" do
      Species.each { |species| expect(species.default.species).to eq species }
    end
  end

  describe "the variants" do
    it "gives a blue slime more hit points than a white one" do
      expect(Kind::BlueSlime.hit_points).to be > Kind::WhiteSlime.hit_points
    end

    it "gives a red slime more damage than a white one, and a green one the most" do
      expect(Kind::RedSlime.damage.average).to be > Kind::WhiteSlime.damage.average
      Species::Slime.kinds.each do |slime|
        expect(Kind::GreenSlime.damage.average).to be >= slime.damage.average
      end
    end

    it "sends a goblin scout out alone, and nothing else" do
      expect(Kind.values.select &.alone?).to eq [Kind::GoblinScout]
    end

    it "gives a goblin scout worse armor than a warrior" do
      scout = Monster.new Kind::GoblinScout, 0, 0, "band"
      warrior = Monster.new Kind::GoblinWarrior, 0, 0, "band"

      expect(scout.armor_class).to be < warrior.armor_class
    end

    it "lets only the shaman mend and cast" do
      expect(Kind.values.select &.mends?).to eq [Kind::GoblinShaman]
      expect(Kind.values.select &.casts?).to eq [Kind::GoblinShaman]
    end
  end

  describe "Kinds.at" do
    it "answers only the kinds that appear at a depth" do
      (1..5).each do |depth|
        Kinds.at(depth).each_key { |kind| expect(kind.appears_at? depth).to be_true }
      end
    end

    it "has something to place at every depth" do
      (1..5).each { |depth| expect(Kinds.at depth).not_to be_empty }
    end

    it "answers every kind that appears anywhere in a range of depths" do
      expect(Kinds.at(1..2).keys.to_set).to eq Set{Kind::WhiteSlime, Kind::BlueSlime,
                                                   Kind::RedSlime, Kind::GoblinScout, Kind::GoblinWarrior}
    end

    it "keeps to a species and to company when asked" do
      found = Kinds.at 2, Species::Goblin, alone: false

      expect(found.keys).to eq [Kind::GoblinWarrior]
    end
  end

  describe "a save" do
    it "round-trips a creature's kind" do
      slime = Monster.new Kind::BlueSlime, 3, 4, "band-one", hit_points: 7,
        max_hit_points: 12
      again = Monster.from_json slime.to_json

      expect(again).to eq slime
      expect(again.kind).to eq Kind::BlueSlime
      expect(again.species).to eq Species::Slime
      expect(again.max_hit_points).to eq 12
      expect(again.label).to eq "blue slime"
    end

    # What a save written before kinds existed holds for one creature.
    OLD = %({"id":3,"species":"goblin","x":4,"y":5,"hit_points":6,) +
          %("attributes":{"strength":10,"dexterity":13,"constitution":10,) +
          %("intelligence":7,"stealth":13},"band":"band-one","memory":{},) +
          %("carrying":[],"blinded":0,"pace":{"base":100,"energy":0}})

    it "loads a bare species as its default kind" do
      old = Monster.from_json OLD

      expect(old.kind).to eq Kind::GoblinWarrior
      expect(old.species).to eq Species::Goblin
      expect(old.hit_points).to eq 6
      expect(old.max_hit_points).to eq Kind::GoblinWarrior.hit_points
    end

    it "writes the kind out once it has loaded one" do
      again = Monster.from_json Monster.from_json(OLD).to_json

      expect(again.kind).to eq Kind::GoblinWarrior
      expect(again.max_hit_points).to eq Kind::GoblinWarrior.hit_points
    end
  end
end
