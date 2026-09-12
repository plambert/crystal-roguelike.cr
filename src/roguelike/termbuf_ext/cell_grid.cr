require "./cells"

module TermBuf::Widgets
  # A window over a field of cells, which draws the ones that are showing and
  # no others.
  #
  #     grid = CellGrid.new level
  #     grid.on_draw = ->(view : View, x : Int32, y : Int32, tile : Tile) do
  #       view.write_char 0, 0, tile.glyph, tile.style
  #     end
  #
  #     grid.center_on player.x, player.y
  #
  # What makes it a window rather than a picture is that it holds no widget
  # per cell and asks its `Cells` only about the cells in view, so a level of
  # a million costs what the pane it is drawn in costs.
  #
  # It is a `Scrolls`, so a `Scrollbar` attaches to it the way one attaches to
  # a `VirtualList`. It scrolls itself rather than sitting in a scroll panel,
  # because a panel would have to be as large as the whole field for the
  # clipping to have anything to clip.
  #
  # Moving the camera changes no rectangle, so it costs no layout: the next
  # frame draws different cells in the same box.
  class CellGrid(T) < Widget
    include Scrolls

    # Where the cells come from.
    property cells : Cells(T)

    # How many cells one notch of the wheel moves.
    property wheel : Int32 = 3

    # What draws one cell, or `nil` for the default, which writes what the
    # cell answers to `#to_s`.
    #
    # Called with a view cut to that cell — one cell wide and one tall — and
    # the cell's own coordinates in the field, which are what a caller needs
    # to look up anything the cell does not carry itself.
    property on_draw : Proc(View, Int32, Int32, T, Nil)? = nil

    # Whether the keyboard can land here.
    #
    # False by default: a map pane in a game whose application binds its own
    # movement keys should not be in the tab order. Set it and the arrows,
    # page keys, `Home` and `End` move the camera.
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

    # The keys that move the camera. A grid is given its own copy, so
    # rebinding one leaves the rest alone.
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

    # A grid is a window both ways.
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

    # How many rows a page key moves, which is a window's worth.
    def page : Int32
      Math.max viewport_size[1], 1
    end

    # Moves the camera, stopping at the edges.
    def scroll_by(dx : Int32, dy : Int32) : Nil
      scroll_to @camera_x + dx, @camera_y + dy
    end

    # :ditto:
    def scroll_by(*, dx : Int32 = 0, dy : Int32 = 0) : Nil
      scroll_by dx, dy
    end

    # Puts *x*, *y* at the top left of the window, as near as the edges allow.
    #
    # A field smaller than the window has nowhere to go, so this leaves the
    # camera at the origin rather than showing blank cells beside it.
    def scroll_to(x : Int32, y : Int32) : Nil
      limit = max_scroll

      @camera_x = x.clamp 0, limit[0]
      @camera_y = y.clamp 0, limit[1]
    end

    # Puts *x*, *y* in the middle of the window, as near as the edges allow.
    def center_on(x : Int32, y : Int32) : Nil
      room = viewport_size

      scroll_to x - room[0] // 2, y - room[1] // 2
    end

    # Moves the camera as little as it takes to leave *x*, *y* at least
    # *margin* cells from every edge of the window.
    #
    # The dead zone a camera wants: a player walking about the middle of the
    # screen moves nothing, and the view only follows once they near an edge.
    # A margin with no room for it — one wider than half the window — centres
    # instead, because there is no position that satisfies it.
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

    # :ditto: for rows.
    def visible_y : Range(Int32, Int32)
      window @camera_y, viewport_size[1], @cells.rows
    end

    private def window(camera : Int32, room : Int32, extent : Int32) : Range(Int32, Int32)
      return (0...0) if room <= 0 || extent <= 0

      first = camera.clamp 0, Math.max(extent - 1, 0)
      (first...Math.min(first + room, extent))
    end

    # Yields the coordinates and the cell of everything showing, in reading
    # order.
    def each_visible(& : Int32, Int32, T ->) : Nil
      across = visible_x

      visible_y.each do |row|
        across.each { |column| yield column, row, @cells.cell(column, row) }
      end
    end

    # Which cell of the field is at *view_x*, *view_y* of the window, or `nil`
    # when that spot is outside the window or past the edge of the field.
    #
    # What a mouse report wants next: `Layout::Tree#hit` says the pointer is
    # over this widget, and `Widget#content` turns the screen cell into one of
    # these.
    def cell_at(view_x : Int32, view_y : Int32) : {Int32, Int32}?
      room = viewport_size
      return unless 0 <= view_x < room[0] && 0 <= view_y < room[1]

      spot = {view_x + @camera_x, view_y + @camera_y}
      return unless @cells.contains? spot[0], spot[1]

      spot
    end

    # Where in the window the field's *x*, *y* is drawn, or `nil` when it is
    # not showing. The inverse of `#cell_at`.
    def view_of(x : Int32, y : Int32) : {Int32, Int32}?
      return unless @cells.contains? x, y

      spot = {x - @camera_x, y - @camera_y}
      room = viewport_size
      return unless 0 <= spot[0] < room[0] && 0 <= spot[1] < room[1]

      spot
    end

    # Turns a cell of the screen into one of the field, for a widget holding
    # a mouse event whose coordinates are the buffer's.
    def cell_at_screen(screen_x : Int32, screen_y : Int32) : {Int32, Int32}?
      box = content

      cell_at screen_x - box.x, screen_y - box.y
    end

    # ------------------------------------------------------------ the widget

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.new 1, Math.max(@cells.columns, 1)
    end

    # As tall as the field. A grid sized to grow never uses this; one sized to
    # fit is as tall as what it holds.
    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      @cells.rows
    end

    # Answers a wheel notch, and lets everything else past.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      context.consume if scroll_wheel event
    end

    # Draws the cells that are showing, one view each.
    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      # A window that grew may be showing past the edge of the field, which
      # the camera has had no reason to notice until now.
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
