require "../../spec_helper"

Spectator.describe "running from the keyboard" do
  alias Monster = Roguelike::Monster
  alias Pending = Roguelike::Ui::Pending
  alias Species = Roguelike::Species
  alias Terrain = Roguelike::Terrain

  # A corridor running east from a staircase, with a passage going north at
  # column 8.
  SIDE = [
    "###############",
    "########.######",
    "#<............#",
    "###############",
  ]

  # A run on `SIDE` with the character on the up staircase.
  def walking(lines : Array(String) = SIDE) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("run", lines)
    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"run" => floor}),
      Roguelike::Player.new("run", *Roguelike::Game.entrance(floor),
        hit_points: 40)), 60, 20
  end

  describe "G" do
    it "waits for a direction" do
      run = walking

      run.press "G"

      expect(run.play.pending).to eq Pending::Run
      expect(run.said).to contain "Run which way?"
      expect(run.at).to eq({1, 2})
    end

    it "walks the direction that is pressed next" do
      run = walking

      run.press "G", "l"

      expect(run.play.pending).to be_nil
      expect(run.at).to eq({8, 2})
    end

    # Every direction is an answer, so there is nothing to choose between and
    # nothing is lit up. `o` and `c` light up the doors they would act on.
    it "lights up no square while it waits" do
      run = walking

      run.press "G"

      expect(run.map.highlights).to be_empty
    end

    it "takes the whole walk in one press" do
      run = walking
      before = run.turn

      run.press "G", "l"

      expect(run.turn).to eq before + 7
    end

    it "forgets the walk on Escape" do
      run = walking

      run.press "G"
      run.press "Escape"
      run.press "l"

      expect(run.play.pending).to be_nil
      expect(run.at).to eq({2, 2})
    end

    it "moves the camera to where the walk ended" do
      run = walking ["#" * 90, "#<" + ("." * 87) + "#", "#" * 90]

      run.press "G", "l"

      expect(run.at[0]).to be > 40
      expect(run.map.screen_of *run.at).not_to be_nil
    end

    it "draws the character where the walk ended" do
      run = walking

      run.press "G", "l"

      spot = run.map.screen_of *run.at
      raise "the character is off the screen" unless spot

      expect(run.rows[spot[1]][spot[0]]).to eq '@'
    end

    # The examine cursor takes a movement key before the character does, so a
    # walk started while it is up would move the cursor instead.
    it "walks rather than moving the examine cursor" do
      run = walking

      run.press "x"
      run.press "G", "l"

      expect(run.at).to eq({8, 2})
    end

    it "says why a walk that goes nowhere went nowhere" do
      run = walking

      run.press "G", "k"

      expect(run.at).to eq({1, 2})
      expect(run.said).to eq "The granite blocks your way."
    end

    it "stops in front of a creature without swinging at it" do
      run = walking
      run.game.floor.place Monster.new(Species::Goblin, 2, 2, "band-one",
        hit_points: 30)
      run.play.refresh

      run.press "G", "l"

      expect(run.at).to eq({1, 2})
      expect(run.game.floor.monster(2, 2).try &.hit_points).to eq 30
    end
  end
end
