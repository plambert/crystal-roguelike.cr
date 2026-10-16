require "termbuf-widgets"
require "./ramp"

module TermBuf::Widgets
  # A background that fades from one color to another on a timer.
  #
  #     tint = Tint.new Color.rgb(0x1E, 0x2E, 0x4C), Color.rgb(0x22, 0x26, 0x2E)
  #     tint.apply panel, app, animate: true
  #
  # It sets the background of the widget's `Widget#style`. A widget under it
  # that writes with no background of its own draws on the tint, because a
  # view lays its style under every write. A widget that names a background
  # keeps it.
  #
  # One tint covers one widget at a time. Applying it to another takes it off
  # the first and puts back the style that widget had.
  #
  # Each step is a `Ramp` step, so a fade interns the same few styles every
  # time it runs.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`.
  class Tint
    # How many steps a fade takes, the two ends included.
    STEPS = 5

    # How long a whole fade takes.
    SPAN = 200.milliseconds

    # The color a fade starts at.
    getter from : Color

    # The color a fade ends at, and stays at.
    getter to : Color

    # The widget being tinted, or `nil` when none is.
    getter target : Widget? = nil

    # Which step the fade is on. `#top` is the end.
    getter step : Int32 = 0

    # How long each step lasts.
    getter every : Time::Span

    # The steps between `#from` and `#to`.
    @ramp : Ramp

    # The style the end of the fade has.
    @base : Style

    # The style the target had before it was tinted.
    @saved : Style? = nil

    # The timer the next step is armed under, and the app that armed it.
    @timer : UInt64? = nil
    @app : App? = nil

    def initialize(@from : Color, @to : Color, steps : Int32 = STEPS,
                   span : Time::Span = SPAN)
      @base = Style::DEFAULT.bg @to
      @ramp = Ramp.linear steps, @from, deepest: 1.0
      @every = steps > 1 ? span / (steps - 1) : span
      @step = @ramp.top
    end

    # The last step.
    def top : Int32
      @ramp.top
    end

    # Whether the fade has reached `#to`.
    def settled? : Bool
      @step >= top
    end

    # The style the target is drawn in now.
    def style : Style
      @ramp[@base, @step]
    end

    # Tints *widget* and takes the tint off whatever had it.
    #
    # With *animate* the fade starts at `#from` and steps to `#to` on timers
    # *app* arms. Without it, or with no clock to arm them on, the widget
    # takes `#to` at once.
    def apply(widget : Widget, app : App?, animate : Bool) : Nil
      clear
      @target = widget
      @saved = widget.style
      @app = app
      @step = animate ? 0 : top
      paint
      arm unless settled?
    end

    # Takes the tint off and puts back the style the widget had.
    def clear : Nil
      disarm

      held = @target
      return unless held

      held.style = @saved
      @target = nil
      @saved = nil
    end

    # Writes the current step into the target's style.
    private def paint : Nil
      held = @target
      return unless held

      saved = @saved
      held.style = saved ? saved.merge(style) : style
    end

    # Arms the next step. With no clock the fade ends now.
    private def arm : Nil
      armed = @app.try &.after(@every) { advance }
      return @timer = armed if armed

      @step = top
      paint
    end

    private def advance : Nil
      @timer = nil
      @step = Math.min @step + 1, top
      paint
      arm unless settled?
    end

    private def disarm : Nil
      held = @timer
      @timer = nil
      @app.try &.cancel(held) if held
    end
  end
end
