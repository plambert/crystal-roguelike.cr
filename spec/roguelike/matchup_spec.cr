require "../spec_helper"

Spectator.describe Roguelike::Trial::Matchup do
  alias Matchup = Roguelike::Trial::Matchup
  alias Species = Roguelike::Species

  # Small, because a spec checks the rules and the command line takes the
  # measurement.
  FIGHTS = 200

  let(:first) { Matchup::KITS.first }
  let(:last) { Matchup::KITS.last }

  describe "KITS" do
    it "holds one kit for each of five depths" do
      expect(Matchup::KITS.map(&.depth)).to eq [1, 2, 3, 4, 5]
    end

    it "readies every piece of gear" do
      Matchup::KITS.each do |kit|
        player = kit.character

        expect(player.wielded).not_to be_nil
        expect(player.level).to eq kit.level
        expect(player.worn.size).to eq kit.gear.count(&.kind.item_class.armor?)
      end
    end

    it "raises armor class and hit points with the depth" do
      players = Matchup::KITS.map &.character
      armor = players.map &.armor_class
      health = players.map &.max_hit_points

      expect(armor).to eq armor.sort
      expect(health).to eq health.sort
    end
  end

  describe ".fight" do
    it "ends, for every species and every kit" do
      Matchup.opponents.each do |species|
        Matchup::KITS.each do |kit|
          result = Matchup.fight kit, species, Roguelike::Rng.new(7_u64)

          expect(result.turns).to be_between(1, Matchup::LIMIT)
        end
      end
    end

    it "leaves the character at most as hurt as they were" do
      result = Matchup.fight first, Species::Orc, Roguelike::Rng.new(7_u64)

      expect(result.damage).to be_between(0, first.character.max_hit_points)
    end
  end

  describe ".cell" do
    it "counts the fights it was asked for" do
      cell = Matchup.cell first, Species::Goblin, FIGHTS

      expect(cell.fights).to eq FIGHTS
      expect(cell.wins).to be <= FIGHTS
    end

    it "gives the same answer for the same seed" do
      once = Matchup.cell first, Species::Goblin, FIGHTS, 11_u64
      again = Matchup.cell first, Species::Goblin, FIGHTS, 11_u64

      expect(again).to eq once
    end

    it "gives another answer for another seed" do
      once = Matchup.cell first, Species::Goblin, FIGHTS, 11_u64
      other = Matchup.cell first, Species::Goblin, FIGHTS, 12_u64

      expect(other).not_to eq once
    end

    it "is won more often by a stronger kit" do
      Matchup.opponents.each do |species|
        weak = Matchup.cell first, species, FIGHTS
        strong = Matchup.cell last, species, FIGHTS

        expect(strong.win_rate).to be >= weak.win_rate
        expect(strong.mean_damage).to be <= weak.mean_damage
      end
    end
  end

  describe ".play" do
    it "has a row for every species and a column for every kit" do
      table = Matchup.play 5

      expect(table.opponents).to eq Species.values
      expect(table.cells.size).to eq Species.values.size
      expect(table.cells.map(&.size).uniq!).to eq [Matchup::KITS.size]
    end

    it "prints the same table for the same seed" do
      expect(Matchup.play(20, 3_u64).to_s).to eq Matchup.play(20, 3_u64).to_s
    end

    it "names every species and every kit" do
      text = Matchup.play(5).to_s

      Species.values.each { |species| expect(text).to contain species.label }
      Matchup::KITS.each { |kit| expect(text).to contain kit.heading }
    end
  end
end
