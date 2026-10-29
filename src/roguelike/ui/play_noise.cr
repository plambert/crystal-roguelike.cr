require "../../crystal-roguelike"

module Roguelike::Ui
  class Play
    # How long the tint of the character's noise takes to spread one square
    # further.
    RIPPLE = 30.milliseconds

    # The turn whose noise the map is tinted for. `nil` when it is tinted for
    # none.
    @echo_turn : Int32? = nil

    # The timer for the next square of the spreading tint. `nil` when the
    # tint is not spreading.
    @ripple_timer : UInt64? = nil

    # How many times the mark of a sound heard out of sight turns off and on
    # again before it holds still. Each lasts `BLINK`.
    HEARD_BLINKS = 4

    # The turn whose overheard sounds the map marks. `nil` when it marks none.
    @heard_turn : Int32? = nil

    # How many blinks of the mark are left.
    @heard_blinks : Int32 = 0

    # The timer for the next blink of the mark. `nil` when it is not
    # blinking.
    @heard_timer : UInt64? = nil

    # Marks the map where the last action heard sounds from out of sight,
    # and tints it for the noise the character made.
    private def show_noise : Nil
      show_heard
      show_echo
    end

    # Marks each sound out of sight the last action heard, on the last
    # square in sight toward it.
    #
    # The mark blinks with motion on and holds still with motion off.
    private def show_heard : Nil
      heard = @game.overheard
      if heard.empty?
        stop_heard_blink
        @heard_turn = nil
        @map.overhear [] of {Int32, Int32}
        return
      end
      return if @heard_turn == @game.turn

      stop_heard_blink
      @heard_turn = @game.turn
      @map.overhear heard.map(&.mark)

      app = @app
      return unless app && Motion.on?

      @heard_blinks = HEARD_BLINKS
      @heard_timer = app.after(BLINK) { blink_heard }
    end

    # Turns the mark off if it is on and on if it is off, and arms the next
    # blink until the count runs out with the mark on.
    private def blink_heard : Nil
      @heard_timer = nil
      @map.heard_lit = !@map.heard_lit?
      @heard_blinks -= 1
      return if @heard_blinks <= 0 && @map.heard_lit?

      app = @app
      @heard_timer = app.after(BLINK) { blink_heard } if app
    end

    # Cancels the next blink, and leaves the mark on.
    private def stop_heard_blink : Nil
      timer = @heard_timer
      @heard_timer = nil
      @app.try &.cancel(timer) if timer
      @map.heard_lit = true
    end

    # Tints the map for the noise the character made in the last action, and
    # takes the tint off once an action has made none.
    #
    # The tint spreads out from where the sound began, a square at a time.
    # With motion off, or with no clock, it is drawn whole at once.
    private def show_echo : Nil
      echoes = @game.echoes
      if echoes.empty?
        stop_ripple
        @echo_turn = nil
        @map.clear_echo
        return
      end
      return if @echo_turn == @game.turn

      stop_ripple
      @echo_turn = @game.turn
      @map.hear echoes
      @map.echo_front = nil

      app = @app
      return unless app && Motion.on?

      @map.echo_front = 0
      @ripple_timer = app.after(RIPPLE) { ripple }
    end

    # Spreads the tint one square further, and arms the next square until it
    # has reached as far as the sound did.
    private def ripple : Nil
      @ripple_timer = nil
      front = @map.echo_front
      return unless front

      front += 1
      if front >= @map.echo_reach
        @map.echo_front = nil
        return
      end

      @map.echo_front = front
      app = @app
      @ripple_timer = app.after(RIPPLE) { ripple } if app
    end

    # Cancels the spreading tint where it stands.
    private def stop_ripple : Nil
      timer = @ripple_timer
      @ripple_timer = nil
      @app.try &.cancel(timer) if timer
    end
  end
end
