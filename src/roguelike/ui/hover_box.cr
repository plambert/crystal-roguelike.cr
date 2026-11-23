require "../../crystal-roguelike"

module Roguelike::Ui
  # What stands on one map square and the items lying there, in a box beside
  # the pointer.
  #
  # Hover mode puts it up in place of the list in the info panel. `Play`
  # decides when it goes up and when it comes down. This class decides what
  # it says and where it sits.
  #
  # It sits beside the square and never on it. It goes to the right of the
  # square when it fits there and to the left when it does not. When neither
  # side has room it goes below the square, or above it. It is moved up or
  # down to stay on the screen.
  class HoverBox < Tooltip
    # What the line above the items says.
    HEADING = "Here"

    # The columns left clear between the square and the box.
    GAP = 1

    # The rows and columns a box with no text takes: the border and the
    # padding.
    CHROME = {4, 2}

    # The square it is beside, in buffer coordinates. `nil` while it is down.
    getter cell : {Int32, Int32}? = nil

    # Its width and height, border and all, while it is up.
    @size : {Int32, Int32} = {LEAST_WIDTH, 0}

    # Whether something holds the box off the screen while it is up. `Play`
    # answers whether a modal box has the screen.
    #
    # Whatever closes that box is a key or a click, and either takes this box
    # down for good. So it does not come back when the modal box goes.
    property held_back : Proc(Bool)? = nil

    # The lines for *feature* and *items*. The feature comes first, then a
    # heading and one item to a line. The heading is left out when there are
    # no items. Empty when there is neither, which puts no box up.
    #
    # The lines fit in `MOST_LINES`, the feature line among them. A pile too
    # long for the rest names one fewer item and says how many are left.
    def self.lines(items : Array(String), feature : String? = nil) : Array(String)
      top = feature ? [feature] : [] of String
      return top if items.empty?

      room = MOST_LINES - top.size - 1
      return top + [HEADING] + items if items.size <= room

      named = room - 1
      top + [HEADING] + items.first(named) + ["and #{items.size - named} more"]
    end

    # The width and height of a box holding *lines*.
    def self.size(lines : Array(String),
                  policy : TermBuf::Unicode::WidthPolicy = TermBuf::Unicode.policy) : {Int32, Int32}
      widest = lines.max_of? { |line| TermBuf::Unicode.string_width line, policy } || 0
      {(widest + CHROME[0]).clamp(LEAST_WIDTH, WIDTH), lines.size + CHROME[1]}
    end

    # Where the top left corner of a box of *size* goes beside *cell*, on
    # *screen*.
    def self.place(screen : Rect, cell : {Int32, Int32}, size : {Int32, Int32}) : {Int32, Int32}
      width, height = size
      x, y = cell

      right = x + 1 + GAP
      return {right, beside(screen, y, height)} if right + width - 1 <= screen.right

      left = x - GAP - width
      return {left, beside(screen, y, height)} if left >= screen.x

      across = (x - width // 2).clamp(screen.x, Math.max(screen.x, screen.right - width + 1))
      below = y + 1
      return {across, below} if below + height - 1 <= screen.bottom

      {across, Math.max(screen.y, y - height)}
    end

    # The top row of a box of *height* beside row *y*. It starts on that row
    # and hangs down, and it is moved up when it would run off the bottom.
    private def self.beside(screen : Rect, y : Int32, height : Int32) : Int32
      top = Math.min(y, screen.bottom - height + 1)
      Math.max top, screen.y
    end

    # Puts *feature* and *items* up beside *cell*, pinned to *map*. Takes the
    # box down when there is neither.
    def show_at(app : Widgets::App, map : Widgets::Widget, cell : {Int32, Int32},
                items : Array(String), feature : String? = nil) : Nil
      lines = HoverBox.lines items, feature
      return hide if lines.empty?

      @size = HoverBox.size lines, app.tree.policy
      at = HoverBox.place app.tree.screen, cell, @size
      box = map.rect
      dx = at[0] - box.x
      dy = at[1] - box.y

      show app, map, lines, dx, dy
      @cell = cell

      # The corner goes exactly where `.place` put it. The layout has nothing
      # to flip, because the place is already on the screen.
      self.floating = Layout::Floating.on map,
        Layout::AttachPoint::LeftTop, Layout::AttachPoint::LeftTop,
        dx: dx, dy: dy, z: LAYER, capture: false, overflow: Layout::Overflow::Clamp
    end

    # The width `.size` worked out.
    def width : Layout::Sizing
      Layout::Sizing.fixed @size[0]
    end

    # Whether it is left out of the layout and the drawing.
    def hidden? : Bool
      super || (@held_back.try(&.call) || false)
    end

    # Takes it down.
    def hide : Nil
      @cell = nil
      super
    end
  end
end
