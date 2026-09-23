module Roguelike::Ui
  # One row of text, written at columns the caller picks.
  #
  #     line.put 0, "ac", Palette::FAINT
  #     line.put 3, "5", Palette::STRONG
  #
  # A `Widgets::Label` holds one string in one style. A status row is several
  # short pieces in several styles, each at a column of its own so the ones
  # under it line up. This holds those pieces.
  #
  # A piece written past the right edge is cut there and marked with
  # `ELLIPSIS`, so a name that did not fit reads as one that did not fit.
  # Nothing wraps: a row that wrapped would push everything under it down by
  # one.
  class Line < Widgets::Widget
    # What marks a piece that ran off the right edge.
    ELLIPSIS = '…'

    # Which edge a piece is placed from.
    enum Edge
      # From the left, at the column the caller named.
      Left

      # From the right, so the piece ends at the right edge of the row.
      Right
    end

    # One piece of the row.
    record Span, column : Int32, text : String, style : Style,
      edge : Edge = Edge::Left

    # How many cells are left clear between the last left piece and the first
    # right one.
    GAP = 1

    # How many cells a caller that marks its rows leaves clear at the left
    # for `#marks` to go in.
    #
    # The room is kept whether or not a row is marked, so a row does not move
    # when the pointer crosses it.
    INDENT = 2

    # A row's two marks: one at the near edge and one at the far one.
    record Marks, near : Char, far : Char, style : Style

    # What marks this row, or `nil` for one that is not marked.
    #
    # The near mark goes in the first cell and the far one against the right
    # edge. The far one takes its cells from the text, so a name already long
    # enough to be cut is cut two cells shorter while the row is marked.
    property marks : Marks? = nil

    # The pieces, in the order they were written.
    getter spans : Array(Span) = [] of Span

    # What runs when the pointer is over the row.
    #
    # It runs on every report the pointer makes, so whatever it does has to
    # be cheap and has to be the same every time.
    property on_point : Proc(Nil)? = nil

    # What runs when a button goes down on the row.
    property on_press : Proc(Nil)? = nil

    def initialize(width : Layout::Sizing = Layout::Sizing.grow)
      @width = width
      @height = Layout::Sizing.fixed 1
    end

    # Writes *text* at *column*. Answers the column after it.
    def put(column : Int32, text : String, style : Style = Style::DEFAULT) : Int32
      @spans << Span.new column, text, style
      invalidate_layout

      column + text.size
    end

    # Writes *text* against the right edge of the row.
    #
    # Where it lands is not known until the row is drawn, because it depends
    # on how wide the row turned out. A left piece that would reach it is cut
    # `GAP` cells short of it.
    def put_right(text : String, style : Style = Style::DEFAULT) : Nil
      @spans << Span.new 0, text, style, Edge::Right
      invalidate_layout
    end

    # Takes everything off the row.
    def clear : Nil
      return if @spans.empty?

      @spans.clear
      invalidate_layout
    end

    # Everything on the row, in column order, with nothing between the
    # pieces. For a spec that reads what a row says.
    #
    # A right piece comes last, whatever column it was drawn at.
    def text : String
      left, right = @spans.partition &.edge.left?

      (left.sort_by(&.column) + right).map(&.text).join
    end

    def intrinsic_width(policy : TermBuf::Unicode::WidthPolicy) : Layout::Intrinsic
      wanted = @spans.sum do |span|
        next span.text.size + GAP if span.edge.right?

        0
      end

      wanted += @spans.max_of? { |span| span.edge.right? ? 0 : span.column + span.text.size } || 0

      Layout::Intrinsic.new 1, Math.max(wanted, 1)
    end

    def height_for_width(width : Int32, policy : TermBuf::Unicode::WidthPolicy) : Int32
      1
    end

    # Takes the pointer. A row with neither hook takes nothing.
    #
    # A press is claimed, so nothing behind the sidebar answers a click that
    # landed on a row. The pointer moving is not claimed: whatever is
    # tracking where the pointer is has to hear about every report, including
    # the ones that land here.
    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      return unless event.is_a? TermBuf::Events::Mouse

      if event.action.press? && !event.button.wheel?
        pressed = @on_press
        return unless pressed

        pressed.call
        context.consume
        return
      end

      @on_point.try &.call
    end

    def draw(view : View) : Nil
      return if view.height <= 0

      # The right pieces go down first and say where the left ones stop. They
      # are placed from the right edge, so the last of them is the leftmost.
      edge = view.width

      found = @marks
      if found && edge > INDENT
        view.write 0, 0, found.near.to_s, found.style
        view.write edge - 1, 0, found.far.to_s, found.style
        edge -= 1 + GAP
      end

      @spans.each do |span|
        next unless span.edge.right?

        at = edge - span.text.size
        next if at < 0

        view.write at, 0, span.text, span.style
        edge = at - GAP
      end

      @spans.each do |span|
        next if span.edge.right?
        next if span.column >= edge

        room = edge - span.column
        text = span.text
        text = "#{text[0, Math.max(room - 1, 0)]}#{ELLIPSIS}" if text.size > room

        view.write span.column, 0, text, span.style
      end
    end
  end
end
