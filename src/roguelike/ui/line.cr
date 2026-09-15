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

    # One piece of the row.
    record Span, column : Int32, text : String, style : Style

    # The pieces, in the order they were written.
    getter spans : Array(Span) = [] of Span

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

    # Takes everything off the row.
    def clear : Nil
      return if @spans.empty?

      @spans.clear
      invalidate_layout
    end

    # Everything on the row, in column order, with nothing between the
    # pieces. For a spec that reads what a row says.
    def text : String
      @spans.sort_by(&.column).map(&.text).join
    end

    def intrinsic_width(policy : TermBuf::Unicode::WidthPolicy) : Layout::Intrinsic
      wanted = @spans.max_of? { |span| span.column + span.text.size } || 0

      Layout::Intrinsic.new 1, Math.max(wanted, 1)
    end

    def height_for_width(width : Int32, policy : TermBuf::Unicode::WidthPolicy) : Int32
      1
    end

    def draw(view : View) : Nil
      return if view.height <= 0

      @spans.each do |span|
        next if span.column >= view.width

        room = view.width - span.column
        text = span.text
        text = "#{text[0, Math.max(room - 1, 0)]}#{ELLIPSIS}" if text.size > room

        view.write span.column, 0, text, span.style
      end
    end
  end
end
