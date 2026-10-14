require "../../spec_helper"

Spectator.describe "the Seen list" do
  alias Monster = Roguelike::Monster
  alias Palette = Roguelike::Ui::Palette
  alias Species = Roguelike::Species

  # One lit room with the character on the staircase and a goblin asleep
  # three squares east.
  ROOM = [
    "#############",
    "#...........#",
    "#...........#",
    "#....<......#",
    "#...........#",
    "#...........#",
    "#############",
  ]

  # Where the goblin stands.
  GOBLIN = {8, 3}

  # A run on `ROOM` with the goblin in it. *clock* gives it timers to fire.
  def room(clock : Bool = false) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
    floor.place Monster.new(Species::Goblin, GOBLIN[0], GOBLIN[1], "band-one")

    run = Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {floor.id => floor}),
      Roguelike::Player.new(floor.id, 5, 3)), 80, 44, clock: clock
    run.render
    run
  end

  # The first row under "Seen".
  def first_seen(run : Playing::Run) : Roguelike::Ui::Line
    run.nearby.seen.children.compact_map(&.as?(Roguelike::Ui::Line)).first
  end

  # Moves the pointer onto the first Seen row.
  def hover_row(run : Playing::Run) : Nil
    row = first_seen run
    run.hover row.rect.x + 1, row.rect.y
  end

  # The style the map draws the goblin's square in.
  def goblin_style(run : Playing::Run) : TermBuf::Style
    spot = run.map.screen_of(GOBLIN[0], GOBLIN[1]) || raise "the goblin is off the map"
    found = run.buffer.hit spot[0], spot[1]
    raise "nothing is drawn at #{spot}" unless found

    run.buffer.styles[found.cell.style]
  end

  describe "hovering a creature's row" do
    it "lights the creature's square on the map" do
      run = room

      hover_row run

      expect(run.map.spotlight).to eq GOBLIN
      expect(goblin_style(run)).to eq Palette::SPOTLIT
    end

    it "blinks the square on a timer" do
      run = room clock: true

      hover_row run
      expect(run.armed.size).to eq 1
      expect(run.map.spotlight).to eq GOBLIN

      run.tick
      run.render
      expect(run.map.spotlight).to be_nil
      expect(goblin_style(run)).not_to eq Palette::SPOTLIT

      run.tick
      run.render
      expect(run.map.spotlight).to eq GOBLIN
    end

    it "stays lit without blinking under --no-flicker" do
      run = room clock: true
      run.play.flicker.burning = false

      hover_row run

      expect(run.map.spotlight).to eq GOBLIN
      expect(run.armed).to be_empty
    end

    it "puts the light out and stops the timer when the pointer leaves the row" do
      run = room clock: true
      hover_row run

      spot = run.map.screen_of(1, 1) || raise "the corner is off the map"
      run.hover spot[0], spot[1]

      expect(run.map.spotlight).to be_nil
      expect(run.armed).to be_empty
    end

    it "lights nothing for a row about an item" do
      run = room
      run.game.floor.monsters.clear
      run.game.floor.drop GOBLIN[0], GOBLIN[1], Roguelike::Item.new(Roguelike::ItemKind::Dagger)
      run.play.refresh
      run.render

      hover_row run

      expect(run.map.spotlight).to be_nil
      expect(first_seen(run).marks).not_to be_nil
    end
  end
end
