require "termbuf-widgets"

# Extraction candidate: `TermBuf::Widgets::Pager`, for termbuf-widgets.cr.
#
# A pane of N rows shows the last N lines. A turn that produces six lines in
# a four row pane loses two of them, and those two are never drawn at all.
#
# `less` solves this by holding at a page boundary. Roguelikes solve it the
# same way and write `--More--` at the end of the line. The widget catalogue
# has nothing that does it. `VirtualList` scrolls, and scrolling past unread
# text is the problem rather than the fix.
#
# This type is written in `TermBuf::Widgets` rather than in `Roguelike`.
# Extracting it is then a file move with no edits.
#
# Two questions remain open:
#
# * Should this be a `VirtualList` over `Rows(String)` instead? A list holds a
#   window and a selection. A pager holds a read mark and a page size. The two
#   pieces of state do not overlap, so a subclass would carry a selection it
#   never uses.
# * Should `#resize` be needed at all? The widget learns its own size during
#   `#draw`. Holding is decided outside `#draw` because pushing a focus scope
#   during a render is not safe. An owner that already knows the pane size
#   passes it in.
module TermBuf::Widgets
  # Lines that hold at a page boundary until a key is pressed.
  #
  #     pager.resize 78, 4
  #     pager.show log.lines
  #     pager.holding?   # => true when more arrived than one page holds
  #
  # The widget wraps what it is given to its own width. A line longer than the
  # pane becomes two lines rather than being cut.
  #
  # A pager pushes a focus scope while it holds. Every key then reaches the
  # pager and stops there. `Router` reads the chain's keymaps before it offers
  # an event to a widget's `#handle`, so an application binding would answer
  # before the pager saw the key.
  class Pager < Widget
    include Scrolls

    # What the pager draws at the end of a page when more lines remain.
    property marker : String = "--More--"

    # What the marker is drawn in.
    property marker_style : Style = Style::DEFAULT.reverse

    # Cells across. An owner sets this with `#resize`.
    getter columns : Int32 = 0

    # Rows down. An owner sets this with `#resize`.
    getter rows : Int32 = 0

    # Every line, wrapped to `#columns`, oldest first.
    getter lines : Array(String) = [] of String

    # How many lines the person has seen.
    getter read : Int32 = 0

    # How many lines back from the newest the window sits.
    #
    # Zero is the bottom, which is where the pane stands until somebody
    # scrolls it. A line arriving puts it back to zero: what just happened is
    # what a person wants to see, and a pane left where it was scrolled to
    # would go quietly stale.
    getter back : Int32 = 0

    # How many lines one notch of the wheel moves.
    #
    # One. The pane is four rows, and three lines a notch would jump most of
    # it.
    property wheel : Int32 = 1

    # The application this pager is drawn on.
    #
    # An owner sets this once it has built an `App`. Holding needs it to push
    # a focus scope. A pager without one still holds and still draws the
    # marker. Other keys then reach their own bindings.
    property app : App? = nil

    # The focus scope holding pushed.
    @scope : Focus::Scope? = nil

    # What to run when a hold an owner asked for is let go.
    #
    # A hold the line count called for runs nothing: nobody asked for it, so
    # nobody is waiting on it. `#hold` is what arms this.
    property on_release : Proc(Nil)? = nil

    # Whether an owner asked for a hold that the line count does not call
    # for. `#hold` sets it and `#advance` clears it.
    @insisted = false

    def initialize(style : Style? = nil)
      @width = Layout::Sizing.grow
      @height = Layout::Sizing.grow
      @style = style
      @source = [] of String
    end

    # Sets the size of the pane. Wraps the text again when the width changed.
    def resize(columns : Int32, rows : Int32) : Nil
      @rows = rows

      if columns == @columns
        settle
        return
      end

      @columns = columns
      rewrap
    end

    # Shows *source*, oldest first.
    #
    # A line already shown stays shown. The read mark moves only when the
    # person has seen a line.
    #
    # The same lines a second time change nothing. An owner redraws on every
    # frame, and rewrapping text that has not moved would throw away a
    # scrolled window several times a second.
    def show(source : Array(String)) : Nil
      return if @source == source

      @source = source.dup
      @back = 0
      rewrap
    end

    # How many wrapped lines the person has not seen.
    def unread : Int32
      @lines.size - @read
    end

    # Whether more lines arrived than one page holds, or an owner asked to
    # hold anyway.
    #
    # A pane an owner has deferred holds nothing at all. See `#deferred?`.
    def holding? : Bool
      return false if @deferred

      @rows > 0 && (@insisted || unread > @rows)
    end

    # Whether an owner has asked the pane not to hold for now.
    #
    # `Ui::Play` sets it while a walk is drawn a step at a time. Lines pile up
    # during the walk and the hold is for when the person has the keyboard
    # back: a hold part way through would take the keyboard from the walk and
    # leave two things pushing focus scopes at once.
    getter? deferred : Bool = false

    # :ditto:
    def deferred=(wanted : Bool) : Bool
      return wanted if wanted == @deferred

      @deferred = wanted
      settle
      wanted
    end

    # Holds at the newest page, however few lines arrived.
    #
    # An owner calls this when one line has to be read before anything else
    # happens. The pane goes on showing the newest page and writes the marker
    # under it, and the next key clears it the way it clears any other hold.
    def hold : Bool
      return false unless @rows > 0

      @insisted = true
      @read = Math.max @lines.size - page, 0
      settle
      true
    end

    # How many lines one page shows while the pager holds.
    #
    # One row goes to the marker. A page that used every row would leave
    # nowhere to say that more is coming.
    def page : Int32
      Math.max @rows - 1, 1
    end

    # Shows the next page. Does nothing while the pager is not holding.
    def advance : Bool
      return false unless holding?

      asked = @insisted
      @insisted = false
      @read += page
      settle
      @on_release.try &.call if asked

      true
    end

    # Marks every line as seen, and drops a hold an owner asked for.
    #
    # An owner calls this when the lines it has just handed over are lines the
    # person has already read. Restoring a saved run does that: the log comes
    # back whole, and none of it is news.
    def catch_up : Nil
      @insisted = false
      @read = @lines.size
      settle
    end

    # Puts the window back on the newest line.
    #
    # An owner calls this when what the pane is beside has moved on. A pane
    # scrolled back is showing what was happening rather than what is.
    def to_newest : Nil
      @back = 0
    end

    # The lines this pane shows now.
    #
    # While the pager holds, this is one page starting at the read mark.
    # Otherwise it is the `#rows` lines ending `#back` lines above the
    # newest, so older text stays as context and the wheel reaches further
    # back.
    def showing : Array(String)
      return [] of String if @rows <= 0

      return @lines[@read, page] if holding?

      @lines[scroll_y, @rows]
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
    def scroll_y : Int32
      Math.max @lines.size - @rows - @back, 0
    end

    # Moves the window, stopping at either end.
    #
    # A held page is not scrolled. What is showing then is a page that has
    # not been read, and moving it is how a line goes unread.
    def scroll_by(dx : Int32, dy : Int32) : Nil
      return if holding?

      @back = (@back - dy).clamp 0, max_scroll[1]
    end

    # The keyboard lands here while the pager holds. It lands nowhere else.
    def focusable? : Bool
      holding?
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.new 1, Math.max(@columns, 1)
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      Math.max @rows, 1
    end

    # Takes every key while the pager holds. Any key shows the next page.
    #
    # A wheel notch is answered whether it holds or not. While it holds, a
    # notch down shows the next page, which is what the marker is asking
    # for. Otherwise the notch moves the window over the lines already read.
    def handle(event : Event, context : Context) : Nil
      case event
      when Events::Mouse
        return unless event.button.wheel?

        context.consume

        if holding?
          advance if event.button.wheel_down?
        else
          scroll_wheel event
        end
      when Events::Key
        return unless holding?

        context.consume
        advance
      end
    end

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      more = holding?
      showing.each_with_index do |line, row|
        break if row >= view.height

        view.write 0, row, line
      end

      return unless more

      spot = Math.min page, view.height - 1
      view.write 0, spot, @marker, @marker_style
    end

    # Wraps the source to `#columns`. Keeps the read mark where it was.
    #
    # Rewrapping changes how many lines there are. The read mark counts
    # wrapped lines, so it is clamped rather than kept exactly.
    private def rewrap : Nil
      @lines = if @columns > 0
                 @source.flat_map { |line| Pager.wrap line, @columns }
               else
                 @source.dup
               end

      settle
    end

    # Holds the read mark inside the lines there are. Takes or gives back the
    # keyboard as holding starts or stops.
    private def settle : Nil
      @read = @read.clamp 0, @lines.size

      # A deferred pane does not hold, and it does not count the lines as
      # read either. They pile up unread until the owner lets it hold again,
      # which is the whole point of deferring it.
      @read = @lines.size unless @deferred || holding?
      @back = @back.clamp 0, max_scroll[1]

      holding? ? grab : release
    end

    # Puts a focus scope over the application, with this pager as its root.
    private def grab : Nil
      return if @scope

      app = @app
      return unless app

      @scope = app.focus.push self
      app.focus.focus self
    end

    # Takes that scope off again.
    private def release : Nil
      return unless @scope

      @scope = nil
      @app.try &.focus.pop
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
