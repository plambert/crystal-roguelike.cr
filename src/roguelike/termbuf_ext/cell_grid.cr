require "./cells"

module TermBuf::Widgets
  # A window over a field of cells. It draws the cells that are showing and no
  # others.
  #
  #     grid = CellGrid.new floor
  #     grid.on_draw = ->(view : View, x : Int32, y : Int32, tile : Tile) do
  #       view.write_char 0, 0, tile.glyph, tile.style
  #     end
  #
  #     grid.center_on player.x, player.y
  #
  # A grid holds no widget per cell. It asks its `Cells` only about the cells
  # in view. The work is the size of the pane. It is not the size of the
  # field.
  #
  # A grid is a `Scrolls`. A `Scrollbar` attaches to it the way one attaches to
  # a `VirtualList`. A grid scrolls itself. It does not sit inside a scroll
  # panel. Such a panel would have to be as large as the whole field for the
  # clipping to have anything to clip.
  #
  # Moving the camera changes no rectangle. No layout runs. The next frame
  # draws different cells in the same box.
  class CellGrid(T) < Widget
    include Scrolls

    # Where the cells come from.
    property cells : Cells(T)

    # How many cells one notch of the wheel moves.
    property wheel : Int32 = 3

    # What draws one cell. `nil` uses the default. The default writes what
    # the cell answers to `#to_s`.
    #
    # The grid calls this with a view cut to that cell. The view is one cell
    # wide and one cell tall. The grid also passes the cell's own coordinates
    # in the field. A caller uses those to look up anything the cell does not
    # carry itself.
    property on_draw : Proc(View, Int32, Int32, T, Nil)? = nil

    # Whether the keyboard can land here.
    #
    # This is false by default. A game binds its own movement keys. Its map
    # pane should stay out of the tab order.
    #
    # Set this true and the arrows, the page keys, `Home` and `End` move the
    # camera.
    property? takes_focus : Bool = false

    # The leftmost column showing.
    @camera_x : Int32 = 0

    # The topmost row showing.
    @camera_y : Int32 = 0

    def initialize(@cells : Cells(T),
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.grow,
                   style : Style? = nil)
      @width = width
      @height = height
      @style = style
      @keymap = CellGrid.moves self
    end

    # The keys that move the camera. Each grid gets its own copy. Rebinding
    # one grid's keys leaves every other grid alone.
    def self.moves(grid : CellGrid(T)) : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Left"), "a column back",
          ->(_context : Context) { grid.scroll_by -1, 0 }
        map.bind Key.parse("Right"), "a column on",
          ->(_context : Context) { grid.scroll_by 1, 0 }
        map.bind Key.parse("Up"), "a row back",
          ->(_context : Context) { grid.scroll_by 0, -1 }
        map.bind Key.parse("Down"), "a row on",
          ->(_context : Context) { grid.scroll_by 0, 1 }
        map.bind Key.parse("PageUp"), "a window back",
          ->(_context : Context) { grid.scroll_by 0, -grid.page }
        map.bind Key.parse("PageDown"), "a window on",
          ->(_context : Context) { grid.scroll_by 0, grid.page }
        map.bind Key.parse("Home"), "the top left",
          ->(_context : Context) { grid.scroll_to 0, 0 }
        map.bind Key.parse("End"), "the bottom right",
          ->(_context : Context) { grid.scroll_to grid.cells.columns, grid.cells.rows }
      end
    end

    def focusable? : Bool
      takes_focus?
    end

    # A grid is a window on both axes.
    def clip_x? : Bool
      true
    end

    # :ditto:
    def clip_y? : Bool
      true
    end

    # ------------------------------------------------------------- the window

    # Cells the field comes to.
    def content_size : {Int32, Int32}
      @cells.size
    end

    # Cells there are to show it in.
    def viewport_size : {Int32, Int32}
      box = content
      {Math.max(box.width, 0), Math.max(box.height, 0)}
    end

    # The leftmost column showing.
    def scroll_x : Int32
      @camera_x
    end

    # The topmost row showing.
    def scroll_y : Int32
      @camera_y
    end

    # How many rows a page key moves. One window of rows.
    def page : Int32
      Math.max viewport_size[1], 1
    end

    # Moves the camera. Stops at the edges.
    def scroll_by(dx : Int32, dy : Int32) : Nil
      scroll_to @camera_x + dx, @camera_y + dy
    end

    # :ditto:
    def scroll_by(*, dx : Int32 = 0, dy : Int32 = 0) : Nil
      scroll_by dx, dy
    end

    # Puts *x*, *y* at the top left of the window. Stops at the edges.
    #
    # A field smaller than the window has nowhere to scroll. The camera then
    # stays at the origin. It does not show blank cells beside the field.
    def scroll_to(x : Int32, y : Int32) : Nil
      limit = max_scroll

      @camera_x = x.clamp 0, limit[0]
      @camera_y = y.clamp 0, limit[1]
    end

    # Puts *x*, *y* in the middle of the window. Stops at the edges.
    def center_on(x : Int32, y : Int32) : Nil
      room = viewport_size

      scroll_to x - room[0] // 2, y - room[1] // 2
    end

    # Moves the camera as little as it takes to leave *x*, *y* at least
    # *margin* cells from every edge of the window.
    #
    # This is a dead zone. A player walking about the middle of the screen
    # moves the camera not at all. The view follows once they near an edge.
    #
    # A margin wider than half the window has no position that satisfies it.
    # This method centres instead.
    def reveal(x : Int32, y : Int32, margin : Int32 = 0) : Nil
      room = viewport_size
      return if room[0] <= 0 || room[1] <= 0

      if margin * 2 >= room[0] || margin * 2 >= room[1]
        center_on x, y
        return
      end

      scroll_to axis(@camera_x, x, room[0], margin),
        axis(@camera_y, y, room[1], margin)
    end

    # Moves the camera so that *x*, *y* and *margin* cells around it fall
    # outside *area*.
    #
    # *area* is in window coordinates. A modal box drawn over part of the
    # window is one. The camera moves the least it can. It tries above the
    # area, below it, left of it and right of it, and takes the smallest move
    # that clears the area once the edges of the field are allowed for.
    #
    # The camera does not move at all when *x*, *y* is already clear, or when
    # the field is too small for any move to clear it.
    def avoid(x : Int32, y : Int32, area : Rect, margin : Int32 = 1) : Bool
      room = viewport_size
      return false if room[0] <= 0 || room[1] <= 0
      return false if area.empty?

      spot = {x - @camera_x, y - @camera_y}
      return false unless overlaps? spot, area, margin

      wanted = {
        {@camera_x, @camera_y + (spot[1] - (area.y - margin - 1))},
        {@camera_x, @camera_y - ((area.bottom + margin) - spot[1])},
        {@camera_x + (spot[0] - (area.x - margin - 1)), @camera_y},
        {@camera_x - ((area.right + margin) - spot[0]), @camera_y},
      }

      limit = max_scroll
      here = {@camera_x, @camera_y}

      chosen = wanted
        .map { |camera| {camera[0].clamp(0, limit[0]), camera[1].clamp(0, limit[1])} }
        .reject { |camera| overlaps?({x - camera[0], y - camera[1]}, area, margin) }
        .min_by? { |camera| (camera[0] - here[0]).abs + (camera[1] - here[1]).abs }

      return false unless chosen

      @camera_x, @camera_y = chosen
      true
    end

    # Whether *margin* cells around *spot* reach into *area*.
    private def overlaps?(spot : {Int32, Int32}, area : Rect, margin : Int32) : Bool
      spot[0] + margin >= area.x && spot[0] - margin <= area.right - 1 &&
        spot[1] + margin >= area.y && spot[1] - margin <= area.bottom - 1
    end

    # Where one axis of the camera has to move to keep *spot* off the edge.
    private def axis(camera : Int32, spot : Int32, room : Int32,
                     margin : Int32) : Int32
      low = camera + margin
      high = camera + room - 1 - margin

      return spot - margin if spot < low
      return spot - room + 1 + margin if spot > high

      camera
    end

    # --------------------------------------------------------------- geometry

    # The columns of the field that are showing.
    def visible_x : Range(Int32, Int32)
      window @camera_x, viewport_size[0], @cells.columns
    end

    # The rows of the field that are showing.
    def visible_y : Range(Int32, Int32)
      window @camera_y, viewport_size[1], @cells.rows
    end

    private def window(camera : Int32, room : Int32, extent : Int32) : Range(Int32, Int32)
      return (0...0) if room <= 0 || extent <= 0

      first = camera.clamp 0, Math.max(extent - 1, 0)
      (first...Math.min(first + room, extent))
    end

    # Yields the coordinates and the cell of everything showing. In reading
    # order.
    def each_visible(& : Int32, Int32, T ->) : Nil
      across = visible_x

      visible_y.each do |row|
        across.each { |column| yield column, row, @cells.cell(column, row) }
      end
    end

    # Which cell of the field is at *view_x*, *view_y* of the window.
    #
    # Answers `nil` when that spot is outside the window. Answers `nil` when
    # it is past the edge of the field.
    #
    # A mouse report needs this. `Layout::Tree#hit` answers that the pointer
    # is over this widget. `Widget#content` turns the screen cell into a window
    # cell.
    def cell_at(view_x : Int32, view_y : Int32) : {Int32, Int32}?
      room = viewport_size
      return unless 0 <= view_x < room[0] && 0 <= view_y < room[1]

      spot = {view_x + @camera_x, view_y + @camera_y}
      return unless @cells.contains? spot[0], spot[1]

      spot
    end

    # Where in the window the field's *x*, *y* draws. Answers `nil` when it is
    # not showing. This is the inverse of `#cell_at`.
    def view_of(x : Int32, y : Int32) : {Int32, Int32}?
      return unless @cells.contains? x, y

      spot = {x - @camera_x, y - @camera_y}
      room = viewport_size
      return unless 0 <= spot[0] < room[0] && 0 <= spot[1] < room[1]

      spot
    end

    # Turns a cell of the screen into a cell of the field. A mouse event
    # carries buffer coordinates. This method takes those.
    def cell_at_screen(screen_x : Int32, screen_y : Int32) : {Int32, Int32}?
      box = content

      cell_at screen_x - box.x, screen_y - box.y
    end

    # Where on the screen the field's *x*, *y* draws, in buffer coordinates.
    # Answers `nil` when it is not showing. This is the inverse of
    # `#cell_at_screen`.
    #
    # Putting the terminal's own cursor on a cell needs this. A terminal
    # places its cursor in buffer coordinates.
    def screen_of(x : Int32, y : Int32) : {Int32, Int32}?
      spot = view_of x, y
      return unless spot

      box = content
      {spot[0] + box.x, spot[1] + box.y}
    end

    # ------------------------------------------------------------ the widget

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.new 1, Math.max(@cells.columns, 1)
    end

    # As tall as the field.
    #
    # A grid sized to grow never uses this. A grid sized to fit is as tall as
    # the field it holds.
    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @cells.rows
    end

    # Answers a wheel notch. Lets every other event past.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      context.consume if scroll_wheel event
    end

    # Draws the cells that are showing. One view for each.
    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      # A window that grew may show past the edge of the field. The camera
      # has had no reason to notice that until now.
      scroll_to @camera_x, @camera_y

      hook = @on_draw
      left = @camera_x
      top = @camera_y

      each_visible do |column, row, held|
        spot = view.view Rect.new(column - left, row - top, 1, 1)

        if hook
          hook.call spot, column, row, held
        else
          spot.write 0, 0, held.to_s
        end
      end
    end
  end
end
