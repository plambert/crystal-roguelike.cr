require "../../crystal-roguelike"

module Roguelike::Ui
  # The message log under the map, with its scrollbar, and how tall it is.
  #
  # Unfocused, the pane is `Screen.log_height` rows. Focused, it grows to
  # show everything it holds, up to `Screen.log_most`, and the map gives up
  # the rows. When the focus leaves, it shrinks back and scrolls to the
  # newest line, both at once. The scroll inserts a sample of the rows it
  # passes, from `Widgets::SampledScroll`, so a long way back reads as
  # scrolling and still ends in a few frames.
  #
  # A pane scrolled back while unfocused stays where it is until a message
  # arrives. It then scrolls back the same way, to the last line before the
  # message, and the message follows. A focused pane does not move when a
  # message arrives. A badge on its last row counts the messages below it.
  #
  # A held page wins over all of this. The pager shows the page from its
  # read mark whatever the window is, a held pager does not scroll, and a
  # message that starts a hold puts the window back on the newest line, so
  # the window is where the page is once the hold is let go.
  #
  # Every animation asks `Motion.on?`. With motion off, or no clock, the
  # last frame draws at once.
  class LogPanel
    # How long the pane takes to grow when it gains the focus.
    GROW_SPAN = 200.milliseconds

    # How long the pane takes to shrink and scroll back.
    RETURN_SPAN = 350.milliseconds

    # How many frames the shrink and scroll back take.
    RETURN_FRAMES = 6

    # How many rows one frame of growing adds, past which it adds two.
    GROW_FRAMES = 6

    # One frame of an animation. *height* is the rows of the pane. *sampled*
    # is the lines it shows, or `nil` for the pager's own window.
    record Frame, height : Int32, sampled : Array(Int32)?

    # The lines, which hold at a page boundary.
    getter pager : Widgets::Pager

    # The scrollbar on the right of the pane.
    getter bar : Widgets::QuietBar

    # The pager and the bar side by side. `Screen#show_log` takes this.
    getter root : Widgets::Panel

    # What runs after the pane changes height, so the map can keep the
    # character in view.
    property on_resize : Proc(Nil)? = nil

    # Whether the pane has the focus.
    getter? focused : Bool = false

    # The frames not yet drawn, in order.
    @frames = [] of Frame

    # How long each frame lasts.
    @every : Time::Span = Time::Span.zero

    # What runs once the last frame is drawn.
    @after : Proc(Nil)? = nil

    @timer : UInt64? = nil

    # Whether the frame drawn last was a sampled one.
    @sampling : Bool = false

    # How wide the text is, and how tall the terminal is.
    @columns : Int32 = 0
    @rows : Int32 = 0

    def initialize(@screen : Screen)
      @pager = Widgets::Pager.new
      @bar = Widgets::QuietBar.new @pager, Widgets::Scrollbar::Orientation::Vertical
      @root = Widgets::Panel.new(
        direction: Layout::Direction::Row,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      @root.add @pager, @bar
      @pager.badge = ->(count : Int32) { " \u2193 #{count} newer " }
    end

    # Sizes the pane for text *columns* wide on a terminal *rows* tall.
    # A running animation ends, and the pane takes the height it wants at
    # once.
    def fit(columns : Int32, rows : Int32) : Nil
      @columns = columns
      @rows = rows
      stop
      @pager.sampled = nil
      apply Frame.new(wanted, nil), tell: false
    end

    # How many rows the pane wants. Unfocused that is `Screen.log_height`.
    # Focused it is enough for every line, between that and
    # `Screen.log_most`.
    def wanted : Int32
      rest = Screen.log_height @rows
      return rest unless @focused

      (@pager.lines.size + banner).clamp rest, Screen.log_most(@rows)
    end

    # Gives the pane the focus, or takes it away.
    #
    # Gaining it, the pane grows. Losing it, the pane shrinks and scrolls to
    # the newest line. An animation still running ends first.
    def focused=(focused : Bool) : Bool
      return focused if focused == @focused

      finish
      @focused = focused
      focused ? grow : go_back
      focused
    end

    # Whether an animation is running.
    def animating? : Bool
      !@frames.empty? || !@after.nil?
    end

    # Shows *source* on the pager. *arrived* is how many lines were added
    # since the last call.
    def show(source : Array(String), arrived : Int32) : Nil
      return @pager.show(source, arrived: arrived) unless arrived > 0

      finish
      back = @pager.back
      @pager.show source, arrived: arrived, keep: back > 0
      @pager.to_newest if @pager.holding?

      if @focused
        grow
      elsif @pager.back > 0
        catch_up back
      end
    end

    # Draws the last frame of the running animation now.
    def finish : Nil
      last = @frames.last?
      after = @after
      stop
      apply last if last
      after.try &.call
    end

    # How many rows the banner takes from the pane.
    private def banner : Int32
      @screen.banner ? 1 : 0
    end

    # Grows or shrinks the pane to the height it wants, a row or two a
    # frame.
    private def grow : Nil
      from = @screen.log_size
      goal = wanted
      return if goal == from

      per = (goal - from).abs > GROW_FRAMES ? 2 : 1
      way = goal > from ? per : -per
      heights = [] of Int32
      at = from
      until at == goal
        at = way > 0 ? Math.min(at + way, goal) : Math.max(at + way, goal)
        heights << at
      end

      run heights.map { |height| Frame.new height, nil }, GROW_SPAN
    end

    # Shrinks the pane to its unfocused height and scrolls it to the newest
    # line, together.
    private def go_back : Nil
      from = @screen.log_size
      goal = wanted
      ends = @pager.lines.size - 1
      sampled = Widgets::SampledScroll.frames ends - @pager.back, ends,
        goal - banner, RETURN_FRAMES, window: from - banner

      if from == goal && sampled.empty?
        @pager.to_newest
        return
      end

      frames = (1..RETURN_FRAMES).map do |frame|
        height = from - ((from - goal) * frame + RETURN_FRAMES - 1) // RETURN_FRAMES
        shown = unless sampled.empty?
          sampled[(frame * sampled.size + RETURN_FRAMES - 1) // RETURN_FRAMES - 1]
        end
        Frame.new height, shown
      end

      run frames.chunk_while { |one, two| one == two }.map(&.first).to_a, RETURN_SPAN,
        -> { @pager.to_newest }
    end

    # Scrolls an unfocused pane that stood *back* lines above what had been
    # the newest line back to that line. What arrived since shows after.
    private def catch_up(back : Int32) : Nil
      ends = @pager.lines.size - 1
      arrived = @pager.back - back
      goal = ends - arrived
      height = @screen.log_size - banner
      sampled = Widgets::SampledScroll.frames ends - @pager.back, goal,
        height, RETURN_FRAMES

      if sampled.empty?
        @pager.to_newest
        return
      end

      frames = sampled.map { |shown| Frame.new @screen.log_size, shown }
      run frames, RETURN_SPAN, -> { @pager.to_newest }
    end

    # Plays *frames* over *span*, then runs *after* one frame later, so the
    # last frame shows before it.
    #
    # The first frame draws now. With motion off, or no clock to arm the
    # rest on, the last frame draws now instead, and *after* runs with it.
    private def run(frames : Array(Frame), span : Time::Span,
                    after : Proc(Nil)? = nil) : Nil
      stop
      return after.try(&.call) if frames.empty?

      @frames = frames
      @after = after
      @every = span / frames.size
      return finish unless Motion.on?

      step
    end

    # Draws the next frame and arms the one after it. With every frame
    # drawn, runs what was to follow them.
    private def step : Nil
      frame = @frames.shift?
      return finish unless frame

      apply frame
      return if @frames.empty? && @after.nil?

      armed = @pager.app.try &.after(@every) { advance }
      return finish unless armed

      @timer = armed
    end

    # Runs on the timer. A pane someone scrolled while it showed a sampled
    # frame stays where they put it, and takes its last height at once.
    private def advance : Nil
      @timer = nil
      if @sampling && @pager.sampled.nil?
        last = @frames.last
        stop
        apply Frame.new(last.height, nil)
        return
      end

      step
    end

    # Makes the pane as tall as *frame* says, and shows its lines.
    private def apply(frame : Frame, tell : Bool = true) : Nil
      moved = frame.height != @screen.log_size
      @screen.grow_log frame.height
      @pager.resize @columns, frame.height - banner
      @pager.sampled = frame.sampled
      @sampling = !frame.sampled.nil?
      @on_resize.try &.call if moved && tell
    end

    private def stop : Nil
      held = @timer
      @timer = nil
      @frames = [] of Frame
      @after = nil
      @pager.app.try &.cancel(held) if held
    end
  end
end
