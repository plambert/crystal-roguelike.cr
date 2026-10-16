require "termbuf-widgets"

module TermBuf::Widgets
  # Moves a scroll offset to a new place over a short time, slowing as it
  # arrives.
  #
  #     glide = EasedScroll.over panel
  #     glide.by 0, 3, app, animate: true
  #
  # It knows nothing about what scrolls. It reads the offset, writes the
  # offset and asks how far the offset may go through three procs, so one
  # class moves a panel, a pager and a map camera.
  #
  # The first frame is written at once and the rest follow on timers
  # `app` arms. Without `animate`, or with no clock to arm them on, the
  # offset takes the goal in one write.
  #
  # A scroll started while another runs begins from where the offset is now.
  # `#by` adds to the goal of the one running, so a key held down keeps
  # gaining ground. An offset that someone else moved between two frames
  # ends the scroll, and the other mover keeps the place it chose.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`.
  class EasedScroll
    # How many frames a scroll takes, the first included.
    STEPS = 5

    # How long a whole scroll takes.
    SPAN = 150.milliseconds

    alias Offset = {Int32, Int32}

    # How long each frame after the first lasts.
    getter every : Time::Span

    # How many frames a scroll takes.
    getter steps : Int32

    # The offset the running scroll ends on. `nil` when none runs.
    getter goal : Offset? = nil

    @from : Offset = {0, 0}
    @frame : Int32 = 0

    # Where the offset stood after the last frame this wrote.
    @last : Offset = {0, 0}

    @timer : UInt64? = nil
    @app : App? = nil

    def initialize(@read : Proc(Offset), @write : Proc(Int32, Int32, Nil),
                   @limit : Proc(Offset), @steps : Int32 = STEPS,
                   span : Time::Span = SPAN)
      @every = @steps > 1 ? span / (@steps - 1) : span
    end

    # A scroll for anything that scrolls by `Scrolls`.
    def self.over(target : Scrolls, steps : Int32 = STEPS,
                  span : Time::Span = SPAN) : EasedScroll
      new(
        -> { {target.scroll_x, target.scroll_y} },
        ->(x : Int32, y : Int32) { target.scroll_by x - target.scroll_x, y - target.scroll_y },
        -> { target.max_scroll },
        steps, span)
    end

    # Where an offset going from *from* to *to* stands at *frame* of
    # *frames*.
    #
    # It moves along the straight line between the two and slows as it
    # arrives. Each frame is a smaller share of the way than the one before.
    # The last frame lands on *to* exactly.
    def self.at(from : Offset, to : Offset, frame : Int32, frames : Int32) : Offset
      return to if frame >= frames

      share = 1.0 - (1.0 - frame / frames) ** 3
      {from[0] + ((to[0] - from[0]) * share).round.to_i,
       from[1] + ((to[1] - from[1]) * share).round.to_i}
    end

    # Whether a scroll is running.
    def running? : Bool
      !@goal.nil?
    end

    # Where the offset is heading. The offset itself when no scroll runs.
    def heading : Offset
      @goal || @read.call
    end

    # *x*, *y* held inside what the offset may reach.
    def clamp(x : Int32, y : Int32) : Offset
      limit = @limit.call
      {x.clamp(0, limit[0]), y.clamp(0, limit[1])}
    end

    # Scrolls to *x*, *y*, stopping at the ends.
    def to(x : Int32, y : Int32, app : App?, animate : Bool) : Nil
      wanted = clamp x, y
      stop
      here = @read.call
      return if wanted == here

      @app = app
      return land wanted unless animate && app

      @from = here
      @goal = wanted
      @frame = 0
      step
    end

    # Scrolls *dx* columns and *dy* rows on from where the offset is heading.
    def by(dx : Int32, dy : Int32, app : App?, animate : Bool) : Nil
      now = heading
      to now[0] + dx, now[1] + dy, app, animate
    end

    # Ends the scroll where the offset stands.
    def cancel : Nil
      stop
    end

    # Puts the offset on the goal of the running scroll at once.
    def finish : Nil
      wanted = @goal
      stop
      land wanted if wanted
    end

    private def land(wanted : Offset) : Nil
      @write.call wanted[0], wanted[1]
    end

    # Arms the frame after this one, then writes this one.
    #
    # With no clock to arm it on, the offset takes the goal at once.
    private def step : Nil
      wanted = @goal
      return unless wanted

      @frame += 1
      last = @frame >= @steps

      unless last
        armed = @app.try &.after(@every) { advance }
        unless armed
          stop
          return land wanted
        end

        @timer = armed
      end

      spot = EasedScroll.at @from, wanted, @frame, @steps
      @write.call spot[0], spot[1]
      @last = @read.call
      stop if last
    end

    private def advance : Nil
      @timer = nil
      return stop unless @read.call == @last

      step
    end

    private def stop : Nil
      held = @timer
      @timer = nil
      @goal = nil
      @app.try &.cancel(held) if held
    end
  end
end
