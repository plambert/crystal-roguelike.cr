require "../../spec_helper"

Spectator.describe "the camera after a staircase" do
  alias Terrain = Roguelike::Terrain

  # Floor 1 of this seed is 107 by 107 and floor 2 is 251 by 168. The up
  # staircase of floor 2 is near its bottom right corner, so in a large window
  # the camera is stopped by two edges.
  SEED = 3_u64

  # A run on floor 1 of `SEED`, standing on the down staircase, with a clock
  # a spec fires by hand.
  def on_the_stairs(columns : Int32 = 80, rows : Int32 = 24) : Playing::Run
    game = Roguelike::Game.dug Roguelike::Rng.new(SEED)
    stairs = game.floor.find Terrain::StairsDown
    raise "no staircase down" unless stairs

    game.player.move_to stairs
    run = Playing.open game, columns, rows, clock: true
    run.clear_monsters
    run
  end

  # Where the camera stands with the character in the middle of the window.
  def centred(run : Playing::Run) : {Int32, Int32}
    held = run.map.camera
    run.map.center_on *run.at
    found = run.map.camera
    run.map.camera = held
    found
  end

  it "puts the character in the middle of the window on the floor below" do
    run = on_the_stairs
    above = run.game.floor

    run.press ">"

    floor = run.game.floor
    expect(floor).not_to be above
    expect({floor.columns, floor.rows}).not_to eq({above.columns, above.rows})
    expect(run.map.floor).to be floor
    expect(run.map.camera).not_to eq({0, 0})
    expect(run.map.camera).to eq centred(run)
    expect(run.play.panning?).to be_false
    expect(run.armed).to be_empty
  end

  it "stops at the edges of the floor" do
    run = on_the_stairs 120, 40

    run.press ">"

    room = run.map.grid.viewport_size
    floor = run.game.floor
    wanted = {run.at[0] - room[0] // 2, run.at[1] - room[1] // 2}
    edges = {floor.columns - room[0], floor.rows - room[1]}
    expect(wanted[0]).to be > edges[0]
    expect(wanted[1]).to be > edges[1]
    expect(run.map.camera).to eq edges
  end

  it "puts the character in the middle of the window on the floor above" do
    run = on_the_stairs
    run.press ">"
    while run.pager.holding?
      run.press "Enter"
    end

    run.press "<"

    expect(Roguelike::World.depth run.game.floor.id).to eq 1
    expect(run.map.camera).to eq centred(run)
    expect(run.play.panning?).to be_false
  end
end
