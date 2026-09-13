require "../../spec_helper"

Spectator.describe "monsters on the screen" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Species = Roguelike::Species
  alias Ui = Roguelike::Ui

  # One lit room with the character on the up staircase.
  ROOM = [
    "#########",
    "#.......#",
    "#.......#",
    "#...<...#",
    "#.......#",
    "#.......#",
    "#########",
  ]

  def shown(lines : Array(String) = ROOM, lit : Bool = true) : Playing::Run
    floor = Roguelike::Floor.parse "room", lines
    Playing.daylight floor if lit

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"room" => floor}),
      Roguelike::Player.new("room", *Roguelike::Game.entrance(floor))), 40, 16
  end

  def drawn_style(run : Playing::Run, x : Int32, y : Int32) : TermBuf::Style
    found = run.buffer.hit x, y
    raise "nothing is drawn at #{x},#{y}" unless found

    run.buffer.styles[found.cell.style]
  end

  describe "drawing" do
    it "draws each species as its own letter" do
      run = shown ["#######", "#.j.g.#", "#<.o..#", "#######"]

      expect(run.row(1)).to eq "#.j.g.#"
      expect(run.row(2)).to eq "#@.o..#"
    end

    it "draws each species in its own colour" do
      run = shown ["#######", "#.j.g.#", "#<.o..#", "#######"]

      colours = [drawn_style(run, 2, 1), drawn_style(run, 4, 1), drawn_style(run, 3, 2)]
      expect(colours.uniq.size).to eq 3
    end

    # A creature draws over what is lying on the square it stands on.
    it "draws over an item on the same square" do
      run = shown ["#######", "#..g..#", "#..<..#", "#######"]
      run.game.floor.drop 3, 1, Item.new Kind::LongSword

      run.play.refresh
      run.render

      expect(run.row(1)[3]).to eq 'g'
    end

    it "draws nothing for a square the character cannot see" do
      run = shown ["#######", "#..#g.#", "#..<..#", "#######"], lit: false

      expect(run.game.can_see_creature?(4, 1)).to be_false
      expect(run.row(1)[4]?).to be_nil
    end

    # A creature on an unlit square with light behind it is a shape.
    it "draws one standing against the light" do
      run = shown ["############", "#..<...g..*#", "############"], lit: false

      expect(run.game.sight.lit?(7, 1)).to be_false
      expect(run.game.can_see_creature?(7, 1)).to be_true
      expect(run.row(1)[7]).to eq 'g'
    end

    it "draws a shape darker than one standing in the light" do
      shape = shown ["############", "#..<...g..*#", "############"], lit: false
      lit = shown ["############", "#..<...g..*#", "############"]

      expect(drawn_style(shape, 7, 1).foreground.green)
        .to be < drawn_style(lit, 7, 1).foreground.green
    end

    # Phase 19 gives `Memory` a creature. Until then a monster is drawn where
    # it is or not at all.
    it "leaves nothing behind on a remembered square" do
      run = shown ["############", "#<.........#", "############"], lit: false
      run.game.floor.place Monster.new(Species::Orc, 9, 1, "band")

      run.play.refresh
      run.render

      expect(run.game.knowledge.seen?(9, 1)).to be_false
      expect(run.row(1)[9]?).to be_nil
    end
  end

  describe "the examine pane" do
    it "names the creature standing there" do
      run = shown ["#######", "#..g..#", "#..<..#", "#######"]

      run.hover 3, 1

      expect(run.examine.what.text).to eq "goblin"
      expect(run.examine.detail.text).to eq Species::Goblin.description
    end

    it "names the creature rather than the terrain under it" do
      run = shown ["#######", "#.,o,.#", "#..<..#", "#######"]

      run.hover 3, 1

      expect(run.game.floor.terrain 3, 1).to eq Roguelike::Terrain::DirtFloor
      expect(run.examine.what.text).to eq "orc"
    end

    it "still names what is lying on the square" do
      run = shown ["#######", "#..g..#", "#..<..#", "#######"]
      run.game.floor.drop 3, 1, Item.new Kind::LongSword

      run.hover 3, 1

      expect(run.examine.what.text).to eq "goblin"
      expect(run.examine.litter.text).to contain "long sword"
    end
  end

  describe "walking into one" do
    # Phase 17 swings at it. Until then it is in the way and nothing else.
    it "is refused with a message" do
      run = shown ["#######", "#..g..#", "#..<..#", "#######"]

      run.press "k"

      expect(run.at).to eq({3, 2})
      expect(run.said).to eq "A goblin is in your way."
    end

    it "takes no turn" do
      run = shown ["#######", "#..g..#", "#..<..#", "#######"]

      run.press "k"

      expect(run.turn).to eq 0
    end

    it "names the creature rather than the ground under it" do
      run = shown ["#######", "#..o..#", "#..<..#", "#######"]

      run.press "k"

      expect(run.said).to eq "An orc is in your way."
    end

    it "leaves the creature where it was" do
      run = shown ["#######", "#..j..#", "#..<..#", "#######"]

      run.press "k"

      expect(run.game.floor.monster(3, 1).try &.species).to eq Species::Slime
    end
  end

  describe "Game#monsters_in_sight" do
    it "answers the ones the character can see" do
      run = shown ["#########", "#.j...g.#", "#...<...#", "#########"]

      expect(run.game.monsters_in_sight.map(&.species).to_set)
        .to eq Set{Species::Slime, Species::Goblin}
    end

    it "leaves out the ones it cannot" do
      run = shown ["#########", "#.j.#.g.#", "#...<...#", "#########"], lit: false

      expect(run.game.monsters_in_sight).to be_empty
    end
  end

  describe "drawn" do
    it "draws what it drew last time with one of each" do
      drawn = shown(["#########", "#.j...g.#", "#...<...#", "#...o...#", "#########"]).text

      expect(drawn).to eq Fixture.expected("screen/monsters.txt", drawn)
    end
  end
end
