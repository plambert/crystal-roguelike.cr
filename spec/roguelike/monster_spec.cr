require "../spec_helper"

Spectator.describe Roguelike::Monster do
  alias Band = Roguelike::Band
  alias Faction = Roguelike::Faction
  alias Species = Roguelike::Species

  subject(goblin) { described_class.new Species::Goblin, 4, 5, "band-one" }

  it "stands where it was put" do
    expect(goblin.at).to eq({4, 5})
    expect(goblin.at?(4, 5)).to be_true
    expect(goblin.at?(4, 6)).to be_false
  end

  it "takes its statistics from its species" do
    expect(goblin.hit_points).to eq Species::Goblin.hit_points
    expect(goblin.max_hit_points).to eq Species::Goblin.hit_points
    expect(goblin.attributes.to_a).to eq Species::Goblin.attributes.to_a
    expect(goblin.label).to eq "goblin"
  end

  it "takes statistics of its own when it is given them" do
    hurt = described_class.new Species::Goblin, 4, 5, "band-one", hit_points: 2

    expect(hurt.hit_points).to eq 2
    expect(hurt.max_hit_points).to eq Species::Goblin.hit_points
  end

  describe "hit points" do
    it "falls when it is hurt" do
      expect(goblin.hurt 3).to eq Species::Goblin.hit_points - 3
      expect(goblin.alive?).to be_true
    end

    it "stops at nothing" do
      goblin.hurt 999

      expect(goblin.hit_points).to eq 0
      expect(goblin.alive?).to be_false
    end
  end

  describe "the band" do
    # A band is the unit that shares what it knows. Nothing reads it yet.
    it "names one" do
      expect(goblin.band).to eq "band-one"
    end

    it "fights the dungeon's fight by default" do
      expect(Band.new("band-one").faction).to eq Faction::Dungeon
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      goblin.hurt 3
      again = described_class.from_json goblin.to_json

      expect(again).to eq goblin
      expect(again.species).to eq Species::Goblin
      expect(again.hit_points).to eq goblin.hit_points
      expect(again.band).to eq "band-one"
    end

    it "round-trips a band through JSON" do
      band = Band.new "band-one", Faction::Dungeon

      expect(Band.from_json band.to_json).to eq band
    end
  end

  describe "every species" do
    it "has a mark, a name and a sentence" do
      Species.each do |species|
        expect(species.label).not_to be_empty
        expect(species.plural).not_to be_empty
        expect(species.description).not_to be_empty
      end
    end

    it "has a mark of its own" do
      marks = Species.values.map &.mark

      expect(marks.uniq.size).to eq marks.size
    end

    it "is found by its mark" do
      Species.each { |species| expect(Species.from_mark? species.mark).to eq species }
    end

    it "is not found by a mark that names no species" do
      expect(Species.from_mark? '#').to be_nil
      expect(Species.from_mark? '.').to be_nil
    end

    it "takes no mark another layer of a floor file uses" do
      taken = Roguelike::Terrains::MARKS.keys +
              Roguelike::FixtureKind.values.flat_map { |kind| [kind.mark, kind.lit_mark] } +
              [Roguelike::Terrains::GLOW]

      Species.each { |species| expect(taken.includes? species.mark).to be_false }
    end

    it "is worth something to kill" do
      Species.each { |species| expect(species.experience).to be > 0 }
    end

    it "takes more than one hit" do
      Species.each { |species| expect(species.hit_points).to be > 1 }
    end

    # A slime is weak, a goblin is quick, an orc is strong.
    it "runs from weakest to strongest" do
      expect(Species::Slime.hit_points).to be < Species::Goblin.hit_points
      expect(Species::Goblin.hit_points).to be < Species::Orc.hit_points

      expect(Species::Slime.experience).to be < Species::Goblin.experience
      expect(Species::Goblin.experience).to be < Species::Orc.experience

      expect(Species::Goblin.attributes.dexterity).to be > Species::Orc.attributes.dexterity
      expect(Species::Orc.attributes.strength).to be > Species::Goblin.attributes.strength
    end
  end
end
