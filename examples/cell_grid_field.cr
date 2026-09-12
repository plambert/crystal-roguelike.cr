require "../src/roguelike/termbuf_ext/cell_grid"

# What the `cell_grid` example looks at.
module Demo
  # What one cell of the field looks like.
  record Mark, glyph : Char, style : TermBuf::Style

  # A large field with landmarks in it, for looking at a camera.
  #
  # A camera over an even texture cannot be read: everything looks the same
  # wherever the window is. So there are four kinds of landmark, each saying
  # something the others do not.
  #
  # * Guide lines, closer together down than across, because a window is
  #   shorter than it is wide and one of each should be in view.
  # * The coordinates of every crossing, written beside it, which say exactly
  #   where the window is.
  # * A diagonal, whose place in the window moves when either axis does — the
  #   one landmark that answers both at once.
  # * A plus in the middle of the field, small enough to see all of at once,
  #   coloured from warm in the centre to cool at the tips.
  #
  # It is a `TermBuf::Widgets::Cells` subclass, which is how a source that
  # works out what it holds is meant to be written — the same shape a level in
  # a game has.
  class Field < TermBuf::Widgets::Cells(Mark)
    alias Style = TermBuf::Style
    alias Color = TermBuf::Color

    # Cells across and down.
    SIZE = 200

    # Cells between guide lines, across and down. A window is wider than it is
    # tall, so the rows are closer together than the columns.
    STEP_X = 20
    STEP_Y = 10

    # The middle, where the plus is.
    CENTRE = SIZE // 2

    # How far each arm of the plus reaches, and how far it is from the arm's
    # own middle to its edge. Small enough that the whole plus is in one
    # window, which is what makes it a shape rather than a wall.
    ARM   = 7
    THICK = 1

    # Fixed styles, interned once.
    #
    # A style worked out per cell per frame interns one per cell, which is
    # bounded by the screen for one frame and by nothing at all across an
    # animation. Everything here comes from a table instead.
    DIM      = Style::DEFAULT.fg Color.rgb(0x3A, 0x3F, 0x4A)
    RULE     = Style::DEFAULT.fg Color.rgb(0x3A, 0x55, 0x77)
    CROSSING = Style::DEFAULT.fg Color.rgb(0x5A, 0x86, 0xBB)
    LEGEND   = Style::DEFAULT.fg Color.rgb(0xE8, 0xA0, 0x3C)
    SLASH    = Style::DEFAULT.fg Color.rgb(0x4C, 0xA8, 0x7A)

    # The plus, warm in the middle and cool at the tips. One style per whole
    # cell of reach, so the table stops growing after the first frame.
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

    # How far along an arm of the plus *x*, *y* is, or `nil` when it is
    # outside it.
    def arm_at(x : Int32, y : Int32) : Int32?
      across = (x - CENTRE).abs
      down = (y - CENTRE).abs

      return down if across <= THICK && down <= ARM
      return across if down <= THICK && across <= ARM

      nil
    end

    # The character of a crossing's label that belongs at *x*, *y*.
    #
    # A label sits one cell to the right of the crossing it names, so the
    # crossing itself is still drawn.
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
