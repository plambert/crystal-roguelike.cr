require "termbuf-widgets"

# Extraction candidate: `TermBuf::Widgets::Pager`, for termbuf-widgets.cr.
#
# A pane of N rows shows the last N lines. A turn that produces six lines in
# a four row pane would push the first two past before anybody read them.
#
# This pager follows the newest line only while its window is at the end.
# A batch of lines too big for the pane parks the window with the first of
# them at the top, so the start of the batch is what shows. A window that is
# not at the end stays where it is as lines arrive, and a badge on the last
# row counts what is below. Nothing blocks, and no key is taken.
#
# This type is written in `TermBuf::Widgets` rather than in `Roguelike`.
# Extracting it is then a file move with no edits.
#
# One question remains open. Should this be a `VirtualList` over
# `Rows(String)` instead? A list holds a window and a selection, and a pager
# never selects, so a subclass would carry a selection it never uses.
module TermBuf::Widgets
  # Lines in a window that follows the newest line while it is at the end.
  #
  #     pager.resize 78, 4
  #     pager.show log.lines, arrived: 6
  #     pager.back    # => how far above the end the window parked
  #
  # The widget wraps what it is given to its own width. A line longer than the
  # pane becomes two lines rather than being cut.
  class Pager < Widget
    include Scrolls

    # What the newest `#fresh` source lines are drawn in. `nil` draws every
    # line in the pane's own style.
    property fresh_style : Style? = nil

    # How many of the newest source lines are drawn in `#fresh_style`.
    #
    # An owner sets this each frame. It changes how lines are drawn and
    # nothing about which lines show.
    property fresh : Int32 = 0

    # A run of characters in one wrapped line drawn in a style of its own.
    #
    # *start* and *size* count characters. The style is laid over the line's
    # own, so an underline keeps the line's color.
    record Accent, start : Int32, size : Int32, style : Style

    # What finds the accents in a wrapped line. `nil` draws none.
    #
    # It sees each line after wrapping, so an accent never spans two rows. It
    # changes how lines are drawn and nothing about which lines show.
    property accents : Proc(String, Array(Accent))? = nil

    # Cells across. An owner sets this with `#resize`.
    getter columns : Int32 = 0

    # Rows down. An owner sets this with `#resize`.
    getter rows : Int32 = 0

    # Every line, wrapped to `#columns`, oldest first.
    getter lines : Array(String) = [] of String

    # How many lines back from the newest the window sits.
    #
    # Zero is the end, where the window follows each line that arrives.
    # Anywhere else it stays on the lines it shows.
    getter back : Int32 = 0

    # How many lines one notch of the wheel moves.
    #
    # One. The pane is four rows, and three lines a notch would jump most of
    # it.
    property wheel : Int32 = 1

    # Whether an owner has asked the pane not to park for now.
    #
    # `Ui::Play` sets it while a walk, a flight or a recorded run is drawn a
    # step at a time. The window then follows every line, so the frames of a
    # walk do not leave it parked part way back. When the owner lets go, the
    # lines that arrived meanwhile park the window the way one batch would.
    getter? deferred : Bool = false

    # :ditto:
    def deferred=(wanted : Bool) : Bool
      return wanted if wanted == @deferred

      @deferred = wanted
      unless wanted
        came = @deferred_came
        @deferred_came = 0
        park came if @back == 0
      end
      wanted
    end

    # How many lines arrived while the pane was deferred.
    @deferred_came : Int32 = 0

    # The lines to draw in place of the window, by index, top to bottom.
    # `nil` draws the window.
    #
    # An owner sets this to draw the frames of a scroll that skips rows. See
    # `SampledScroll`. The pane draws the last `#rows` of them. Scrolling the
    # pane, or new text, clears it.
    property sampled : Array(Int32)? = nil

    # What the pane says while lines below the window are not showing, given
    # how many messages those are. `nil` says nothing.
    #
    # The text is drawn over the right end of the last row, so most of the
    # row stays readable.
    #
    #     pager.badge = ->(count : Int32) { " ↓ #{count} newer " }
    property badge : Proc(Int32, String)? = nil

    # What the badge is drawn in.
    property badge_style : Style = Style::DEFAULT.reverse

    # What a click on the badge runs. `nil` puts the window on the newest
    # line at once.
    property on_badge : Proc(Nil)? = nil

    # How many wrapped lines each source line became, oldest first.
    @rows_per_line = [] of Int32

    def initialize(style : Style? = nil)
      @width = Layout::Sizing.grow
      @height = Layout::Sizing.grow
      @style = style
      @source = [] of String
      @given = [] of String
    end

    # Sets the size of the pane. Wraps the text again when the width changed,
    # and keeps the window on the line at its top.
    def resize(columns : Int32, rows : Int32) : Nil
      @rows = rows

      if columns == @columns
        @back = @back.clamp 0, max_scroll[1]
        return
      end

      top = @back > 0 ? window_top : nil
      @columns = columns
      rewrap
      place top
    end

    # Shows *source*, oldest first. *arrived* is how many lines were added
    # at the end since the last call.
    #
    # The same lines a second time change nothing. An owner redraws on every
    # frame, and rewrapping text that has not moved would throw away a
    # scrolled window several times a second.
    #
    # A window at the end follows the new lines. When they make more rows
    # than the pane has, it parks with the first of them at the top, unless
    # the pane is `#deferred?`. A window anywhere else stays on the lines it
    # shows, and what arrived waits below it.
    #
    # A source may drop its oldest lines as it gains new ones. A capped log
    # does this, and its size then stays the same however much is added. An
    # owner that knows how many lines *arrived* since the last call says so,
    # and the dropped count comes from that. Otherwise the shown lines are
    # looked for in the new source, which fails when more arrived than the
    # source keeps, since nothing shown is left in it. The pager keeps any
    # dropped line the window shows in front of the source until the window
    # moves on, so the window holds still.
    def show(source : Array(String), arrived : Int32? = nil) : Nil
      return if @given == source

      shift = arrived ? dropped(source, arrived) : dropped(source)
      came = (arrived || source.size - (@source.size - shift)).clamp 0, source.size
      top = @back > 0 ? window_top : nil
      kept = [] of String
      if top && top[0] < shift
        kept = @source[top[0]..Math.min(window_bottom_line, shift - 1)]
      end

      @given = source.dup
      @source = kept + source
      @back = 0
      rewrap

      if top
        line = top[0] < shift ? 0 : top[0] - shift + kept.size
        place({line, top[1]})
      else
        park came
      end
    end

    # Puts the window back on the newest line.
    def to_newest : Nil
      @back = 0
      @sampled = nil
    end

    # How many source lines end below the window, which a person has to
    # scroll down to read all of. Zero at the newest line.
    def newer : Int32
      return 0 if @rows <= 0

      bottom = @lines.size - 1 - @back
      ended = -1
      @rows_per_line.count do |size|
        ended += size
        ended > bottom
      end
    end

    # How many lines one page moves. One row of the last page stays, so a
    # line is never paged past unseen.
    def page : Int32
      Math.max @rows - 1, 1
    end

    # The lines this pane shows now.
    def showing : Array(String)
      shown.map { |index| @lines[index] }
    end

    # The indices of the lines `#showing` answers, top to bottom.
    def shown : Array(Int32)
      return [] of Int32 if @rows <= 0

      frame = @sampled
      return frame.last(@rows).select { |index| index < @lines.size } if frame

      (scroll_y...Math.min(scroll_y + @rows, @lines.size)).to_a
    end

    # Lines there are, and cells across.
    def content_size : {Int32, Int32}
      {@columns, @lines.size}
    end

    # Lines that fit.
    def viewport_size : {Int32, Int32}
      {@columns, @rows}
    end

    # A pane is a window down, never across.
    def clip_x? : Bool
      false
    end

    # :ditto:
    def clip_y? : Bool
      true
    end

    # Always nothing: the text is wrapped rather than scrolled sideways.
    def scroll_x : Int32
      0
    end

    # Which line is at the top of the window.
    #
    # A sampled frame answers for the line at the bottom of the frame, so a
    # scrollbar shows what is drawn.
    def scroll_y : Int32
      frame = @sampled
      return (frame.last - @rows + 1).clamp(0, max_scroll[1]) if frame && !frame.empty?

      Math.max @lines.size - @rows - @back, 0
    end

    # Moves the window, stopping at either end.
    def scroll_by(dx : Int32, dy : Int32) : Nil
      @sampled = nil
      @back = (@back - dy).clamp 0, max_scroll[1]
    end

    # The keyboard never lands here. The owner binds the keys that scroll it.
    def focusable? : Bool
      false
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.new 1, Math.max(@columns, 1)
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      Math.max @rows, 1
    end

    # Answers a notch of the wheel, and a click on the badge.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse
      return pressed(event, context) unless event.button.wheel?

      context.consume
      scroll_wheel event
    end

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      bright = @fresh_style
      from = @lines.size - fresh_rows
      rows = shown

      rows.each_with_index do |index, row|
        break if row >= view.height

        line = @lines[index]
        base = bright if bright && index >= from
        view.write 0, row, line, base || Style::DEFAULT
        Pager.accent view, row, line, base || Style::DEFAULT, @accents
      end

      spot = badge_spot view.width, Math.min(rows.size, view.height)
      view.write spot[0], spot[1], spot[2], @badge_style if spot
    end

    # Where the badge goes in a pane *width* cells across with *rows* rows
    # drawn, and what it says. `nil` while nothing is waiting below.
    private def badge_spot(width : Int32, rows : Int32) : {Int32, Int32, String}?
      return if @sampled || rows <= 0

      found = @badge
      return unless found

      count = newer
      return if count <= 0

      text = found.call count
      size = Unicode.string_width text
      return if size > width

      {width - size, rows - 1, text}
    end

    # Answers a press on the badge. Lets any other press past.
    private def pressed(event : Events::Mouse, context : Context) : Nil
      return unless event.button.left? && event.action.press?

      box = content
      spot = badge_spot box.width, Math.min(shown.size, box.height)
      return unless spot

      size = Unicode.string_width spot[2]
      return unless event.y == box.y + spot[1]
      return unless event.x >= box.x + spot[0] && event.x < box.x + spot[0] + size

      context.consume
      found = @on_badge
      found ? found.call : to_newest
    end

    # Draws the accents *finder* finds in *line* over the line already
    # written on *row* in *base*. A `nil` finder draws none.
    #
    # Any widget that draws wrapped lines can use this to draw the same
    # accents a pager draws.
    def self.accent(view : View, row : Int32, line : String, base : Style,
                    finder : Proc(String, Array(Accent))?) : Nil
      return unless finder

      finder.call(line).each do |mark|
        text = line[mark.start, mark.size]?
        next unless text

        column = Unicode.string_width line[0, mark.start]
        view.write column, row, text, base.merge(mark.style)
      end
    end

    # Parks the window with the first of the last *came* source lines at the
    # top, when those lines make more rows than the pane has.
    private def park(came : Int32) : Nil
      if @deferred
        @deferred_came += came
        return
      end
      return if @rows <= 0 || came <= 0

      first = @rows_per_line.first(Math.max(@rows_per_line.size - came, 0)).sum
      return unless @lines.size - first > @rows

      @back = (@lines.size - @rows - first).clamp 0, max_scroll[1]
    end

    # Puts *top*, a source line and one of its wrapped rows, at the top of
    # the window. `nil` leaves the window at the end.
    private def place(top : {Int32, Int32}?) : Nil
      unless top
        @back = @back.clamp 0, max_scroll[1]
        return
      end

      line = top[0].clamp 0, Math.max(@rows_per_line.size - 1, 0)
      within = Math.min top[1], Math.max((@rows_per_line[line]? || 1) - 1, 0)
      row = @rows_per_line.first(line).sum + within
      @back = (@lines.size - @rows - row).clamp 0, max_scroll[1]
    end

    # The source line the window's top row is in, and which of that line's
    # wrapped rows it is.
    private def window_top : {Int32, Int32}
      line_of Math.max(@lines.size - @rows - @back, 0)
    end

    # The source line the window's bottom row is in.
    private def window_bottom_line : Int32
      line_of(Math.max(@lines.size - 1 - @back, 0))[0]
    end

    # The source line wrapped row *row* is in, and which of its rows it is.
    private def line_of(row : Int32) : {Int32, Int32}
      start = 0
      @rows_per_line.each_with_index do |size, index|
        return {index, row - start} if row < start + size

        start += size
      end
      {@rows_per_line.size, 0}
    end

    # How many wrapped lines the newest `#fresh` source lines made.
    private def fresh_rows : Int32
      @rows_per_line.last(@fresh.clamp(0, @rows_per_line.size)).sum
    end

    # How many lines at the front of the shown source *source* no longer
    # holds, when *arrived* lines were added to the shown source and it
    # settled at *source*'s size. More arriving than the source holds drops
    # everything that was shown.
    private def dropped(source : Array(String), arrived : Int32) : Int32
      (@source.size + arrived - source.size).clamp 0, @source.size
    end

    # The shown source is looked for at the front of *source*, with one more
    # of its oldest lines left off each try. A source that shares nothing with
    # the shown one is new text rather than a continuation, and drops nothing.
    private def dropped(source : Array(String)) : Int32
      (0...@source.size).find { |shift| continues? source, shift } || 0
    end

    # Whether *source* starts with the shown source less its first *shift*
    # lines.
    private def continues?(source : Array(String), shift : Int32) : Bool
      kept = @source.size - shift
      return false if kept > source.size

      kept.times.all? { |index| source[index] == @source[shift + index] }
    end

    # Wraps the source to `#columns`.
    private def rewrap : Nil
      wrapped = if @columns > 0
                  @source.map { |line| Pager.wrap line, @columns }
                else
                  @source.map { |line| [line] }
                end

      @rows_per_line = wrapped.map &.size
      @lines = wrapped.flatten
      @sampled = nil
    end

    # *text* broken into lines no wider than *columns*.
    def self.wrap(text : String, columns : Int32,
                  policy : Unicode::WidthPolicy = Unicode::WidthPolicy::DEFAULT) : Array(String)
      return [text] if columns <= 0

      measured = Layout::TextMeasure.measure text, policy
      broken = Layout::TextMeasure.wrap measured, columns, Layout::Wrap::Words

      lines = broken.map &.text(text)
      lines.empty? ? [""] : lines
    end
  end
end
