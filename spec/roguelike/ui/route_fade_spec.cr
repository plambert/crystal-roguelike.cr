require "../../spec_helper"

Spectator.describe "a drawn route fading" do
  alias Game = Roguelike::Game

  HALL_LINES = [
    "###############",
    "#<...........>#",
    "###############",
  ]

  # A run on the hall with timers to fire by hand and nothing else alive.
  def hall : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL_LINES)
    run = Playing.open Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}),
      Roguelike::Player.new("hall", *Game.entrance(floor), hit_points: 40)),
      60, 20, clock: true
    run.clear_monsters
    run
  end

  # Where *spot* of the floor is drawn.
  def on_screen(run : Playing::Run, spot : {Int32, Int32}) : {Int32, Int32}
    run.map.screen_of(spot[0], spot[1]) || raise "#{spot} is not on the screen"
  end

  it "is a few seconds" do
    expect(Roguelike::Ui::Play::ROUTE_FADE).to be >= 2.seconds
    expect(Roguelike::Ui::Play::ROUTE_FADE).to be <= 10.seconds
  end

  it "takes the route off when the timer fires" do
    run = hall
    spot = on_screen run, {10, 1}

    run.click spot[0], spot[1]
    expect(run.map.highlighted? 10, 1).to be_true
    expect(run.armed.size).to eq 1

    run.tick
    run.render

    expect(run.map.highlights).to be_empty
    expect(run.turn).to eq 0
  end

  it "waits a full window after a second click elsewhere" do
    run = hall
    first = on_screen run, {10, 1}
    second = on_screen run, {5, 1}

    run.click first[0], first[1]
    run.click second[0], second[1]

    expect(run.armed.size).to eq 1
    expect(run.map.highlighted? 5, 1).to be_true
  end

  it "still walks the route on a second click on the same square" do
    run = hall
    spot = on_screen run, {10, 1}

    run.click spot[0], spot[1]
    run.click spot[0], spot[1]

    run.run_timers
    run.render

    expect(run.at).to eq({10, 1})
    expect(run.armed).to be_empty
  end

  it "does nothing when a turn has already taken the route off" do
    run = hall
    spot = on_screen run, {10, 1}

    run.click spot[0], spot[1]
    run.press "l"
    run.render
    expect(run.map.highlights).to be_empty

    run.run_timers
    expect(run.at).to eq({2, 1})
  end

  it "leaves the route that > put up behind a held page alone" do
    run = hall
    spot = on_screen run, {10, 1}

    run.click spot[0], spot[1]
    run.press ">"
    run.run_timers
    run.render

    expect(run.map.highlighted? 13, 1).to be_true
  end
end
