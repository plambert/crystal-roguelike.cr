module Roguelike::Ui
  # A level as something a `CellGrid` can draw.
  #
  # The adapter exists so that `Level` needs no reference to the widget layer.
  # A level is the model and a `Cells` is what a window over one is asked; the
  # game reads and writes the first and only the screen holds the second.
  class LevelCells < Widgets::Cells(Tile)
    # Which level is being shown. Assigning another shows that one instead,
    # which is what walking down a staircase will be.
    property level : Level

    def initialize(@level : Level)
    end

    def columns : Int32
      @level.columns
    end

    def rows : Int32
      @level.rows
    end

    def cell(x : Int32, y : Int32) : Tile
      @level.tile x, y
    end
  end

  # The window a level is played in.
  #
  # Holds the `CellGrid` and the camera over it, and knows how a tile is
  # drawn. Everything about where the window is pointed goes through here.
  class MapPane
    # What the grid is asking.
    getter cells : LevelCells

    # The widget itself, for putting in a tree.
    getter grid : Widgets::CellGrid(Tile)

    # Cells kept between the thing being followed and the edge of the window
    # before the camera moves at all.
    property margin : Int32 = 6

    # The square the examine cursor is on, or `nil` when there is no cursor.
    #
    # Drawn over whatever is there rather than instead of it, so the cursor
    # says where it is without hiding what it is standing on.
    property cursor : {Int32, Int32}? = nil

    # What the cursor is drawn as: the square's own colours, swapped.
    CURSOR = Style::DEFAULT.reverse

    def initialize(level : Level)
      @cells = LevelCells.new level
      @grid = Widgets::CellGrid.new @cells
      @grid.on_draw = ->(view : TermBuf::View, x : Int32, y : Int32, tile : Tile) do
        look = Palette[tile.terrain]
        here = @cursor
        style = here && here[0] == x && here[1] == y ? look.style.reverse : look.style

        view.write_char 0, 0, look.glyph, style
        nil
      end
    end

    # Which level is being shown.
    def level : Level
      @cells.level
    end

    # Shows *level* instead, from its top left corner.
    def level=(level : Level) : Level
      @cells.level = level
      @grid.scroll_to 0, 0
      level
    end

    # Moves the camera as little as it takes to keep *x*, *y* off the edge of
    # the window, which is what following the player is.
    def follow(x : Int32, y : Int32) : Nil
      @grid.reveal x, y, margin: @margin
    end

    # Puts *x*, *y* in the middle of the window, as near as the edges allow.
    def center_on(x : Int32, y : Int32) : Nil
      @grid.center_on x, y
    end

    # Which square of the level is at *screen_x*, *screen_y* of the buffer, or
    # `nil` when the pointer is not over one.
    def cell_at_screen(screen_x : Int32, screen_y : Int32) : {Int32, Int32}?
      @grid.cell_at_screen screen_x, screen_y
    end

    # Where the camera is.
    def camera : {Int32, Int32}
      {@grid.scroll_x, @grid.scroll_y}
    end

    # Which square is in the middle of the window, which is where a cursor
    # with nowhere else to be should start.
    def middle : {Int32, Int32}
      room = @grid.viewport_size

      {@grid.scroll_x + room[0] // 2, @grid.scroll_y + room[1] // 2}
    end
  end
end
