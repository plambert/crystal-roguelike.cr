module Roguelike::Ui
  # Pointing at a square and saying what is on it.
  #
  # Two ways in, and they share one readout. The pointer needs no mode and is
  # the quicker of the two. `x` puts a cursor on the map and moves it with the
  # movement keys, which is what a terminal with mouse reporting turned off
  # has, and what somebody who would rather not reach for the mouse has.
  #
  # It holds no terminal, so a spec drives one over a buffer.
  class Examiner
    # The window being pointed at.
    getter map : MapPane

    # The readout being written.
    getter pane : ExaminePane

    # Where it is pointed, in the level's own coordinates, or `nil` before
    # anything has been looked at.
    getter spot : {Int32, Int32}?

    # Whether the keyboard cursor is on the map.
    getter? cursoring : Bool = false

    def initialize(@map : MapPane, @pane : ExaminePane)
    end

    # Points the readout at *x*, *y* of the level.
    #
    # A square off the level is not pointed at and does not clear what is
    # there: the readout holds what it last had.
    def point_at(x : Int32, y : Int32) : Bool
      return false unless @map.level.contains? x, y

      @spot = {x, y}
      refresh
      true
    end

    # Points it at whatever square is under *screen_x*, *screen_y* of the
    # buffer, answering whether that was one.
    def point_at_screen(screen_x : Int32, screen_y : Int32) : Bool
      spot = @map.cell_at_screen screen_x, screen_y
      return false unless spot

      point_at spot[0], spot[1]
    end

    # Puts the cursor on the map, where the readout is already pointed or in
    # the middle of the window.
    def start : Nil
      return if @cursoring

      @cursoring = true
      here = @spot || @map.middle
      @spot = here
      point_at here[0], here[1]
    end

    # Takes the cursor off the map, leaving the readout saying what it said.
    def stop : Nil
      return unless @cursoring

      @cursoring = false
      refresh
    end

    # Starts if it is stopped and stops if it is started.
    def toggle : Nil
      cursoring? ? stop : start
    end

    # Moves the cursor one square *direction*, stopping at the edges of the
    # level, and brings it into view.
    #
    # Does nothing when the cursor is not on the map, so the movement keys can
    # be bound once and mean the cursor here and the player everywhere else.
    def move(direction : Direction) : Bool
      return false unless @cursoring

      here = @spot
      return false unless here

      wanted = direction.from here[0], here[1]
      return false unless @map.level.contains? wanted[0], wanted[1]

      @spot = wanted
      @map.follow wanted[0], wanted[1]
      refresh
      true
    end

    # Writes the readout and puts the cursor where it belongs.
    private def refresh : Nil
      here = @spot

      if here
        @pane.show @map.level, here[0], here[1]
      else
        @pane.clear
      end

      @map.cursor = @cursoring ? here : nil
    end
  end
end
