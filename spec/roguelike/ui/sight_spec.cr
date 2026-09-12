require "../../spec_helper"

Spectator.describe "what the character can see" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Terrain = Roguelike::Terrain
  alias Ui = Roguelike::Ui

  # Two rooms with a shut door between them. The character starts in the left
  # one, beside the door, so `o` reaches it.
  ROOMS = [
    "#########",
    "#...#...#",
    "#..<+.>.#",
    "#...#...#",
    "#########",
  ]

  # A run on *lines*, with the character on the up staircase.
  def shown(lines : Array(String) = ROOMS) : Playing::Run
    floor = Roguelike::Floor.parse "rooms", lines
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"rooms" => floor}),
      Roguelike::Player.new("rooms", *Roguelike::Game.entrance(floor))

    Playing.open game, 40, 16
  end

  describe "the map pane" do
    # A row is written with trailing blanks trimmed, so a row that ends at
    # the shut door ends there in the text too.
    it "draws the room the character is in and stops at the shut door" do
      run = shown

      expect(run.rows[0, 5]).to eq ["#####", "#...#", "#..@+", "#...#", "#####"]
    end

    it "shows the room behind the door once the door is open" do
      run = shown

      run.press "o"

      expect(run.row(2)).to eq "#..@'.>.#"
    end

    # A field of view is worked out again from where the character stands.
    # Standing in the second room, the first room is seen through the doorway
    # and the two wall squares the doorway hides are not.
    it "follows the character" do
      run = shown

      run.press "o"
      run.press "l"
      run.press "l"

      expect(run.at).to eq({5, 2})
      expect(run.rows[0, 5]).to eq ["##  #####", "#...#...#", "#..<'@>.#",
                                    "#...#...#", "##  #####"]
    end
  end

  describe "an item out of sight" do
    it "is not drawn" do
      run = shown
      run.game.floor.drop 6, 2, Item.new Kind::LongSword

      run.render
      expect(run.row(2)).to eq "#..@+"
    end

    it "is drawn once it comes into sight" do
      run = shown
      run.game.floor.drop 6, 2, Item.new Kind::LongSword

      run.press "o"

      expect(run.row(2)[6]).to eq ')'
    end
  end

  describe "the examine pane" do
    it "reads a square the character can see" do
      run = shown

      run.hover 2, 2

      expect(run.examine.what.text).to eq "stone floor"
    end

    # The pointer reaches any square. The readout must not, or the whole map
    # could be read with the mouse.
    it "refuses a square the character cannot see" do
      run = shown

      run.hover 6, 2

      expect(run.examine.what.text).to eq Ui::ExaminePane::UNSEEN
      expect(run.examine.detail.text).to be_empty
    end

    it "names the square once it comes into sight" do
      run = shown

      run.press "o"
      run.hover 6, 2

      expect(run.examine.what.text).to eq "staircase down"
    end

    it "says nothing about what lies on a square out of sight" do
      run = shown
      run.game.floor.drop 6, 2, Item.new Kind::LongSword

      run.hover 6, 2

      expect(run.examine.litter.hidden?).to be_true
    end
  end

  describe "Game#sight" do
    it "grows when a door opens" do
      run = shown
      before = run.game.sight.size

      run.press "o"

      expect(run.game.sight.size).to be > before
    end

    it "answers whether one square can be seen from another" do
      run = shown

      expect(run.game.can_see?(3, 2)).to be_true
      expect(run.game.can_see?(6, 2)).to be_false
    end
  end

  describe "a pane with no field of view" do
    # A spec that is not about sight should need to say nothing about sight.
    it "draws every square" do
      pane = Ui::MapPane.new Roguelike::Floors.proving_ground

      expect(pane.sight).to be_nil
      expect(pane.seen?(0, 0)).to be_true
      expect(pane.seen?(70, 26)).to be_true
    end

    it "draws only what is seen once one is set" do
      floor = Roguelike::Floors.proving_ground
      pane = Ui::MapPane.new floor
      pane.sight = Roguelike::FieldOfView.from floor, 6, 5

      expect(pane.seen?(6, 5)).to be_true
      expect(pane.seen?(0, 0)).to be_false
    end

    it "forgets the field of view when the floor changes" do
      floor = Roguelike::Floors.proving_ground
      pane = Ui::MapPane.new floor
      pane.sight = Roguelike::FieldOfView.from floor, 6, 5

      pane.floor = Roguelike::Floor.parse "tiny", "##\n##"

      expect(pane.sight).to be_nil
    end
  end

  describe "drawn" do
    it "draws what it drew last time from the first room" do
      drawn = shown.text

      expect(drawn).to eq Fixture.expected("screen/sight-room.txt", drawn)
    end

    it "draws what it drew last time with the door open" do
      run = shown
      run.press "o"
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/sight-open.txt", drawn)
    end
  end
end
