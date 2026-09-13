require "../spec_helper"

Spectator.describe "monsters on a floor" do
  alias Floor = Roguelike::Floor
  alias Monster = Roguelike::Monster
  alias Species = Roguelike::Species
  alias Terrain = Roguelike::Terrain

  ROOM = ["#####", "#...#", "#...#", "#####"]

  def spot(lines : Array(String) = ROOM) : Floor
    Floor.parse "room", lines
  end

  describe "read off a floor file" do
    it "stands on the square its mark is on" do
      floor = spot ["#####", "#.g.#", "#####"]

      expect(floor.monster(2, 1).try &.species).to eq Species::Goblin
      expect(floor.monster? 2, 1).to be_true
      expect(floor.monster 1, 1).to be_nil
    end

    # A mark that is not terrain does not say what the square is made of, so
    # the squares beside it do.
    it "stands on the same floor as the squares beside it" do
      stone = spot ["#####", "#.o.#", "#####"]
      dirt = spot ["#####", "#,j,#", "#####"]

      expect(stone.terrain 2, 1).to eq Terrain::StoneFloor
      expect(dirt.terrain 2, 1).to eq Terrain::DirtFloor
    end

    it "writes the plain terrain back out" do
      expect(spot(["#####", "#,j,#", "#####"]).to_map).to eq ["#####", "#,,,#", "#####"]
    end

    it "reads one of each" do
      floor = spot ["#######", "#.j.g.#", "#..o..#", "#######"]

      expect(floor.monsters.size).to eq 3
      expect(floor.monster(2, 1).try &.species).to eq Species::Slime
      expect(floor.monster(4, 1).try &.species).to eq Species::Goblin
      expect(floor.monster(3, 2).try &.species).to eq Species::Orc
    end

    # Each in a band of one. A generator will put several in one band.
    it "puts each in a band of its own" do
      floor = spot ["#######", "#.j.g.#", "#..o..#", "#######"]
      bands = [] of String

      floor.each_monster { |_column, _row, creature| bands << creature.band }

      expect(bands.uniq.size).to eq 3
      expect(floor.bands.size).to eq 3
      bands.each { |id| expect(floor.band id).not_to be_nil }
    end
  end

  describe "#place" do
    it "puts a monster on an empty square" do
      floor = spot

      expect(floor.place Monster.new(Species::Orc, 2, 1, "band")).to be_true
      expect(floor.monster(2, 1).try &.species).to eq Species::Orc
    end

    it "records the band it names" do
      floor = spot
      floor.place Monster.new(Species::Orc, 2, 1, "band")

      expect(floor.band("band").try &.id).to eq "band"
    end

    # One square holds one creature.
    it "refuses a square something is already standing on" do
      floor = spot
      floor.place Monster.new(Species::Orc, 2, 1, "one")

      expect(floor.place Monster.new(Species::Goblin, 2, 1, "two")).to be_false
      expect(floor.monster(2, 1).try &.species).to eq Species::Orc
    end

    it "refuses a square off the floor" do
      floor = spot

      expect(floor.place Monster.new(Species::Orc, 99, 99, "band")).to be_false
    end
  end

  describe "#remove" do
    it "takes a monster off and answers it" do
      floor = spot ["#####", "#.g.#", "#####"]

      expect(floor.remove(2, 1).try &.species).to eq Species::Goblin
      expect(floor.monster 2, 1).to be_nil
    end

    it "answers nothing for an empty square" do
      expect(spot.remove(1, 1)).to be_nil
    end
  end

  describe "#walk" do
    # The floor's own table and the monster's own position stay in step.
    it "moves a monster and keeps both records in step" do
      floor = spot ["#####", "#.g.#", "#####"]

      expect(floor.walk({2, 1}, {3, 1})).to be_true
      expect(floor.monster 2, 1).to be_nil
      expect(floor.monster(3, 1).try &.at).to eq({3, 1})
    end

    it "refuses to move onto another creature" do
      floor = spot ["#####", "#gg.#", "#####"]

      expect(floor.walk({1, 1}, {2, 1})).to be_false
      expect(floor.monster(1, 1).try &.at).to eq({1, 1})
    end

    it "refuses to move off the floor" do
      floor = spot ["#####", "#.g.#", "#####"]

      expect(floor.walk({2, 1}, {99, 99})).to be_false
    end

    it "refuses to move an empty square" do
      expect(spot.walk({1, 1}, {2, 1})).to be_false
    end
  end

  describe "serialization" do
    it "round-trips a floor with one of each" do
      floor = spot ["#######", "#.j.g.#", "#..o..#", "#######"]
      floor.monster(2, 1).try &.hurt 2

      again = Floor.from_json floor.to_json

      expect(again).to eq floor
      expect(again.monsters.size).to eq 3
      expect(again.bands.size).to eq 3
      expect(again.monster(2, 1).try &.hit_points).to eq Species::Slime.hit_points - 2
      expect(again.monster(3, 2).try &.species).to eq Species::Orc
    end

    it "keeps each band's faction" do
      floor = spot ["#####", "#.g.#", "#####"]
      again = Floor.from_json floor.to_json

      expect(again.bands).to eq floor.bands
    end
  end

  describe "on the shipped floor" do
    it "puts one of every species down" do
      floor = Roguelike::Floors.proving_ground
      found = [] of Species

      floor.each_monster { |_column, _row, creature| found << creature.species }

      expect(found.to_set).to eq Species.values.to_set
    end

    it "stands each of them on ground they could walk on" do
      floor = Roguelike::Floors.proving_ground

      floor.each_monster do |column, row, _creature|
        expect(floor.passable? column, row).to be_true
      end
    end

    it "gives each of them a band the floor knows" do
      floor = Roguelike::Floors.proving_ground

      floor.each_monster do |_column, _row, creature|
        expect(floor.band creature.band).not_to be_nil
      end
    end
  end
end
