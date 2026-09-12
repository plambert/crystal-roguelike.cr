require "../src/roguelike/termbuf_ext/cell_grid"

# What the `cell_grid` example looks at.
module Demo
  # What one cell of the field looks like.
  record Mark, glyph : Char, style : TermBuf::Style

  # A large field with landmarks in it. For looking at a camera.
  #
  # A camera over an even texture cannot be read. Every part of the field
  # looks the same. So this field carries four kinds of landmark. Each says
  # something the others do not.
  #
  # * Guide lines. The rows sit closer together than the columns. A window is
  #   shorter than it is wide. One line of each kind should be in view.
  # * The coordinates of every crossing, written beside it. They say exactly
  #   where the window is.
  # * A diagonal. Its place in the window moves when either axis moves. It is
  #   the one landmark that answers both axes at once.
  # * A plus in the middle of the field. It is small enough to see all at
  #   once. Its colour runs warm in the centre and cool at the tips.
  #
  # This class is a `TermBuf::Widgets::Cells` subclass. A source that works
  # out what it holds is written this way. A level in a game has the same
  # shape.
  class Field < TermBuf::Widgets::Cells(Mark)
    alias Style = TermBuf::Style
    alias Color = TermBuf::Color

    # Cells across and down.
    SIZE = 200

    # Cells between guide lines, across and down.
    #
    # A window is wider than it is tall. So the rows sit closer together than
    # the columns.
    STEP_X = 20
    STEP_Y = 10

    # The middle, where the plus is.
    CENTRE = SIZE // 2

    # How far each arm of the plus reaches. How far it is from the arm's own
    # middle to its edge.
    #
    # The whole plus fits in one window. A larger plus would fill the view and
    # read as a wall.
    ARM   = 7
    THICK = 1

    # Fixed styles. The style table interns each one once.
    #
    # A style built inside a draw call interns one style per cell. One frame
    # bounds that count by the screen size. An animation does not bound it at
    # all. Every style here comes from a table.
    DIM      = Style::DEFAULT.fg Color.rgb(0x3A, 0x3F, 0x4A)
    RULE     = Style::DEFAULT.fg Color.rgb(0x3A, 0x55, 0x77)
    CROSSING = Style::DEFAULT.fg Color.rgb(0x5A, 0x86, 0xBB)
    LEGEND   = Style::DEFAULT.fg Color.rgb(0xE8, 0xA0, 0x3C)
    SLASH    = Style::DEFAULT.fg Color.rgb(0x4C, 0xA8, 0x7A)

    # The plus. Warm in the middle. Cool at the tips.
    #
    # There is one style per whole cell of reach. The style table stops
    # growing after the first frame that draws the plus.
    ARMS = Array.new(ARM + 1) do |reach|
      part = reach / ARM
      Style::DEFAULT.fg Color.rgb(
        (0xFF - 0x60 * part).to_i,
        (0xE8 - 0xB0 * part).to_i,
        (0x70 + 0x80 * part).to_i)
    end

    BLANK    = Mark.new ' ', DIM
    STIPPLE  = Mark.new '·', DIM
    DOWN     = Mark.new '│', RULE
    ACROSS   = Mark.new '─', RULE
    CORNER   = Mark.new '┼', CROSSING
    DIAGONAL = Mark.new '╲', SLASH

    def columns : Int32
      SIZE
    end

    def rows : Int32
      SIZE
    end

    def cell(x : Int32, y : Int32) : Mark
      if reach = arm_at x, y
        return Mark.new '█', ARMS[reach]
      end

      if glyph = legend_at x, y
        return Mark.new glyph, LEGEND
      end

      return DIAGONAL if x == y

      down = x % STEP_X == 0
      across = y % STEP_Y == 0

      return CORNER if down && across
      return DOWN if down
      return ACROSS if across

      x.even? ? STIPPLE : BLANK
    end

    # How far along an arm of the plus *x*, *y* is. Answers `nil` when it is
    # outside the plus.
    def arm_at(x : Int32, y : Int32) : Int32?
      across = (x - CENTRE).abs
      down = (y - CENTRE).abs

      return down if across <= THICK && down <= ARM
      return across if down <= THICK && across <= ARM

      nil
    end

    # The character of a crossing's label that belongs at *x*, *y*.
    #
    # A label starts one cell to the right of the crossing it names. The
    # crossing glyph then still draws.
    def legend_at(x : Int32, y : Int32) : Char?
      return unless y % STEP_Y == 0

      start = (x // STEP_X) * STEP_X
      offset = x - start - 1
      return unless offset >= 0

      text = "#{start},#{y}"
      return unless offset < text.size

      text[offset]
    end
  end
end
