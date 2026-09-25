require "../../spec_helper"

Spectator.describe "resting from the keyboard" do
  alias Game = Roguelike::Game
  alias Monster = Roguelike::Monster
  alias Pending = Roguelike::Ui::Pending
  alias Species = Roguelike::Species

  # A hall with the character at the west end.
  HALL = [
    "###############",
    "#<............#",
    "###############",
  ]

  # A run on `HALL` with the character *down* hit points.
  #
  # *clock* gives the application timers a spec fires by hand. Without one
  # the whole rest happens inside the press that starts it.
  def resting(down : Int32 = 6, clock : Bool = false) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)
    run = Playing.open Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}),
      Roguelike::Player.new("hall", *Game.entrance(floor))),
      60, 20, clock: clock
    run.clear_monsters
    run.game.player.hurt down
    run.play.refresh

    run
  end

  describe "R" do
    it "rests until the character is healed" do
      run = resting

      run.press "R"

      expect(run.game.player.hit_points).to eq run.game.player.max_hit_points
    end

    it "takes one turn of the run for each turn of rest" do
      run = resting
      before = run.turn

      run.press "R"

      expect(run.turn).to be > before
    end

    it "writes nothing to the log" do
      run = resting
      before = run.log.size

      run.press "R"

      expect(run.log.size).to eq before
    end

    it "says why a character at full health cannot rest" do
      run = resting 0
      before = run.turn

      run.press "R"

      expect(run.said).to eq "You are already as well as you are going to get."
      expect(run.turn).to eq before
    end

    it "says why a character who can see a creature cannot rest" do
      run = resting
      run.game.floor.place Monster.new(Species::Goblin, 8, 1, "band-one")
      before = run.turn

      run.press "R"

      expect(run.said).to eq "You cannot rest with a creature in sight."
      expect(run.turn).to eq before
    end

    # `.` does the same. A key that is waiting for a direction takes the next
    # key back, whatever that key usually does.
    it "gives up a command waiting for a direction" do
      run = resting

      run.press "G"
      run.press "R"

      expect(run.play.pending).to be_nil
      expect(run.play.resting?).to be_false
    end
  end

  describe "a rest drawn a turn at a time" do
    it "takes one turn and then waits" do
      run = resting 6, clock: true
      before = run.turn

      run.press "R"

      expect(run.turn).to eq before + 1
      expect(run.play.resting?).to be_true
    end

    it "takes one more turn for each tick of the clock" do
      run = resting 6, clock: true
      before = run.turn

      run.press "R"
      run.tick
      run.tick

      expect(run.turn).to eq before + 3
    end

    it "runs to full health when the clock is left to run" do
      run = resting 6, clock: true

      run.press "R"
      run.run_timers

      expect(run.game.player.hit_points).to eq run.game.player.max_hit_points
      expect(run.play.resting?).to be_false
    end

    it "arms nothing more once it has stopped" do
      run = resting 6, clock: true

      run.press "R"
      run.run_timers

      expect(run.armed).to be_empty
    end
  end

  describe "a key pressed while a rest is going" do
    it "stops the rest" do
      run = resting 6, clock: true

      run.press "R"
      run.tick
      run.press "j"

      expect(run.play.resting?).to be_false
    end

    it "does not do what the key usually does" do
      run = resting 6, clock: true

      run.press "R"
      run.tick
      before = run.turn
      run.press "i"

      expect(run.menu.showing?).to be_false
      expect(run.turn).to eq before
    end

    it "leaves the character short of full health" do
      run = resting 6, clock: true

      run.press "R"
      run.tick
      run.press "j"

      expect(run.game.player.hit_points).to be < run.game.player.max_hit_points
    end
  end

  describe "the help" do
    it "names the key" do
      run = resting
      _match, binding = run.play.bindings.lookup TermBuf::Key.parse("R")

      expect(binding.try &.description).to eq "rest until you are healed"
    end
  end
end
