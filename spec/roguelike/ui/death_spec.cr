require "../../spec_helper"

Spectator.describe "the character dying on the screen" do
  alias Monster = Roguelike::Monster
  alias Outcome = Roguelike::Outcome
  alias Species = Roguelike::Species

  # One lit room with the character on the up staircase and an orc beside
  # them. The character has one hit point, so the orc needs one landed swing.
  ROOM = [
    "#######",
    "#..o..#",
    "#..<..#",
    "#######",
  ]

  # How many swings a spec takes before it gives up waiting for one to land.
  SWINGS = 200

  def dying : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
    player = Roguelike::Player.new floor.id, *Roguelike::Game.entrance(floor),
      hit_points: 1

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {floor.id => floor}), player), 40, 16
  end

  # Walks into the orc until the character is dead.
  def killed : Playing::Run
    run = dying

    SWINGS.times do
      break if run.game.over?

      run.press "k"
    end

    run
  end

  it "ends the run as a death" do
    run = killed

    expect(run.game.outcome).to eq Outcome::Died
    expect(run.game.player.alive?).to be_false
  end

  it "puts the death screen up" do
    run = killed

    expect(run.placard.showing?).to be_true
    expect(run.placard.heading).to eq "You died"
    expect(run.placard.lines.first).to eq "Killed by an orc."
  end

  it "finishes the run when the key is pressed" do
    run = killed
    expect(run.finished?).to be_false

    run.press "n"

    expect(run.finished?).to be_true
    expect(run.play.again?).to be_false
  end

  it "asks for another run when the key is pressed" do
    run = killed

    run.press "y"

    expect(run.finished?).to be_true
    expect(run.play.again?).to be_true
  end

  it "puts the death screen up once" do
    run = killed
    run.press "n"

    # The screen is answered and gone. A later refresh does not bring it
    # back.
    run.play.refresh

    expect(run.placard.showing?).to be_false
  end

  it "leaves the last thing that happened in the log" do
    run = killed

    expect(run.log.last).to eq "You die..."
  end
end
