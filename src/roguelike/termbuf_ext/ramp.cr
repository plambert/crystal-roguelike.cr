require "termbuf"

module TermBuf::Widgets
  # A fixed number of styles between one style and a colour.
  #
  #     ramp = Ramp.new 5, Color.rgb(0, 0, 0)
  #
  #     ramp[Style::DEFAULT.fg(Color.rgb 0xC0, 0xC0, 0xC0), 4]  # the style itself
  #     ramp[Style::DEFAULT.fg(Color.rgb 0xC0, 0xC0, 0xC0), 0]  # nearly black
  #
  # A `Blend` computing a colour per cell interns a style per cell, and
  # `StyleTable` only grows. One frame of that is bounded by the screen and
  # costs nothing. An animation recomputing it every frame is not bounded at
  # all, and the table grows until the program ends.
  #
  # A ramp answers the same style for the same step every time, so the table
  # stops growing once each step of each base style has been asked for once.
  # A map drawn by torchlight has a handful of base styles and a handful of
  # steps, so it settles at a few dozen.
  #
  # Only a colour that is set moves. A default foreground or background is
  # whatever the terminal draws, and a ramp has nothing to move it toward.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`. What is still
  # to settle is whether the step-to-fraction curve should be given rather
  # than linear, which matters for a light falloff that is not linear either.
  class Ramp
    # How many steps there are, the two ends included.
    getter steps : Int32

    # What the deepest step moves toward.
    getter toward : Color

    # How far the deepest step goes. One moves it the whole way to `#toward`.
    # Less than one leaves the deepest step still readable.
    getter deepest : Float64

    # What has been worked out so far, by base style and step.
    @made = {} of {Style, Int32} => Style

    def initialize(@steps : Int32,
                   @toward : Color = Color.rgb(0, 0, 0),
                   @deepest : Float64 = 0.82)
      raise ArgumentError.new "a ramp needs at least one step" if @steps < 1
    end

    # The top step. A style asked for at this step comes back unchanged.
    def top : Int32
      @steps - 1
    end

    # *base* at *step*. A step outside the ramp is clamped to an end of it.
    def [](base : Style, step : Int32) : Style
      wanted = step.clamp 0, top

      @made[{base, wanted}] ||= mixed base, wanted
    end

    # How many styles this ramp has worked out.
    #
    # It stops rising once each step of each base style has been asked for.
    def size : Int32
      @made.size
    end

    # Throws away what has been worked out. The styles it made stay in
    # whatever `StyleTable` they reached.
    def clear : Nil
      @made.clear
    end

    # How far toward `#toward` *step* is.
    def fraction(step : Int32) : Float64
      return 0.0 if @steps == 1

      wanted = step.clamp 0, top

      @deepest * (top - wanted) / top
    end

    # *base* moved toward `#toward` by `#fraction` of *step*.
    private def mixed(base : Style, step : Int32) : Style
      part = fraction step
      return base if part <= 0.0

      style = base
      style = style.fg mix(base.foreground, part) unless base.foreground.default?
      style = style.bg mix(base.background, part) unless base.background.default?

      # A dimmed style is not the bright one it came from. Bold on a dim
      # colour reads as lit, which is the one thing the dimming says it is
      # not.
      style.copy_with attributes: base.attributes & ~Attributes::Bold
    end

    # *color* moved *part* of the way toward `#toward`.
    private def mix(color : Color, part : Float64) : Color
      from = color.channels
      to = @toward.channels

      Color.rgb(
        step_between(from[0], to[0], part),
        step_between(from[1], to[1], part),
        step_between(from[2], to[2], part))
    end

    private def step_between(from : Int32, to : Int32, part : Float64) : Int32
      (from + (to - from) * part).round.to_i.clamp 0, 255
    end
  end
end
