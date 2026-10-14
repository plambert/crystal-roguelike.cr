require "../../spec_helper"

Spectator.describe "a map pane nobody is looking at" do
  alias Ui = Roguelike::Ui

  # A dark hall. The character stands in it with a lit torch, so every
  # square in sight is under a flame.
  IDLE_HALL = [
    "####################",
    "#..................#",
    "#.<................#",
    "#..................#",
    "####################",
  ]

  # How many ticks the flames take to go round every kept drawing once.
  LOOP = Ui::MapPane::FRAMES * Ui::Flicker::HOLD

  def burning : Playing::Run
    floor = Roguelike::Floor.parse "hall", IDLE_HALL
    player = Roguelike::Player.new "hall", *Roguelike::Game.entrance(floor)
    player.inventory.add Playing.torch

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}), player), 40, 16
  end

  # *run* with the window out of focus and one frame drawn.
  def idle : Playing::Run
    run = burning
    run.map.idle = true
    run.render
    run
  end

  # Moves the flames on *times* ticks and draws a frame after each.
  def tick(run : Playing::Run, times : Int32 = 1) : Nil
    times.times do
      run.play.waver
      run.render
    end
  end

  # Every cell on the screen, with the style it is drawn in.
  def drawn(run : Playing::Run) : Array({String, TermBuf::Style})
    buffer = run.buffer
    cells = [] of {String, TermBuf::Style}

    buffer.height.times do |row|
      buffer.width.times do |column|
        found = buffer.hit column, row
        cells << {found.text, buffer.styles[found.cell.style]} if found
      end
    end

    cells
  end

  it "works every square out on every frame while the window has the focus" do
    run = burning
    tick run, LOOP

    before = run.map.worked
    tick run, LOOP

    expect(run.map.worked).to be > before
  end

  it "works no square out once it keeps every shift of the flames" do
    run = idle
    tick run, LOOP - 1

    before = run.map.worked
    tick run, LOOP * 2

    expect(run.map.kept).to eq Ui::MapPane::FRAMES
    expect(run.map.worked).to eq before
  end

  it "keeps the flames moving" do
    run = idle
    shown = Set(Array({String, TermBuf::Style})).new

    LOOP.times do
      tick run
      shown << drawn(run)
    end

    expect(shown.size).to be > 1
  end

  it "draws a kept shift the way a pane with the focus works it out" do
    run = idle
    tick run, LOOP

    looking = burning
    expect(drawn(run)).to eq drawn(looking)
  end

  it "works the squares out again after any event" do
    run = idle
    tick run, LOOP

    run.session.send TermBuf::Input::Events::Timer.new(0xdead_u64)
    expect(run.map.kept).to eq 0

    before = run.map.worked
    tick run
    expect(run.map.worked).to be > before
  end

  it "keeps nothing once the window has the focus again" do
    run = idle
    tick run, LOOP

    run.session.send TermBuf::Events::Focus.new(true)
    expect(run.map.idle?).to be_false
    expect(run.map.kept).to eq 0

    before = run.map.worked
    tick run
    expect(run.map.worked).to be > before
  end

  it "keeps nothing when the flames do not move" do
    run = burning
    run.play.flicker.burning = false
    run.map.idle = true
    run.render

    before = run.map.worked
    tick run

    expect(run.map.kept).to eq 0
    expect(run.map.worked).to be > before
  end
end
