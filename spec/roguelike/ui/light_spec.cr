require "../../spec_helper"

Spectator.describe "light" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Terrain = Roguelike::Terrain
  alias Ui = Roguelike::Ui

  # A dark room with a sconce in its north wall. The character starts on the
  # up staircase in the middle, carrying *items*.
  ROOM = [
    "#########",
    "#...|...#",
    "#.......#",
    "#...<...#",
    "#.......#",
    "#########",
  ]

  # A dark corridor with a glowing room at the end of it, behind an open
  # doorway. The character starts at the dark end.
  LOOKING = [
    "###########",
    "#<...'****#",
    "###########",
  ]

  def dark(items : Array(Item) = [] of Item,
           lines : Array(String) = ROOM) : Playing::Run
    floor = Roguelike::Floor.parse "dark", lines
    player = Roguelike::Player.new "dark", *Roguelike::Game.entrance(floor)
    items.each { |item| player.inventory.add item }

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"dark" => floor}), player), 40, 16
  end

  describe "a dungeon with nothing alight" do
    # A person in the dark knows where their own feet are and nothing else.
    it "shows the character and nothing else" do
      run = dark

      expect(run.game.sight.size).to eq 1
      expect(run.rows[0, 5]).to eq ["", "", "", "    @", ""]
    end
  end

  describe "a" do
    it "says so when there is nothing to light" do
      run = dark(Array(Item).new, ["###", "#<#", "###"])

      run.press "a"

      expect(run.said).to contain "nothing to light"
    end

    it "lights a carried torch without asking" do
      run = dark [Item.new Kind::Torch]

      run.press "a"

      expect(run.said).to contain "You light"
      expect(run.game.player.inventory['a'].try &.lit?).to be_true
      expect(run.game.sight.size).to be > 1
    end

    it "puts the same torch out again" do
      run = dark [Item.new Kind::Torch]

      run.press "a"
      run.press "a"

      expect(run.said).to contain "You put out"
      expect(run.game.sight.size).to eq 1
    end

    it "takes a turn either way" do
      run = dark [Item.new Kind::Torch]

      run.press "a"
      expect(run.turn).to eq 1

      run.press "a"
      expect(run.turn).to eq 2
    end

    it "refuses a thing that does not burn" do
      run = dark [Item.new Kind::LongSword]

      run.press "a"

      expect(run.said).to contain "nothing to light"
    end

    # Two things to apply is a question. A carried candle and the sconce
    # beside the character are two.
    it "asks which when there is more than one" do
      run = dark [Item.new Kind::Candle]
      run.game.player.move_to 4, 2

      run.press "a"

      expect(run.menu.showing?).to be_true
      expect(run.menu.entries.size).to eq 2
    end

    it "lights the one chosen" do
      run = dark [Item.new Kind::Candle]
      run.game.player.move_to 4, 2

      run.press "a"
      found = run.menu.entries.find &.text.includes?("sconce")
      raise "the menu offers no sconce" unless found
      run.press found.key.to_s

      expect(run.game.floor.fixture(4, 1).try &.lit?).to be_true
      expect(run.game.player.inventory['a'].try &.lit?).to be_false
    end
  end

  describe "a sconce standing on the floor" do
    # It throws light every way rather than half, and one step less far,
    # because the flame is at ankle height.
    FREE = [
      "###########",
      "#.........#",
      "#....|....#",
      "#....<....#",
      "#.........#",
      "###########",
    ]

    it "is bolted to nothing" do
      run = dark(Array(Item).new, FREE)

      expect(run.game.floor.fixture(5, 2).try &.mounted?).to be_false
    end

    it "throws light every way once it is lit" do
      run = dark(Array(Item).new, FREE)
      run.game.player.move_to 5, 3

      run.press "a"

      expect(run.game.can_see?(5, 1)).to be_true
      expect(run.game.can_see?(5, 4)).to be_true
      expect(run.game.can_see?(1, 2)).to be_true
    end

    it "throws one step less than the same sconce on a wall" do
      free = Roguelike::Fixture.new Roguelike::FixtureKind::Sconce, true
      mounted = Roguelike::Fixture.new Roguelike::FixtureKind::Sconce, true,
        Roguelike::Direction::North

      expect(free.light).to eq mounted.light - Roguelike::Fixture::FLOOR_PENALTY
    end
  end

  describe "a sconce bolted to a wall" do
    it "throws light away from the wall and not along it" do
      run = dark
      run.game.player.move_to 4, 2

      run.press "a"

      expect(run.game.can_see?(4, 4)).to be_true
      expect(run.game.can_see?(1, 4)).to be_true
      expect(run.game.can_see?(8, 0)).to be_false
    end
  end

  describe "a wall sconce" do
    # Lighting a sconce reveals the room.
    it "reveals the room when it is lit" do
      run = dark
      run.game.player.move_to 4, 2

      run.press "a"

      expect(run.said).to contain "catches"
      expect(run.game.can_see?(2, 3)).to be_true
      expect(run.game.can_see?(6, 3)).to be_true
    end

    it "goes out again" do
      run = dark
      run.game.player.move_to 4, 2

      run.press "a"
      run.press "a"

      expect(run.game.floor.fixture(4, 1).try &.lit?).to be_false
      expect(run.game.sight.size).to eq 1
    end

    # A fixture stands on an open square, so the character can stand on it
    # and light it from there.
    it "can be lit from the square it stands on" do
      run = dark
      run.game.player.move_to 4, 1

      run.press "a"

      expect(run.said).to contain "catches"
      expect(run.game.floor.fixture(4, 1).try &.lit?).to be_true
    end

    it "is out of reach from across the room" do
      run = dark

      run.press "a"

      expect(run.said).to contain "no sconce beside you"
    end
  end

  describe "a torch on the floor" do
    # Dropping a lit torch and walking away leaves the pool of light behind,
    # and the pool stays visible.
    it "keeps burning where it was dropped" do
      run = dark [Item.new(Kind::Torch, lit: true)]

      run.press "d"
      run.press "a"

      expect(run.game.here.first.lit?).to be_true
      expect(run.game.lights.size).to eq 1
      expect(run.game.lights.first.at).to eq run.at
    end

    it "is still visible from across the room" do
      run = dark [Item.new(Kind::Torch, lit: true)]
      dropped = run.at

      run.press "d"
      run.press "a"
      run.press "h"
      run.press "h"

      expect(run.at).to_not eq dropped
      expect(run.game.can_see?(dropped[0], dropped[1])).to be_true
    end

    it "goes dark when it is picked up and put out" do
      run = dark [Item.new(Kind::Torch, lit: true)]

      run.press "d"
      run.press "a"
      run.press ","
      run.press "a"

      expect(run.game.sight.size).to eq 1
    end
  end

  describe "a room that glows on its own" do
    it "is seen across the dark corridor, doorway and all" do
      run = dark(Array(Item).new, LOOKING)

      expect(run.game.can_see?(5, 1)).to be_true
      expect(run.game.can_see?(7, 1)).to be_true
      expect(run.game.can_see?(2, 1)).to be_false
    end

    it "draws the room and leaves the corridor blank" do
      run = dark(Array(Item).new, LOOKING)

      expect(run.row(1)).to eq " @   '....#"
    end
  end

  # A corridor longer than a torch reaches. The line of sight runs its whole
  # length and the light does not.
  HALL = [
    "###################",
    "#<................#",
    "###################",
  ]

  describe "the map pane" do
    it "draws nothing on an unlit square it has a line to" do
      run = dark([Item.new(Kind::Torch, lit: true)], HALL)
      run.game.floor.drop 15, 1, Item.new Kind::LongSword

      run.play.refresh
      run.render
      expect(run.game.sight.field.includes?(15, 1)).to be_true
      expect(run.row(1)[15]?).to be_nil
    end

    it "draws it once the light reaches it" do
      run = dark([Item.new(Kind::Torch, lit: true)], HALL)
      run.game.floor.drop 4, 1, Item.new Kind::LongSword

      run.play.refresh
      run.render
      expect(run.row(1)[4]).to eq ')'
    end
  end

  describe "drawn" do
    it "draws what it drew last time by torchlight" do
      drawn = dark([Item.new(Kind::Torch, lit: true)]).text

      expect(drawn).to eq Fixture.expected("screen/light-torch.txt", drawn)
    end

    it "draws what it drew last time by a lit sconce" do
      run = dark
      run.game.player.move_to 4, 2
      run.press "a"
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/light-sconce.txt", drawn)
    end
  end
end
