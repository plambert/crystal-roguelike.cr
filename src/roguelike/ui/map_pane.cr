module Roguelike::Ui
  # A floor, as something a `CellGrid` can draw.
  #
  # This adapter exists so that `Floor` needs no reference to the widget
  # layer. A floor is the model. A `Cells` is what a window over one asks. The
  # game reads and writes the first. Only the screen holds the second.
  class FloorCells < Widgets::Cells(Tile)
    # Which floor is being shown.
    #
    # Assigning another floor shows that one instead. Walking down a staircase
    # will do that.
    property floor : Floor

    def initialize(@floor : Floor)
    end

    def columns : Int32
      @floor.columns
    end

    def rows : Int32
      @floor.rows
    end

    def cell(x : Int32, y : Int32) : Tile
      @floor.tile x, y
    end
  end

  # The window a floor is played in.
  #
  # This class holds the `CellGrid` and the camera over it. It also holds the
  # rule for drawing one tile. Every change to where the window points goes
  # through here.
  class MapPane
    # What the grid asks for its cells.
    getter cells : FloorCells

    # The widget itself. A caller puts it in a tree.
    getter grid : Widgets::CellGrid(Tile)

    # Cells kept between the followed square and the edge of the window. The
    # camera does not move while the square is further in than this.
    property margin : Int32 = 6

    # Squares kept clear around the character when a modal box covers part of
    # the window.
    property avoid_margin : Int32 = 3

    # What the character can see from where they stand. `nil` draws every
    # square, which is what a pane with no game behind it does.
    #
    # A square outside this draws as `Palette::UNSEEN`. Nothing on it draws
    # either. A mark is something standing on a square, and a square the
    # character cannot see shows nothing standing on it.
    property sight : FieldOfView? = nil

    # The square the examine cursor is on. `nil` when there is no cursor.
    #
    # The cursor draws over whatever is on the square. It does not replace it.
    # The cursor marks its square. It leaves the glyph on that square
    # readable.
    property cursor : {Int32, Int32}? = nil

    # What is standing on a square. It draws over the terrain. It is not
    # written into the floor.
    #
    # The character goes here now. Monsters and dropped items go here later.
    # Whatever owns the game state fills this table. A pane draws a floor. It
    # holds nothing about the creatures on it.
    getter marks : Hash({Int32, Int32}, Look) = {} of {Int32, Int32} => Look

    # Squares offered as an answer to a question.
    #
    # Each keeps its own glyph and its own colour. Only the background
    # changes. A person choosing between four doors has to see which door is
    # which.
    getter highlights : Set({Int32, Int32}) = Set({Int32, Int32}).new

    def initialize(floor : Floor)
      @cells = FloorCells.new floor
      @grid = Widgets::CellGrid.new @cells
      @grid.on_draw = ->(view : TermBuf::View, x : Int32, y : Int32, tile : Tile) do
        look = if seen? x, y
                 @marks[{x, y}]? || Palette[tile.terrain]
               else
                 Palette::UNSEEN
               end

        style = look.style
        style = style.bg Palette::OFFERED if @highlights.includes?({x, y})

        here = @cursor
        style = style.reverse if here && here[0] == x && here[1] == y

        view.write_char 0, 0, look.glyph, style
        nil
      end
    end

    # Whether the character can see *x*, *y*.
    #
    # A pane with no field of view set sees everything. A spec that is not
    # about sight then needs to say nothing about sight.
    def seen?(x : Int32, y : Int32) : Bool
      found = @sight
      found ? found.includes?(x, y) : true
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

    # Which floor is being shown.
    def floor : Floor
      @cells.floor
    end

    # Shows *floor* instead, from its top left corner.
    def floor=(floor : Floor) : Floor
      @cells.floor = floor
      @grid.scroll_to 0, 0
      clear_marks
      clear_highlights
      @sight = nil
      floor
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
    # floor.
    def center_on(x : Int32, y : Int32) : Nil
      @grid.center_on x, y
    end

    # Which square of the floor is at *screen_x*, *screen_y* of the buffer.
    # `nil` when the pointer is not over a square.
    def cell_at_screen(screen_x : Int32, screen_y : Int32) : {Int32, Int32}?
      @grid.cell_at_screen screen_x, screen_y
    end

    # Where the floor's *x*, *y* is drawn, in buffer coordinates. `nil` when
    # that square is not showing.
    def screen_of(x : Int32, y : Int32) : {Int32, Int32}?
      @grid.screen_of x, y
    end

    # Where the camera is.
    def camera : {Int32, Int32}
      {@grid.scroll_x, @grid.scroll_y}
    end

    # Which square is in the middle of the window.
    #
    # A window larger than the floor shows the floor in one corner of itself.
    # The middle of such a window is past the edge of the floor. The answer is
    # clamped onto the floor, because every caller wants a square that exists.
    def middle : {Int32, Int32}
      room = @grid.viewport_size
      here = {@grid.scroll_x + room[0] // 2, @grid.scroll_y + room[1] // 2}

      {here[0].clamp(0, Math.max(floor.columns - 1, 0)),
       here[1].clamp(0, Math.max(floor.rows - 1, 0))}
    end
  end
end
