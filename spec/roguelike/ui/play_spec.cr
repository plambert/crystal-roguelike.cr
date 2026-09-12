require "../../spec_helper"

Spectator.describe Roguelike::Ui::Play do
  alias Terrain = Roguelike::Terrain

  # The keys that walk, in the order the fingers fall on them.
  CARDINALS = %w[h j k l]
  CORNERS   = %w[y u b n]

  describe "the character on the map" do
    it "is drawn where they are" do
      run = Playing.open
      spot = run.at

      expect(run.map.mark?(spot[0], spot[1])).to eq Roguelike::Ui::Palette::PLAYER
    end

    it "is the only thing on the map that is not the level" do
      run = Playing.open

      expect(run.map.marks.size).to eq 1
    end

    it "starts in view" do
      run = Playing.open
      spot = run.at

      expect(run.map.grid.view_of(spot[0], spot[1])).not_to be_nil
    end
  end

  describe "the movement keys" do
    it "walk one square each and take a turn each" do
      run = Playing.open
      start = run.at

      run.press "l"
      expect(run.at).to eq({start[0] + 1, start[1]})
      expect(run.turn).to eq 1

      run.press "j"
      expect(run.at).to eq({start[0] + 1, start[1] + 1})
      expect(run.turn).to eq 2
    end

    it "walk all four corners" do
      run = Playing.open
      start = run.at

      run.press "u", "b", "y", "n"

      expect(run.at).to eq start
      expect(run.turn).to eq 4
    end

    it "come back where they started, all eight ways" do
      run = Playing.open
      start = run.at

      (CARDINALS + CORNERS).each_slice(2) do |pair|
        run.press pair[0], pair[1]
      end

      expect(run.at).to eq start
      expect(run.turn).to eq 8
    end

    it "take the character with the drawing" do
      run = Playing.open
      start = run.at

      run.press "l"

      expect(run.map.mark?(start[0], start[1])).to be_nil
      expect(run.map.mark?(start[0] + 1, start[1])).to eq Roguelike::Ui::Palette::PLAYER
    end
  end

  describe "walking into something" do
    # The up staircase sits six squares from the room's west wall. Six steps
    # arrive. The seventh does not.
    it "stops at a wall and burns no turn on the attempt" do
      run = Playing.open
      start = run.at

      20.times { run.press "h" }
      stopped = run.at

      expect(stopped[0]).to be > 0
      expect(stopped[1]).to eq start[1]
      expect(run.turn).to eq start[0] - stopped[0]
      expect(run.game.blocking(Roguelike::Direction::West)).not_to be_nil
    end

    # Walking into a shut door opens it. Phase 6 added that.
    it "opens a shut door instead of stopping at it" do
      run = Playing.open
      start = run.at

      15.times { run.press "l" }

      expect(run.game.level.terrain(21, start[1])).to eq Terrain::OpenDoor
      expect(run.at).to eq({20, start[1]})
    end

    it "walks through the door it opened" do
      run = Playing.open
      start = run.at

      20.times { run.press "l" }

      expect(run.at[0]).to be > 21
      expect(run.at[1]).to eq start[1]
    end
  end

  describe "the camera" do
    # This is a dead zone. A person walking about the middle of the window
    # moves the camera not at all. The view follows once they near an
    # edge.
    it "holds still while the character is well inside the window" do
      run = Playing.open Playing.field
      before = run.map.camera

      run.press "l", "l", "l"

      expect(run.map.camera).to eq before
    end

    it "follows once they reach the margin" do
      run = Playing.open Playing.field
      before = run.map.camera

      30.times { run.press "j" }

      expect(run.map.camera).not_to eq before
    end

    it "keeps the character in view however far they walk" do
      run = Playing.open Playing.field

      %w[l j l j n n l l j j y y k k h h].each do |key|
        12.times { run.press key }
        spot = run.at
        expect(run.map.grid.view_of(spot[0], spot[1])).not_to be_nil
      end
    end

    it "stops at the edge of the level rather than showing past it" do
      run = Playing.open Playing.field

      200.times { run.press "n" }
      camera = run.map.camera
      room = run.map.grid.viewport_size
      columns, rows = run.game.level.size

      expect(camera[0] + room[0]).to be <= columns
      expect(camera[1] + room[1]).to be <= rows
    end
  end

  describe "the status line" do
    it "says the turn and where the character is" do
      run = Playing.open
      run.press "l"
      spot = run.at

      expect(run.screen.status_text.text).to contain "turn 1"
      expect(run.screen.status_text.text).to contain "at #{spot[0]},#{spot[1]}"
    end

    it "says whether the mouse is on" do
      run = Playing.open

      expect(run.play.status(true)).to contain "mouse on"
      expect(run.play.status(false)).to contain "mouse off"
    end
  end

  describe "while the examine cursor is up" do
    # A person reading the level is not walking about it. The same keys mean
    # the cursor until the cursor comes off.
    it "moves the cursor and not the character" do
      run = Playing.open
      start = run.at

      run.press "x"
      run.press "l", "l"

      expect(run.at).to eq start
      expect(run.turn).to eq 0
      expect(run.examiner.spot).not_to eq start
    end

    it "gives the keys back to the character on Escape" do
      run = Playing.open
      start = run.at

      run.press "x"
      run.press "l"
      run.press "Escape"
      run.press "l"

      expect(run.at).to eq({start[0] + 1, start[1]})
      expect(run.turn).to eq 1
    end
  end

  describe "drawn" do
    it "draws what it drew last time at the start" do
      drawn = Playing.open.text

      expect(drawn).to eq Fixture.expected("screen/play-start.txt", drawn)
    end

    it "draws what it drew last time after a walk" do
      run = Playing.open
      %w[l l l l l l l l l l j j j n n n].each { |key| run.press key }
      drawn = run.text

      expect(drawn).to eq Fixture.expected("screen/play-walked.txt", drawn)
    end
  end
end
