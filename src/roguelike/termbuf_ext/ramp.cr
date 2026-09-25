require "termbuf"

module TermBuf::Widgets
  # A fixed number of styles between one style and a color.
  #
  #     ramp = Ramp.new [0.66, 0.44, 0.30, 0.15, 0.0], Color.rgb(0x14, 0x18, 0x22)
  #
  #     ramp[Style::DEFAULT.fg(Color.rgb 0xC0, 0xC0, 0xC0), 4]  # the style itself
  #     ramp[Style::DEFAULT.fg(Color.rgb 0xC0, 0xC0, 0xC0), 0]  # nearly black
  #
  # A `Blend` computing a color per cell interns a style per cell, and
  # `StyleTable` only grows. One frame of that is bounded by the screen and
  # costs nothing. An animation recomputing it every frame is not bounded at
  # all, and the table grows until the program ends.
  #
  # A ramp answers the same style for the same step every time, so the table
  # stops growing once each step of each base style has been asked for once.
  # A map drawn by torchlight has a handful of base styles and a handful of
  # steps, so it settles at a few dozen.
  #
  # Only a color that is set moves. A default foreground or background is
  # whatever the terminal draws, and a ramp has nothing to move it toward.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`. What is still
  # to settle is whether a ramp should offer a hue shift as well as a fade,
  # so that a dimmed warm color reads as being in shadow rather than as a
  # darker warm color.
  class Ramp
    # How far toward `#toward` each step moves, from the deepest to the top.
    #
    # The last one is nearly always zero, which leaves the top step the style
    # itself. Giving these rather than working them out from two ends is what
    # lets one step sit well below the rest, so that a square drawn from
    # memory is not read as the dimmest lit square.
    getter fractions : Array(Float64)

    # What the deepest step moves toward.
    getter toward : Color

    # What has been worked out so far, by base style and step.
    @made = {} of {Style, Int32} => Style

    def initialize(@fractions : Array(Float64),
                   @toward : Color = Color.rgb(0, 0, 0))
      raise ArgumentError.new "a ramp needs at least one step" if @fractions.empty?
    end

    # A ramp of *steps* spread evenly between *deepest* and the style itself.
    def self.linear(steps : Int32, toward : Color = Color.rgb(0, 0, 0),
                    deepest : Float64 = 0.82) : Ramp
      raise ArgumentError.new "a ramp needs at least one step" if steps < 1
      return new [0.0], toward if steps == 1

      new Array.new(steps) { |step| deepest * (steps - 1 - step) / (steps - 1) }, toward
    end

    # How many steps there are, the two ends included.
    def steps : Int32
      @fractions.size
    end

    # The top step. A style asked for at this step comes back unchanged.
    def top : Int32
      @fractions.size - 1
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
      @fractions[step.clamp 0, top]
    end

    # How far the deepest step goes.
    def deepest : Float64
      @fractions.first
    end

    # *base* moved toward `#toward` by `#fraction` of *step*.
    private def mixed(base : Style, step : Int32) : Style
      part = fraction step
      return base if part <= 0.0

      style = base
      style = style.fg mix(base.foreground, part) unless base.foreground.default?
      style = style.bg mix(base.background, part) unless base.background.default?

      # Bold is dropped. A bold dim color reads as lit, which is what the
      # dimming is there to say it is not.
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
