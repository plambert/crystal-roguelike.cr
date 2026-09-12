require "../../spec_helper"

Spectator.describe Roguelike::Ui::Examiner do
  alias Direction = Roguelike::Direction
  alias Ui = Roguelike::Ui

  # A motion report with no button held, which is what mode 1003 sends.
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

    it "tracks across a room" do
      run = Playing.open
      seen = [] of String

      (0..8).each do |column|
        hover run, column, 3
        seen << run.examine.what.text
      end

      expect(seen.first).to eq "granite"
      expect(seen.last).to eq "stone floor"
    end

    it "follows the camera rather than the level's own origin" do
      run = Playing.open
      run.map.center_on 62, 19
      run.render

      camera = run.map.camera
      hover run, 4, 3
      expect(run.examiner.spot).to eq({camera[0] + 4, camera[1] + 3})
    end

    # The readout holds what it last had. A panel that empties itself every
    # time the pointer crosses the log is a panel nobody can read.
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

    it "leaves it alone past the edge of a level smaller than the window" do
      run = Playing.open
      run.map.level = Roguelike::Level.parse "tiny", "##\n##"
      run.render

      hover run, 1, 1
      hover run, 30, 8

      expect(run.examiner.spot).to eq({1, 1})
    end

    # A click carries a position like any other report, so it points the
    # readout too and neither needs a mode of its own.
    it "points on a click as well as on a move" do
      run = Playing.open

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, 6, 5,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)

      expect(run.examiner.spot).to eq({6, 5})
    end
  end

  describe "x" do
    it "puts a cursor in the middle of the window" do
      run = Playing.open

      run.press "x"

      expect(run.examiner.cursoring?).to be_true
      expect(run.examiner.spot).to eq run.map.middle
      expect(run.map.cursor).to eq run.examiner.spot
    end

    it "starts where the pointer left the readout" do
      run = Playing.open

      hover run, 6, 5
      run.press "x"

      expect(run.examiner.spot).to eq({6, 5})
      expect(run.map.cursor).to eq({6, 5})
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

    # They mean the player everywhere else, which is what phase 5 gives them.
    it "do nothing while there is no cursor" do
      run = Playing.open

      hover run, 6, 5
      run.press "l"

      expect(run.examiner.spot).to eq({6, 5})
    end

    it "stop at the edge of the level" do
      run = Playing.open

      hover run, 0, 0
      run.press "x"
      run.press "h"
      run.press "k"

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

    # The character is standing on the up staircase, so the square beside it
    # is the one with nothing on it but floor.
    it "leaves the square's own glyph showing" do
      run = Playing.open

      hover run, 7, 5
      run.press "x"
      run.render

      expect(run.row(5)[7]).to eq '.'
    end

    # The glyph is the same either way, so the only evidence the cursor is
    # there is the style the cell came out with.
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
