require "../../spec_helper"

Spectator.describe Roguelike::Ui::NearbyPane do
  alias Floor = Roguelike::Floor
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias NearbyPane = Roguelike::Ui::NearbyPane
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World

  # One room with the character on the up staircase in the middle.
  #
  # The sconce on the left wall is what a fixture example stands beside. The
  # room runs from column 1 to column 9.
  ROOM = [
    "###########",
    "#.........#",
    "#.........#",
    "#....<....#",
    "#.........#",
    "#.........#",
    "###########",
  ]

  # Where the character stands.
  HERE = {5, 3}

  # A run on the room, lit unless *dark*.
  def room(dark : Bool = false, at : {Int32, Int32} = HERE) : Playing::Run
    floor = Floor.parse "room", ROOM
    Playing.daylight floor unless dark

    player = Player.new floor.id, *at
    player.inventory.add Playing.torch if dark

    Playing.open Roguelike::Game.new(
      World.new(Playing::SEED, {floor.id => floor}), player)
  end

  # What the "Here" section says, row by row.
  def underfoot(run : Playing::Run) : Array(String)
    run.nearby.here.children.compact_map { |child| child.as?(Roguelike::Ui::Widgets::Label).try &.text }
  end

  # What the "Seen" section says, row by row.
  def in_sight(run : Playing::Run) : Array(String)
    run.nearby.seen.children.compact_map { |child| child.as?(Roguelike::Ui::Widgets::Label).try &.text }
  end

  describe "Here" do
    it "names the staircase the character stands on" do
      run = room

      expect(underfoot run).to contain "staircase up"
    end

    it "says nothing on a bare floor" do
      run = room at: {2, 2}

      expect(underfoot run).to eq [NearbyPane::NOTHING]
    end

    it "lists what is lying on the square" do
      run = room
      run.game.floor.drop HERE[0], HERE[1], Item.new(Kind::ShortSword)
      run.play.refresh

      expect(underfoot run).to contain "a short sword"
    end

    it "lists a whole pile" do
      run = room
      run.game.floor.drop HERE[0], HERE[1], Item.new(Kind::Dagger)
      run.game.floor.drop HERE[0], HERE[1], Item.new(Kind::Cap)
      run.play.refresh

      expect(underfoot run).to contain "a dagger"
      expect(underfoot run).to contain "a cap"
    end

    it "names a fixture on the square" do
      floor = Playing.daylight Floor.parse("sconce", [
        "#####",
        "#...#",
        "#|..#",
        "#..<#",
        "#####",
      ])
      run = Playing.open Roguelike::Game.new(
        World.new(Playing::SEED, {floor.id => floor}),
        Player.new(floor.id, 1, 2))

      expect(underfoot(run).first).to contain "sconce"
    end

    it "says how many were left out of a deep pile" do
      run = room
      12.times { run.game.floor.drop HERE[0], HERE[1], Item.new(Kind::Dagger) }
      run.play.refresh

      expect(underfoot(run).size).to eq NearbyPane::MOST_HERE
      expect(underfoot(run).last).to contain "more"
    end
  end

  describe "Seen" do
    it "says nothing in an empty room" do
      run = room

      expect(in_sight run).to eq [NearbyPane::NOTHING]
    end

    it "names a creature the character can see" do
      run = room
      run.game.floor.place Monster.new(Species::Goblin, 8, 3, "band-one")
      run.play.refresh

      expect(in_sight run).to contain "goblin"
    end

    it "names an item the character can see" do
      run = room
      run.game.floor.drop 8, 3, Item.new(Kind::LongSword)
      run.play.refresh

      expect(in_sight run).to contain "a long sword"
    end

    it "leaves out what is on the character's own square" do
      run = room
      run.game.floor.drop HERE[0], HERE[1], Item.new(Kind::LongSword)
      run.play.refresh

      expect(underfoot run).to contain "a long sword"
      expect(in_sight run).to eq [NearbyPane::NOTHING]
    end

    it "puts creatures before items" do
      run = room
      run.game.floor.drop 6, 3, Item.new(Kind::LongSword)
      run.game.floor.place Monster.new(Species::Goblin, 8, 3, "band-one")
      run.play.refresh

      expect(in_sight run).to eq ["goblin", "a long sword"]
    end

    it "puts the nearest first" do
      run = room
      run.game.floor.drop 8, 3, Item.new(Kind::LongSword)
      run.game.floor.drop 6, 3, Item.new(Kind::Dagger)
      run.play.refresh

      expect(in_sight run).to eq ["a dagger", "a long sword"]
    end

    it "says how many were left out" do
      run = room
      run.nearby.budget = 6
      8.times { |index| run.game.floor.drop 1 + index, 1, Item.new(Kind::Dagger) }
      run.play.refresh

      expect(in_sight(run).size).to be <= 6
      expect(in_sight(run).last).to contain "more"
    end

    # This is what separates the pane from the map. The map draws what was
    # last seen. This says what is seen.
    it "drops an item the character has walked away from the light of" do
      run = room dark: true
      run.game.floor.drop 8, 3, Item.new(Kind::LongSword)
      run.play.refresh
      expect(in_sight run).to contain "a long sword"

      # Put the torch out. The sword is remembered and no longer seen.
      run.press "a"

      expect(run.map.knowledge.try &.seen? 8, 3).to be_true
      expect(in_sight run).to eq [NearbyPane::NOTHING]
    end

    it "drops a creature that has walked out of sight" do
      run = room
      creature = Monster.new Species::Goblin, 8, 3, "band-one"
      run.game.floor.place creature
      run.play.refresh
      expect(in_sight run).to contain "goblin"

      run.game.floor.remove 8, 3
      run.play.refresh

      expect(in_sight run).to eq [NearbyPane::NOTHING]
    end
  end

  describe "the row budget" do
    it "shrinks with the height of the screen" do
      tall = Roguelike::Ui::Play.nearby_budget 60
      short = Roguelike::Ui::Play.nearby_budget 24

      expect(tall).to be > short
    end

    it "never goes below one row" do
      expect(Roguelike::Ui::Play.nearby_budget 16).to be >= 1
    end
  end
end
