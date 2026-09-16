require "../../spec_helper"

Spectator.describe Roguelike::Ui::Examiner do
  alias Direction = Roguelike::Direction
  alias Ui = Roguelike::Ui

  # A motion report with no button held. Mode 1003 sends these.
  def hover(run : Playing::Run, x : Int32, y : Int32) : Nil
    run.hover x, y
  end

  describe "before anything has been looked at" do
    it "says so rather than showing an empty pane" do
      run = Playing.open

      expect(run.examiner.spot).to be_nil
      expect(run.examine.what.text).to eq Ui::ExaminePane::NOTHING
    end

    it "puts no cursor on the map" do
      expect(Playing.open.map.cursor).to be_nil
    end
  end

  describe "the pointer" do
    it "names the square under it" do
      run = Playing.open

      hover run, 6, 5
      expect(run.examiner.spot).to eq({6, 5})
      expect(run.examine.what.text).to eq "staircase up"
      expect(run.examine.detail.text).to eq "a staircase leading up"
      expect(run.examine.where.text).to eq "6, 5"
    end

    # Column 1 is the room's west wall. Column 0 is the rock behind it, which
    # the character cannot see from inside the room.
    it "tracks across a room" do
      run = Playing.open
      seen = [] of String

      (1..8).each do |column|
        hover run, column, 3
        seen << run.examine.what.text
      end

      expect(seen.first).to eq "granite"
      expect(seen.last).to eq "stone floor"
    end

    it "says a square out of sight cannot be seen" do
      run = Playing.open

      hover run, 0, 3

      expect(run.examiner.spot).to eq({0, 3})
      expect(run.examine.what.text).to eq Ui::ExaminePane::UNSEEN
      expect(run.examine.detail.text).to be_empty
    end

    it "follows the camera rather than the floor's own origin" do
      run = Playing.open
      run.map.center_on 62, 19
      run.render

      camera = run.map.camera
      hover run, 4, 3
      expect(run.examiner.spot).to eq({camera[0] + 4, camera[1] + 3})
    end

    # The readout holds what it last had. A panel that empties whenever the
    # pointer crosses the log is a panel nobody can read.
    it "leaves the readout alone over the sidebar" do
      run = Playing.open

      hover run, 6, 5
      hover run, 70, 5

      expect(run.examiner.spot).to eq({6, 5})
      expect(run.examine.what.text).to eq "staircase up"
    end

    it "leaves it alone over the log" do
      run = Playing.open

      hover run, 6, 5
      hover run, 20, 21

      expect(run.examiner.spot).to eq({6, 5})
    end

    it "leaves it alone past the edge of a floor smaller than the window" do
      run = Playing.open
      run.map.floor = Roguelike::Floor.parse "tiny", "##\n##"
      run.render

      hover run, 1, 1
      hover run, 30, 8

      expect(run.examiner.spot).to eq({1, 1})
    end

    # A click carries a position. Every report does. So a click points the
    # readout too. Neither needs a mode of its own.
    it "points on a click as well as on a move" do
      run = Playing.open

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, 6, 5,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)

      expect(run.examiner.spot).to eq({6, 5})
    end
  end

  describe "the readout once the game moves on" do
    alias Monster = Roguelike::Monster

    # One lit room with the character on the up staircase and an orc two
    # squares east.
    ROOM = [
      "#######",
      "#.....#",
      "#.<.o.+",
      "#.....#",
      "#######",
    ]

    def watching : Playing::Run
      floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
      player = Roguelike::Player.new floor.id, *Roguelike::Game.entrance(floor)

      Playing.open Roguelike::Game.new(
        Roguelike::World.new(Playing::SEED, {floor.id => floor}), player), 60, 20
    end

    # The screen cell square *x*, *y* of the floor is drawn in.
    def cell(run : Playing::Run, x : Int32, y : Int32) : {Int32, Int32}
      found = run.map.screen_of x, y
      raise "#{x}, #{y} is not in the window" unless found

      found
    end

    # The readout is written when the pointer lands on a square. What is on
    # that square goes on changing after that, and nothing else tells the
    # readout.
    it "stops naming a creature that has been killed" do
      run = watching
      run.hover *cell(run, 4, 2)
      expect(run.examine.what.text).to eq "orc"

      creature = run.game.floor.monster 4, 2
      run.game.kill creature if creature
      run.play.refresh

      expect(run.examine.what.text).to eq "stone floor"
    end

    it "stops naming an item that has been picked up" do
      run = watching
      here = run.at
      run.game.floor.drop here[0], here[1],
        Roguelike::Item.new(Roguelike::ItemKind::Dagger)
      run.play.refresh

      run.hover *cell(run, here[0], here[1])
      expect(run.examine.litter.text).to contain "dagger"

      run.press ","

      expect(run.examine.litter.hidden?).to be_true
    end

    it "names a door that has been opened" do
      run = watching
      run.hover *cell(run, 6, 2)
      expect(run.examine.what.text).to eq "closed door"

      run.game.floor.set 6, 2, Roguelike::Terrain::OpenDoor
      run.play.refresh

      expect(run.examine.what.text).to eq "open door"
    end

    # The pointer sits over a cell of the screen rather than over a square of
    # the floor. Walking scrolls the camera under it, so the square it is on
    # is whatever the camera slid there.
    it "follows the pointer when the camera scrolls under it" do
      run = Playing.open Playing.field(200, 60)
      here = run.at
      spot = cell run, here[0] + 3, here[1]

      run.hover *spot
      expect(run.examiner.spot).to eq({here[0] + 3, here[1]})

      40.times { run.press "l" }

      expect(run.examiner.spot).to eq run.map.cell_at_screen(spot[0], spot[1])
      expect(run.examine.where.text).to eq "#{run.examiner.spot.try &.[](0)}, #{here[1]}"
    end

    # The readout belongs to the cursor while the cursor is on the map. A
    # pointer resting over some other square must not take it back.
    it "leaves the keyboard cursor where it is" do
      run = Playing.open Playing.field(200, 60)
      here = run.at
      run.hover *cell(run, here[0] + 3, here[1])

      run.press "x"
      expect(run.examiner.spot).to eq here

      run.play.refresh

      expect(run.examiner.spot).to eq here
    end

    # The square under the cursor changes the same way any other does.
    it "restates the square the keyboard cursor is on" do
      run = watching
      run.press "x"
      run.press "l"
      run.press "l"
      expect(run.examine.what.text).to eq "orc"

      creature = run.game.floor.monster 4, 2
      run.game.kill creature if creature
      run.play.refresh

      expect(run.examine.what.text).to eq "stone floor"
    end
  end

  describe "x" do
    it "puts a cursor on the character" do
      run = Playing.open

      run.press "x"

      expect(run.examiner.cursoring?).to be_true
      expect(run.examiner.spot).to eq run.at
      expect(run.map.cursor).to eq run.examiner.spot
    end

    # The map pane is larger than the floor in a window this size. The floor
    # draws in the top left corner of the pane. The middle of the pane is past
    # the edge of the floor, and a cursor put there is a cursor nobody sees.
    it "puts a cursor on the character in a window larger than the floor" do
      run = Playing.open nil, 200, 60

      run.press "x"

      expect(run.examiner.cursoring?).to be_true
      expect(run.examiner.spot).to eq run.at
      expect(run.map.cursor).to eq run.at
    end

    # A person who presses `x` is reading with the keyboard. Where the mouse
    # was resting is not where they want to start.
    it "starts on the character wherever the pointer left the readout" do
      run = Playing.open

      hover run, 12, 9
      run.press "x"

      expect(run.examiner.spot).to eq run.at
      expect(run.map.cursor).to eq run.at
    end

    it "takes the cursor off again" do
      run = Playing.open

      run.press "x"
      run.press "x"

      expect(run.examiner.cursoring?).to be_false
      expect(run.map.cursor).to be_nil
    end

    it "leaves the readout saying what it said" do
      run = Playing.open

      hover run, 6, 5
      run.press "x"
      run.press "x"

      expect(run.examine.what.text).to eq "staircase up"
    end
  end

  describe "the pointer while the cursor is on the map" do
    # Brushing the mouse would otherwise take the readout off whatever the
    # person is reading with the keyboard.
    it "does not move the cursor" do
      run = Playing.open

      run.press "x"
      run.press "j"
      hover run, 20, 12

      expect(run.examiner.spot).to eq({6, 6})
      expect(run.map.cursor).to eq({6, 6})
      expect(run.examine.where.text).to eq "6, 6"
    end

    # A person who wants the mouse says so with a button. That is a request,
    # not a brush.
    it "moves the cursor on a click" do
      run = Playing.open

      run.press "x"
      run.click 20, 12

      expect(run.examiner.spot).to eq({20, 12})
      expect(run.map.cursor).to eq({20, 12})
      expect(run.examiner.cursoring?).to be_true
    end

    it "leaves the cursor alone on a click off the map" do
      run = Playing.open

      run.press "x"
      run.click 70, 5

      expect(run.examiner.spot).to eq({6, 5})
    end

    # A wheel notch arrives as a press. It is not a click, and it says
    # nothing about where the person wants to look.
    it "does not move the cursor on a wheel notch" do
      run = Playing.open

      run.press "x"
      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::WheelDown, 20, 12,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)
      run.render

      expect(run.examiner.spot).to eq({6, 5})
    end

    it "still asks for the crosshair over the map" do
      run = Playing.open

      run.press "x"
      hover run, 20, 12

      expect(run.pointer.shape).to eq Ui::Pointer::OVER_MAP
    end

    it "puts the shape back off the map" do
      run = Playing.open

      run.press "x"
      hover run, 20, 12
      hover run, 70, 5

      expect(run.pointer.shape).to eq Ui::Pointer::ELSEWHERE
      expect(run.pointer.cursor).to be_nil
    end

    # The gate is only for the cursor. The pointer points the readout again
    # once the cursor comes off the map.
    it "points the readout again once the cursor comes off" do
      run = Playing.open

      run.press "x"
      run.press "Escape"
      hover run, 20, 12

      expect(run.examiner.spot).to eq({20, 12})
    end
  end

  describe "the terminal's own cursor" do
    it "goes nowhere before anything has been looked at" do
      expect(Playing.open.play.cursor).to be_nil
    end

    it "goes where the examine cursor is" do
      run = Playing.open

      hover run, 6, 5
      run.press "x"

      expect(run.examiner.screen_spot).to eq({6, 5})
    end

    # The pointer moved the readout. The pointer is then taken off the map.
    # The keyboard cursor is what is left, so the terminal's own cursor goes
    # to it.
    it "follows the keyboard once the pointer leaves the map" do
      run = Playing.open

      hover run, 6, 5
      run.press "x"
      run.press "j"
      hover run, 70, 5

      expect(run.pointer.cursor).to be_nil
      expect(run.play.cursor).to eq({6, 6})
    end

    # The mouse is resting on the square it last reported. The keyboard is
    # what is moving the cursor. The terminal's own cursor follows the
    # keyboard.
    it "follows the keyboard while the pointer rests" do
      run = Playing.open

      hover run, 6, 5
      run.press "x"
      run.press "j"
      run.press "j"

      expect(run.pointer.cursor).to eq({6, 5})
      expect(run.play.cursor).to eq({6, 7})
    end

    it "goes to the pointer while there is no examine cursor" do
      run = Playing.open

      hover run, 9, 7

      expect(run.play.cursor).to eq({9, 7})
    end

    # The pointer is over the map, so its shape is still the crosshair. The
    # readout is the keyboard's, so the terminal's own cursor stays on it.
    it "stays on the examine cursor while the pointer is elsewhere on the map" do
      run = Playing.open

      run.press "x"
      hover run, 9, 7

      expect(run.pointer.cursor).to eq({9, 7})
      expect(run.play.cursor).to eq({6, 5})
    end

    it "goes nowhere while the cursor is scrolled out of the window" do
      run = Playing.open

      run.press "x"
      run.map.center_on 60, 20
      run.render

      expect(run.examiner.screen_spot).to be_nil
    end

    it "goes nowhere while a menu is up" do
      run = Playing.open
      run.game.player.inventory.add Roguelike::Item.new Roguelike::ItemKind::Dagger

      run.press "x"
      run.press "i"

      expect(run.menu.showing?).to be_true
      expect(run.play.cursor).to be_nil
    end

    it "goes nowhere while a question is up" do
      run = Playing.open

      run.press "x"
      run.press "Q"

      expect(run.prompt.asking?).to be_true
      expect(run.play.cursor).to be_nil
    end

    it "goes nowhere once the cursor comes off the map" do
      run = Playing.open

      run.press "x"
      run.press "Escape"

      expect(run.examiner.screen_spot).to be_nil
    end
  end

  describe "Escape" do
    it "takes the cursor off" do
      run = Playing.open

      run.press "x"
      run.press "Escape"

      expect(run.examiner.cursoring?).to be_false
      expect(run.map.cursor).to be_nil
    end

    it "does nothing when there is no cursor" do
      run = Playing.open

      run.press "Escape"
      expect(run.examiner.cursoring?).to be_false
    end
  end

  describe "the movement keys" do
    it "move the cursor one square each" do
      run = Playing.open

      hover run, 6, 5
      run.press "x"
      run.press "l"
      run.press "j"

      expect(run.examiner.spot).to eq({7, 6})
    end

    it "move on the diagonals too" do
      run = Playing.open

      hover run, 6, 5
      run.press "x"
      run.press "y"
      expect(run.examiner.spot).to eq({5, 4})

      run.press "n"
      expect(run.examiner.spot).to eq({6, 5})
    end

    it "say what the cursor is now on" do
      run = Playing.open

      hover run, 6, 5
      run.press "x"
      run.press "l"

      expect(run.examine.what.text).to eq "stone floor"
      expect(run.examine.where.text).to eq "7, 5"
    end

    # The same keys move the character everywhere else. Phase 5 added
    # that.
    it "do nothing while there is no cursor" do
      run = Playing.open

      hover run, 6, 5
      run.press "l"

      expect(run.examiner.spot).to eq({6, 5})
    end

    it "stop at the edge of the floor" do
      run = Playing.open

      run.press "x"
      10.times { run.press "h" }
      10.times { run.press "k" }

      expect(run.examiner.spot).to eq({0, 0})
    end

    it "bring the camera with them" do
      run = Playing.open
      run.press "x"

      60.times { run.press "l" }
      run.render

      spot = run.examiner.spot
      raise "the cursor went nowhere" unless spot

      expect(run.map.grid.view_of(spot[0], spot[1])).not_to be_nil
    end
  end

  describe "drawn" do
    it "draws what it drew last time with nothing looked at" do
      drawn = Playing.open.text

      expect(drawn).to eq Fixture.expected("screen/examine-empty.txt", drawn)
    end

    it "draws what it drew last time pointed at the up staircase" do
      run = Playing.open
      hover run, 6, 5
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/examine-stairs.txt", drawn)
    end

    it "draws what it drew last time with the cursor on the map" do
      run = Playing.open
      hover run, 6, 5
      run.press "x"
      run.press "j"
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/examine-cursor.txt", drawn)
    end
  end

  describe "the cursor on the map" do
    it "is drawn where the cursor is" do
      run = Playing.open

      hover run, 6, 5
      run.press "x"
      run.render

      expect(run.map.cursor).to eq({6, 5})
    end

    # The character stands on the up staircase. The square beside it holds
    # nothing but floor.
    it "leaves the square's own glyph showing" do
      run = Playing.open

      run.press "x"
      run.press "l"
      run.render

      expect(run.examiner.spot).to eq({7, 5})
      expect(run.row(5)[7]).to eq '.'
    end

    # The glyph is the same either way. The cell's style is the only evidence
    # the cursor is there.
    it "draws that square in a style of its own" do
      run = Playing.open

      hover run, 6, 5
      plain = run.buffer.hit(6, 5).try &.cell.style
      beside = run.buffer.hit(7, 5).try &.cell.style

      run.press "x"
      run.render

      expect(run.buffer.hit(6, 5).try &.cell.style).not_to eq plain
      expect(run.buffer.hit(7, 5).try &.cell.style).to eq beside
    end

    it "puts the square back when the cursor goes" do
      run = Playing.open

      hover run, 6, 5
      plain = run.buffer.hit(6, 5).try &.cell.style

      run.press "x"
      run.render
      run.press "Escape"
      run.render

      expect(run.buffer.hit(6, 5).try &.cell.style).to eq plain
    end
  end
end
