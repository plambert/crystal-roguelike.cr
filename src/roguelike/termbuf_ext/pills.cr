require "termbuf-widgets"

module TermBuf::Widgets
  # Short labels side by side, each on a ground of its own.
  #
  #     pills = Pills.new
  #     pills.pills = [Pills::Pill.new("hungry", warm), Pills::Pill.new("well fed", green)]
  #
  #      hungry   well fed
  #
  # A pill is its text with `PAD` cells of its own ground on each side.
  # `GAP` cells of the widget's ground part two pills. A pill that does not
  # fit on what is left of a row starts the next row, so the widget is as
  # many rows tall as its pills need at its width. A pill wider than a whole
  # row is cut and ends with `ELLIPSIS`.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`.
  class Pills < Widget
    # One label and the style it is drawn in. The style's background is the
    # pill's ground.
    record Pill, text : String, style : Style

    # The cells of the pill's own ground on each side of its text.
    PAD = 1

    # The cells between two pills on one row.
    GAP = 1

    # What ends a pill cut short at the right edge.
    ELLIPSIS = "…"

    # The pills, in the order they are laid out.
    getter pills : Array(Pill) = [] of Pill

    def initialize
      @width = Layout::Sizing.grow
    end

    # Puts *pills* in place of the ones there were.
    def pills=(pills : Array(Pill)) : Array(Pill)
      return pills if pills == @pills

      @pills = pills
      invalidate_layout
      pills
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      return Layout::Intrinsic.new(0, 0) if @pills.empty?

      widths = @pills.map { |pill| span pill, policy }
      Layout::Intrinsic.new widths.max, widths.sum + GAP * (widths.size - 1)
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      return 0 if @pills.empty?

      places(width, policy).max_of(&.[1]) + 1
    end

    def draw(view : View) : Nil
      return if view.width <= 0

      places(view.width, view.policy).each_with_index do |(column, row), index|
        break if row >= view.height

        pill = @pills[index]
        room = view.width - column - 2 * PAD
        next if room <= 0

        text = Unicode.ellipsize pill.text, room, ELLIPSIS, view.policy
        padding = " " * PAD
        view.write column, row, "#{padding}#{text}#{padding}", pill.style
      end
    end

    # How many cells *pill* takes, its padding included.
    private def span(pill : Pill, policy : Unicode::WidthPolicy) : Int32
      Unicode.string_width(pill.text, policy) + 2 * PAD
    end

    # The column and the row each pill starts at, *width* cells across.
    private def places(width : Int32, policy : Unicode::WidthPolicy) : Array({Int32, Int32})
      column = 0
      row = 0
      @pills.map do |pill|
        wide = span pill, policy
        if column > 0 && column + wide > width
          column = 0
          row += 1
        end

        at = {column, row}
        column += wide + GAP
        at
      end
    end
  end
end
