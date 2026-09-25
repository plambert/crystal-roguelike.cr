require "../../spec_helper"

Spectator.describe Roguelike::Ui::MapPane do
  alias Terrain = Roguelike::Terrain

  SMALL = <<-MAP
    #####
    #.<+=
    #,,,%
    ##>##
    MAP

  # A pane over *floor*, drawn in a window of *columns* by *rows*.
  record Shown,
    pane : Roguelike::Ui::MapPane,
    session : Headless::Session

  def shown(floor : Roguelike::Floor, columns : Int32, rows : Int32) : Shown
    pane = described_class.new floor
    session = Headless.open pane.grid, columns, rows
    session.render

    Shown.new pane, session
  end

  describe "what it draws" do
    it "draws the floor, one glyph per square" do
      run = shown Roguelike::Floor.parse("small", SMALL), 5, 4

      expect(run.session.rows).to eq ["#####", "#.<+#", "#...#", "##>##"]
    end

    # Three rocks draw as one glyph. Two floors draw as another. Color tells
    # them apart. That is the roguelike convention. The model keeps the six
    # terrains separate. Only the palette draws them alike.
    it "draws all three rocks as a wall and both floors as a floor" do
      run = shown Roguelike::Floor.parse("rocks", "#=%\n.,."), 3, 2

      expect(run.session.rows).to eq ["###", "..."]
    end

    it "draws a door open and shut differently" do
      run = shown Roguelike::Floor.parse("doors", "+'"), 2, 1

      expect(run.session.row(0)).to eq "+'"
    end

    it "leaves the window blank past the edge of a small floor" do
      run = shown Roguelike::Floor.parse("tiny", "##\n##"), 6, 4

      expect(run.session.rows).to eq ["##", "##", "", ""]
    end
  end

  describe "#floor=" do
    it "shows the other floor from its top left" do
      run = shown Roguelike::Floors.proving_ground, 10, 4
      run.pane.center_on 60, 20
      expect(run.pane.camera).not_to eq({0, 0})

      run.pane.floor = Roguelike::Floor.parse "small", SMALL
      run.session.render

      expect(run.pane.camera).to eq({0, 0})
      expect(run.session.row(1)).to eq "#.<+#"
    end
  end

  describe "#margin" do
    alias Pane = Roguelike::Ui::MapPane

    # The box is half the window, so a quarter is left on each side.
    it "leaves a quarter of the window on each side" do
      pane = described_class.new Roguelike::Floors.proving_ground

      expect(pane.margin 100).to eq 25
      expect(pane.margin 40).to eq 10
    end

    # A count of cells cannot do this job. Six cells is most of the height of
    # a short terminal and a sliver of a tall one.
    it "grows with the window" do
      pane = described_class.new Roguelike::Floors.proving_ground

      expect(pane.margin 120).to be > pane.margin(60)
    end

    it "follows the box it is given" do
      pane = described_class.new Roguelike::Floors.proving_ground
      pane.box = 100

      expect(pane.margin 100).to eq 0
    end

    it "never asks for less than nothing" do
      pane = described_class.new Roguelike::Floors.proving_ground

      expect(pane.margin 1).to eq 0
      expect(pane.margin 0).to eq 0
    end
  end

  describe "#follow" do
    it "does not move for somewhere well inside the window" do
      run = shown Roguelike::Floors.proving_ground, 40, 16
      run.pane.center_on 36, 14
      before = run.pane.camera

      run.pane.follow 36, 15
      expect(run.pane.camera).to eq before
    end

    it "moves once the square is inside the margin" do
      run = shown Roguelike::Floors.proving_ground, 40, 16
      run.pane.center_on 36, 14
      before = run.pane.camera

      run.pane.follow 36 + 20, 14
      expect(run.pane.camera[0]).to be > before[0]
    end

    it "keeps the square in view wherever it is asked to go" do
      run = shown Roguelike::Floors.proving_ground, 40, 16

      [{1, 1}, {70, 26}, {6, 5}, {62, 19}].each do |spot|
        run.pane.follow spot[0], spot[1]
        run.session.render

        expect(run.pane.grid.view_of(spot[0], spot[1])).not_to be_nil
      end
    end

    # The box is the same share of the window whatever size the window is,
    # rather than the same number of cells.
    it "holds a square for a quarter of the window on each side" do
      run = shown Roguelike::Floors.proving_ground, 40, 16
      room = run.pane.grid.viewport_size
      run.pane.center_on 36, 14
      before = run.pane.camera
      here = run.pane.screen_of 36, 14

      raise "36, 14 is not in the window" unless here

      run.pane.follow 36 + (room[0] // 4 - 1), 14
      expect(run.pane.camera).to eq before

      run.pane.follow 36 + room[0] // 2, 14
      expect(run.pane.camera[0]).to be > before[0]
    end

    # A window is much wider than it is tall and a cell is about twice as
    # tall as it is wide, so the two axes never want the same count.
    it "gives the rows a margin of their own" do
      run = shown Roguelike::Floors.proving_ground, 60, 12
      run.pane.center_on 36, 14
      before = run.pane.camera

      # Five columns is inside a sixty column window's margin of fifteen.
      # Five rows is outside a twelve row window's margin of three.
      run.pane.follow 41, 14
      expect(run.pane.camera).to eq before

      run.pane.follow 36, 19
      expect(run.pane.camera[1]).to be > before[1]
    end
  end

  describe "#cell_at_screen" do
    it "names the square under a spot of the buffer" do
      run = shown Roguelike::Floors.proving_ground, 40, 16
      run.pane.center_on 36, 14

      camera = run.pane.camera
      expect(run.pane.cell_at_screen(3, 2)).to eq({camera[0] + 3, camera[1] + 2})
    end

    it "answers nothing past the edge of the floor" do
      run = shown Roguelike::Floor.parse("tiny", "##\n##"), 6, 4

      expect(run.pane.cell_at_screen(1, 1)).to eq({1, 1})
      expect(run.pane.cell_at_screen(3, 1)).to be_nil
    end
  end

  describe "#screen_of" do
    it "answers where a square is drawn in the buffer" do
      run = shown Roguelike::Floors.proving_ground, 40, 16
      run.pane.center_on 36, 14

      camera = run.pane.camera
      expect(run.pane.screen_of(camera[0] + 3, camera[1] + 2)).to eq({3, 2})
    end

    it "round-trips against #cell_at_screen" do
      run = shown Roguelike::Floors.proving_ground, 40, 16
      run.pane.center_on 36, 14

      spot = run.pane.cell_at_screen 7, 4
      raise "the pointer was over no square" unless spot

      expect(run.pane.screen_of(spot[0], spot[1])).to eq({7, 4})
    end

    it "answers nothing for a square that is scrolled away" do
      run = shown Roguelike::Floors.proving_ground, 40, 16
      run.pane.center_on 4, 4

      expect(run.pane.screen_of(70, 26)).to be_nil
    end
  end

  describe "#middle" do
    # The window is larger than this floor on both axes. The floor draws in
    # the top left corner of it. The middle of the window is past the edge of
    # the floor.
    it "stays on a floor smaller than the window" do
      floor = Roguelike::Floor.parse "tiny", "##\n##"
      run = shown floor, 40, 16

      middle = run.pane.middle
      expect(floor.contains?(middle[0], middle[1])).to be_true
      expect(middle).to eq({1, 1})
    end

    it "is the middle of the window on a floor larger than it" do
      run = shown Roguelike::Floors.proving_ground, 40, 16
      run.pane.center_on 36, 14

      camera = run.pane.camera
      room = run.pane.grid.viewport_size
      expect(run.pane.middle).to eq({camera[0] + room[0] // 2, camera[1] + room[1] // 2})
    end
  end

  describe "in the screen" do
    it "draws what it drew last time" do
      screen = Roguelike::Ui::Screen.new
      screen.fit 80, 24

      pane = described_class.new Roguelike::Floors.proving_ground
      screen.show pane.grid

      drawn = Headless.open(screen.root, 80, 24).text

      expect(drawn).to eq Fixture.expected("screen/proving-ground.txt", drawn)
    end

    it "draws what it drew last time with the camera on the down stairs" do
      screen = Roguelike::Ui::Screen.new
      screen.fit 80, 24

      floor = Roguelike::Floors.proving_ground
      pane = described_class.new floor
      screen.show pane.grid

      session = Headless.open screen.root, 80, 24
      session.render

      stairs = floor.find Terrain::StairsDown
      raise "the shipped floor has no down staircase" unless stairs

      pane.center_on stairs[0], stairs[1]
      drawn = session.text

      expect(drawn).to eq Fixture.expected("screen/proving-ground-stairs.txt", drawn)
    end
  end
end
