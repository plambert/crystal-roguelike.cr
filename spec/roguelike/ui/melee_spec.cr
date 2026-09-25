require "../../spec_helper"

# A run that keeps every action that reached the one entry point.
#
# A movement key sends one of two verbs. Which one it sent is the subject
# here, and the state the game ends in does not show it. Both verbs leave the
# character where they were.
class Bumping < Roguelike::Game
  @[JSON::Field(ignore: true)]
  getter taken : Array(Roguelike::Action) = [] of Roguelike::Action

  def perform(action : Roguelike::Action) : Roguelike::Verdict
    @taken << action
    super
  end
end

Spectator.describe "walking into a creature" do
  alias Action = Roguelike::Action
  alias Monster = Roguelike::Monster
  alias Species = Roguelike::Species

  # One lit room with the character in the middle.
  ROOM = [
    "#######",
    "#.....#",
    "#.....#",
    "#..<..#",
    "#.....#",
    "#.....#",
    "#######",
  ]

  # Where the character stands.
  HERE = {3, 3}

  # The square east of the character, where the goblin stands.
  THERE = {4, 3}

  # A run on `ROOM` with a goblin one square east.
  def beset : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
    game = Bumping.new(
      Roguelike::World.new(Playing::SEED, {"room" => floor}),
      Roguelike::Player.new("room", *HERE, hit_points: 40))
    floor.place Monster.new(Species::Goblin, THERE[0], THERE[1], "band-one")

    Playing.open game
  end

  # What the keys pressed so far sent to `Game#perform`.
  def sent(run : Playing::Run) : Array(Roguelike::Action)
    run.game.as(Bumping).taken
  end

  it "sends a swing when the character can see what they walk into" do
    run = beset

    run.press "l"

    expect(sent(run).map &.class).to eq [Action::MeleeAttack]
    expect(sent(run).first.as(Action::MeleeAttack).target).to eq THERE
    expect(run.at).to eq HERE
  end

  it "sends a step when the character cannot see what they walk into" do
    run = beset
    run.game.player.blind 5

    run.press "l"

    expect(sent(run).map &.class).to eq [Action::Move]
    expect(run.at).to eq HERE
  end

  it "sends a step into an empty square" do
    run = beset

    run.press "h"

    expect(sent(run).map &.class).to eq [Action::Move]
    expect(run.at).to eq({2, 3})
  end
end
