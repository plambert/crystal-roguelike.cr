module Roguelike::Ui
  # A level, as something a `CellGrid` can draw.
  #
  # This adapter exists so that `Level` needs no reference to the widget
  # layer. A level is the model. A `Cells` is what a window over one asks. The
  # game reads and writes the first. Only the screen holds the second.
  class LevelCells < Widgets::Cells(Tile)
    # Which level is being shown.
    #
    # Assigning another level shows that one instead. Walking down a staircase
    # will do that.
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
  # This class holds the `CellGrid` and the camera over it. It also holds the
  # rule for drawing one tile. Every change to where the window points goes
  # through here.
  class MapPane
    # What the grid asks for its cells.
    getter cells : LevelCells

    # The widget itself. A caller puts it in a tree.
    getter grid : Widgets::CellGrid(Tile)

    # Cells kept between the followed square and the edge of the window. The
    # camera does not move while the square is further in than this.
    property margin : Int32 = 6

    # Squares kept clear around the character when a modal box covers part of
    # the window.
    property avoid_margin : Int32 = 3

    # The square the examine cursor is on. `nil` when there is no cursor.
    #
    # The cursor draws over whatever is on the square. It does not replace it.
    # The cursor marks its square. It leaves the glyph on that square
    # readable.
    property cursor : {Int32, Int32}? = nil

    # What is standing on a square. It draws over the terrain. It is not
    # written into the level.
    #
    # The character goes here now. Monsters and dropped items go here later.
    # Whatever owns the game state fills this table. A pane draws a level. It
    # holds nothing about the creatures on it.
    getter marks : Hash({Int32, Int32}, Look) = {} of {Int32, Int32} => Look

    # Squares offered as an answer to a question.
    #
    # Each keeps its own glyph and its own colour. Only the background
    # changes. A person choosing between four doors has to see which door is
    # which.
    getter highlights : Set({Int32, Int32}) = Set({Int32, Int32}).new

    def initialize(level : Level)
      @cells = LevelCells.new level
      @grid = Widgets::CellGrid.new @cells
      @grid.on_draw = ->(view : TermBuf::View, x : Int32, y : Int32, tile : Tile) do
        look = @marks[{x, y}]? || Palette[tile.terrain]
        style = look.style
        style = style.bg Palette::OFFERED if @highlights.includes?({x, y})

        here = @cursor
        style = style.reverse if here && here[0] == x && here[1] == y

        view.write_char 0, 0, look.glyph, style
        nil
      end
    end

    # Puts *look* on *x*, *y*. It stays until `#clear_marks`.
    def mark(x : Int32, y : Int32, look : Look) : Nil
      @marks[{x, y}] = look
    end

    # Takes everything off the terrain.
    def clear_marks : Nil
      @marks.clear
    end

    # Offers *x*, *y* as an answer to a question.
    def highlight(x : Int32, y : Int32) : Nil
      @highlights << {x, y}
    end

    # Stops offering anything.
    def clear_highlights : Nil
      @highlights.clear
    end

    # Whether *x*, *y* is offered.
    def highlighted?(x : Int32, y : Int32) : Bool
      @highlights.includes?({x, y})
    end

    # What is on *x*, *y* over the terrain. `nil` for bare ground.
    def mark?(x : Int32, y : Int32) : Look?
      @marks[{x, y}]?
    end

    # Which level is being shown.
    def level : Level
      @cells.level
    end

    # Shows *level* instead, from its top left corner.
    def level=(level : Level) : Level
      @cells.level = level
      @grid.scroll_to 0, 0
      clear_marks
      clear_highlights
      level
    end

    # Moves the camera as little as it takes to keep *x*, *y* off the edge of
    # the window. Following the character uses this.
    def follow(x : Int32, y : Int32) : Nil
      @grid.reveal x, y, margin: @margin
    end

    # Moves the camera so that *x*, *y* and the squares around it fall outside
    # *area*. Answers whether the camera moved.
    def avoid(x : Int32, y : Int32, area : TermBuf::Rect) : Bool
      @grid.avoid x, y, area, margin: @avoid_margin
    end

    # Puts the camera back where *camera* had it.
    def camera=(camera : {Int32, Int32}) : Nil
      @grid.scroll_to camera[0], camera[1]
    end

    # Puts *x*, *y* in the middle of the window. Stops at the edges of the
    # level.
    def center_on(x : Int32, y : Int32) : Nil
      @grid.center_on x, y
    end

    # Which square of the level is at *screen_x*, *screen_y* of the buffer.
    # `nil` when the pointer is not over a square.
    def cell_at_screen(screen_x : Int32, screen_y : Int32) : {Int32, Int32}?
      @grid.cell_at_screen screen_x, screen_y
    end

    # Where the camera is.
    def camera : {Int32, Int32}
      {@grid.scroll_x, @grid.scroll_y}
    end

    # Which square is in the middle of the window. A cursor with nowhere else
    # to be starts there.
    def middle : {Int32, Int32}
      room = @grid.viewport_size

      {@grid.scroll_x + room[0] // 2, @grid.scroll_y + room[1] // 2}
    end
  end
end
