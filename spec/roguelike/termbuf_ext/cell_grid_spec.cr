require "../../spec_helper"

Spectator.describe TermBuf::Widgets::CellGrid do
  alias Widgets = TermBuf::Widgets

  # A grid over a field of *field* by *field* cells, drawn in a window of
  # *columns* by *rows*, laid out and ready to be measured.
  record Window,
    grid : Widgets::CellGrid({Int32, Int32}),
    session : Headless::Session

  def windowed(columns : Int32, rows : Int32, field : Int32 = 200) : Window
    cells = Widgets::Cells.from field, field,
      ->(x : Int32, y : Int32) { {x, y} }

    grid = Widgets::CellGrid.new cells
    session = Headless.open grid, columns, rows
    session.render

    Window.new grid, session
  end

  describe "the window" do
    it "is the size of the box it was given" do
      expect(windowed(40, 15).grid.viewport_size).to eq({40, 15})
    end

    it "says how large the field is" do
      expect(windowed(40, 15).grid.content_size).to eq({200, 200})
    end

    it "starts at the top left" do
      grid = windowed(40, 15).grid

      expect({grid.scroll_x, grid.scroll_y}).to eq({0, 0})
    end

    it "shows exactly the cells that fit" do
      grid = windowed(40, 15).grid

      expect(grid.visible_x).to eq(0...40)
      expect(grid.visible_y).to eq(0...15)
    end
  end

  describe "a field smaller than the window" do
    it "does not scroll" do
      grid = windowed(40, 15, field: 8).grid

      grid.scroll_to 5, 5
      expect({grid.scroll_x, grid.scroll_y}).to eq({0, 0})
    end

    it "shows all of it and no more" do
      grid = windowed(40, 15, field: 8).grid

      expect(grid.visible_x).to eq(0...8)
      expect(grid.visible_y).to eq(0...8)
    end

    it "cannot be centred away from the origin" do
      grid = windowed(40, 15, field: 8).grid

      grid.center_on 7, 7
      expect({grid.scroll_x, grid.scroll_y}).to eq({0, 0})
    end
  end

  describe "#scroll_to" do
    it "puts a cell at the top left" do
      grid = windowed(40, 15).grid

      grid.scroll_to 30, 20
      expect({grid.scroll_x, grid.scroll_y}).to eq({30, 20})
    end

    it "stops at the far edge rather than showing past it" do
      grid = windowed(40, 15).grid

      grid.scroll_to 1_000, 1_000
      expect({grid.scroll_x, grid.scroll_y}).to eq({160, 185})
    end

    it "stops at the near edge" do
      grid = windowed(40, 15).grid

      grid.scroll_to -50, -50
      expect({grid.scroll_x, grid.scroll_y}).to eq({0, 0})
    end

    it "keeps the window full at the far edge" do
      grid = windowed(40, 15).grid

      grid.scroll_to 1_000, 1_000
      expect(grid.visible_x).to eq(160...200)
      expect(grid.visible_y).to eq(185...200)
    end
  end

  describe "#scroll_by" do
    it "moves the camera" do
      grid = windowed(40, 15).grid

      grid.scroll_to 30, 20
      grid.scroll_by 5, -5

      expect({grid.scroll_x, grid.scroll_y}).to eq({35, 15})
    end

    it "stops at the edges" do
      grid = windowed(40, 15).grid

      grid.scroll_by -1, -1
      expect({grid.scroll_x, grid.scroll_y}).to eq({0, 0})
    end
  end

  describe "#center_on" do
    it "puts a cell in the middle" do
      grid = windowed(41, 15).grid

      grid.center_on 100, 100
      expect(grid.view_of(100, 100)).to eq({20, 7})
    end

    it "clamps at a corner rather than showing blank beside it" do
      grid = windowed(40, 15).grid

      grid.center_on 0, 0
      expect({grid.scroll_x, grid.scroll_y}).to eq({0, 0})

      grid.center_on 199, 199
      expect({grid.scroll_x, grid.scroll_y}).to eq({160, 185})
    end

    it "still shows the cell it was asked to centre when it clamped" do
      grid = windowed(40, 15).grid

      grid.center_on 199, 199
      expect(grid.view_of(199, 199)).to eq({39, 14})
    end
  end

  describe "#cell_at" do
    it "turns a spot in the window into one in the field" do
      grid = windowed(40, 15).grid

      grid.scroll_to 30, 20
      expect(grid.cell_at(0, 0)).to eq({30, 20})
      expect(grid.cell_at(5, 3)).to eq({35, 23})
    end

    it "answers nothing outside the window" do
      grid = windowed(40, 15).grid

      expect(grid.cell_at(40, 0)).to be_nil
      expect(grid.cell_at(0, 15)).to be_nil
      expect(grid.cell_at(-1, 0)).to be_nil
    end

    it "answers nothing past the edge of a field smaller than the window" do
      grid = windowed(40, 15, field: 8).grid

      expect(grid.cell_at(7, 7)).to eq({7, 7})
      expect(grid.cell_at(8, 0)).to be_nil
      expect(grid.cell_at(0, 8)).to be_nil
    end

    # The round trip a mouse report depends on: whatever the camera is doing,
    # the cell under a spot is the cell drawn there.
    it "round-trips against #view_of wherever the camera is" do
      run = windowed 40, 15
      grid = run.grid
      rng = Roguelike::Rng.new 20260911_u64

      100.times do
        grid.center_on rng.rand(200), rng.rand(200)
        run.session.render

        view_x = rng.rand 40
        view_y = rng.rand 15
        spot = grid.cell_at view_x, view_y

        expect(spot).not_to be_nil
        next unless spot

        expect(grid.view_of(spot[0], spot[1])).to eq({view_x, view_y})
      end
    end
  end

  describe "#view_of" do
    it "answers nothing for a cell that is not showing" do
      grid = windowed(40, 15).grid

      grid.scroll_to 30, 20
      expect(grid.view_of(29, 20)).to be_nil
      expect(grid.view_of(70, 20)).to be_nil
    end

    it "answers nothing for a cell outside the field" do
      expect(windowed(40, 15).grid.view_of(200, 0)).to be_nil
    end
  end

  describe "#reveal" do
    it "does not move for a cell well inside the window" do
      grid = windowed(40, 15).grid

      grid.scroll_to 30, 20
      grid.reveal 45, 27, margin: 5

      expect({grid.scroll_x, grid.scroll_y}).to eq({30, 20})
    end

    it "moves as little as it takes once the cell is inside the margin" do
      grid = windowed(40, 15).grid

      grid.scroll_to 30, 20
      grid.reveal 34, 27, margin: 5

      expect(grid.scroll_x).to eq 29
      expect(grid.scroll_y).to eq 20
    end

    it "follows a cell leaving the far edge" do
      grid = windowed(40, 15).grid

      grid.scroll_to 30, 20
      grid.reveal 65, 27, margin: 5

      expect(grid.scroll_x).to eq 31
    end

    it "brings a cell far outside straight in" do
      grid = windowed(40, 15).grid

      grid.reveal 100, 100, margin: 5

      expect(grid.view_of(100, 100)).not_to be_nil
    end

    it "takes no margin at all" do
      grid = windowed(40, 15).grid

      grid.scroll_to 30, 20
      grid.reveal 69, 34

      expect({grid.scroll_x, grid.scroll_y}).to eq({30, 20})
    end

    # There is no camera position that leaves a cell five from every edge of a
    # window eight wide, so it goes in the middle instead of oscillating.
    it "centres when the margin does not fit the window" do
      grid = windowed(9, 9).grid

      grid.reveal 100, 100, margin: 5

      expect(grid.view_of(100, 100)).to eq({4, 4})
    end

    it "still stops at the edges of the field" do
      grid = windowed(40, 15).grid

      grid.reveal 0, 0, margin: 5
      expect({grid.scroll_x, grid.scroll_y}).to eq({0, 0})
    end
  end

  describe "what it asks its source" do
    it "asks only about the cells that are showing" do
      asked = 0
      cells = Widgets::Cells.from 1_000, 1_000, ->(x : Int32, y : Int32) do
        asked += 1
        {x, y}
      end

      grid = Widgets::CellGrid.new cells
      Headless.open(grid, 40, 15).render

      expect(asked).to eq 40 * 15
    end

    it "asks about no more after the camera has moved" do
      asked = 0
      cells = Widgets::Cells.from 1_000, 1_000, ->(x : Int32, y : Int32) do
        asked += 1
        {x, y}
      end

      grid = Widgets::CellGrid.new cells
      session = Headless.open grid, 40, 15
      session.render

      asked = 0
      grid.center_on 500, 500
      session.render

      expect(asked).to eq 40 * 15
    end
  end

  describe "#draw" do
    it "gives the hook the field's own coordinates" do
      seen = [] of {Int32, Int32}
      cells = Widgets::Cells.from 200, 200, ->(x : Int32, y : Int32) { {x, y} }
      grid = Widgets::CellGrid.new cells
      grid.on_draw = ->(_view : TermBuf::View, x : Int32, y : Int32, _held : {Int32, Int32}) do
        seen << {x, y}
        nil
      end

      session = Headless.open grid, 4, 2
      grid.scroll_to 10, 20
      session.render

      expect(seen).to eq [{10, 20}, {11, 20}, {12, 20}, {13, 20},
                          {10, 21}, {11, 21}, {12, 21}, {13, 21}]
    end

    # A square is one cell by construction. A cluster the terminal would draw
    # two columns wide does not fit in the view cut for it, and termbuf drops
    # a cluster crossing an edge whole rather than splitting it — so the
    # square after it stays where it was, and the mapping a mouse report
    # depends on stays exact.
    it "keeps one cell per square when a square draws a wide glyph" do
      cells = Widgets::Cells.from 4, 1, ->(x : Int32, _y : Int32) { x }
      grid = Widgets::CellGrid.new cells
      grid.on_draw = ->(view : TermBuf::View, x : Int32, _y : Int32, _held : Int32) do
        view.write 0, 0, x.even? ? "漢" : "."
        nil
      end

      session = Headless.open grid, 4, 1

      expect(session.row(0)).to eq " . ."
      expect(grid.cell_at(1, 0)).to eq({1, 0})
      expect(grid.cell_at(3, 0)).to eq({3, 0})
    end

    it "cuts each view to one cell, so an overlong write does not bleed" do
      cells = Widgets::Cells.from 4, 1, ->(x : Int32, _y : Int32) { x }
      grid = Widgets::CellGrid.new cells
      grid.on_draw = ->(view : TermBuf::View, x : Int32, _y : Int32, _held : Int32) do
        view.write 0, 0, "#{x}###"
        nil
      end

      session = Headless.open grid, 4, 1

      expect(session.row(0)).to eq "0123"
    end
  end

  describe "the keyboard" do
    it "stays out of the tab order unless it is asked for" do
      expect(windowed(40, 15).grid.focusable?).to be_false
    end

    it "moves the camera under the arrows once it has the keyboard" do
      run = windowed 40, 15
      run.grid.takes_focus = true
      run.session.app.focus.rebuild
      run.session.app.focus.focus run.grid

      run.session.press "Down"
      run.session.press "Down"
      run.session.press "Right"

      expect({run.grid.scroll_x, run.grid.scroll_y}).to eq({1, 2})
    end

    it "moves a window at a time on the page keys" do
      run = windowed 40, 15
      run.grid.takes_focus = true
      run.session.app.focus.rebuild
      run.session.app.focus.focus run.grid

      run.session.press "PageDown"

      expect(run.grid.scroll_y).to eq 15
    end

    it "goes to the far corner on End" do
      run = windowed 40, 15
      run.grid.takes_focus = true
      run.session.app.focus.rebuild
      run.session.app.focus.focus run.grid

      run.session.press "End"

      expect({run.grid.scroll_x, run.grid.scroll_y}).to eq({160, 185})
    end
  end

  describe "the wheel" do
    it "scrolls the window" do
      run = windowed 40, 15

      run.session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::WheelDown,
        10, 5,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)

      expect(run.grid.scroll_y).to eq run.grid.wheel
    end
  end

  describe "a window that changed size" do
    it "brings the camera back inside the field when the window grew" do
      run = windowed 40, 15, field: 50
      grid = run.grid

      grid.scroll_to 1_000, 1_000
      expect(grid.scroll_x).to eq 10

      run.session.resize 60, 15
      run.session.render

      expect(grid.scroll_x).to eq 0
      expect(grid.visible_x).to eq(0...50)
    end
  end

  describe "drawn" do
    # A checkerboard is the cheapest thing to read a camera off by eye: the
    # parity of the top left cell says where the window is.
    def checkerboard(columns : Int32, rows : Int32) : Window
      cells = Widgets::Cells.from 200, 200,
        ->(x : Int32, y : Int32) { {x, y} }

      grid = Widgets::CellGrid.new cells
      grid.on_draw = ->(view : TermBuf::View, x : Int32, y : Int32, _held : {Int32, Int32}) do
        view.write_char 0, 0, (x + y).even? ? '#' : '.'
        nil
      end

      session = Headless.open grid, columns, rows
      Window.new grid, session
    end

    it "draws what it drew last time at the origin" do
      run = checkerboard 40, 15
      drawn = run.session.text

      expect(drawn).to eq Fixture.expected("cell_grid/checkerboard-origin.txt", drawn)
    end

    # An odd sum, so the parity of the top left cell flips and the fixture is
    # a different picture rather than the same one shifted by two.
    it "draws what it drew last time once scrolled" do
      run = checkerboard 40, 15
      run.grid.scroll_to 7, 4
      drawn = run.session.text

      expect(drawn).to eq Fixture.expected("cell_grid/checkerboard-7-4.txt", drawn)
    end

    it "draws a different picture once the camera has moved" do
      run = checkerboard 40, 15
      before = run.session.text

      run.grid.scroll_to 7, 4
      expect(run.session.text).not_to eq before
    end
  end

  describe "a Scrollbar over one" do
    # The rule the bar is drawn on is one glyph and the thumb another, so the
    # row that differs from the rest is where the thumb is.
    def thumb_row(session : Headless::Session) : Int32?
      ends = session.rows.map &.[-1]
      rule = ends.tally.max_by { |_, count| count }[0]

      ends.index { |glyph| glyph != rule }
    end

    it "tracks the camera" do
      cells = Widgets::Cells.from 200, 200, ->(x : Int32, y : Int32) { {x, y} }
      grid = Widgets::CellGrid.new cells
      grid.on_draw = ->(view : TermBuf::View, x : Int32, y : Int32, _held : {Int32, Int32}) do
        view.write_char 0, 0, (x + y).even? ? '#' : '.'
        nil
      end

      root = Widgets::Panel.new(
        direction: Widgets::Layout::Direction::Row,
        width: Widgets::Layout::Sizing.grow,
        height: Widgets::Layout::Sizing.grow)
      root.add grid, Widgets::Scrollbar.new(grid)

      session = Headless.open root, 21, 10
      session.render
      expect(thumb_row(session)).to eq 0

      grid.scroll_to 0, 185
      session.render
      expect(thumb_row(session)).to eq 9
    end
  end
end
