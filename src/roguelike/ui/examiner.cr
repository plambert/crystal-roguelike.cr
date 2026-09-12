module Roguelike::Ui
  # Points at a square. Says what is on it.
  #
  # There are two ways in. Both write one readout. The pointer needs no mode.
  # It is the quicker of the two. `x` puts a cursor on the map. The movement
  # keys move that cursor. A terminal with mouse reporting off has only that
  # way. A person who prefers the keyboard has it too.
  #
  # This class holds no terminal. A spec drives one over a buffer.
  class Examiner
    # The window being pointed at.
    getter map : MapPane

    # The readout being written.
    getter pane : ExaminePane

    # What names the items on a square. `nil` names none of them.
    property lore : Lore? = nil

    # Where the readout points, in the level's own coordinates. `nil` before
    # anything has been looked at.
    getter spot : {Int32, Int32}?

    # Whether the keyboard cursor is on the map.
    getter? cursoring : Bool = false

    def initialize(@map : MapPane, @pane : ExaminePane)
    end

    # Points the readout at *x*, *y* of the level.
    #
    # A square off the level does not move the readout. The readout keeps what
    # it last had.
    def point_at(x : Int32, y : Int32) : Bool
      return false unless @map.level.contains? x, y

      @spot = {x, y}
      refresh
      true
    end

    # Points the readout at the square under *screen_x*, *screen_y* of the
    # buffer. Answers whether that spot held a square.
    def point_at_screen(screen_x : Int32, screen_y : Int32) : Bool
      spot = @map.cell_at_screen screen_x, screen_y
      return false unless spot

      point_at spot[0], spot[1]
    end

    # Puts the cursor on the map.
    #
    # The cursor starts where the readout already points. It starts in the
    # middle of the window when the readout points nowhere.
    def start : Nil
      return if @cursoring

      @cursoring = true
      here = @spot || @map.middle
      @spot = here
      point_at here[0], here[1]
    end

    # Takes the cursor off the map. The readout keeps what it said.
    def stop : Nil
      return unless @cursoring

      @cursoring = false
      refresh
    end

    # Starts the cursor when it is off. Stops it when it is on.
    def toggle : Nil
      cursoring? ? stop : start
    end

    # Moves the cursor one square *direction*. Stops at the edges of the
    # level. Brings the cursor into view.
    #
    # This method does nothing while the cursor is off the map. The movement
    # keys can then be bound once. They mean the cursor here. They mean the
    # character everywhere else.
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

    # Writes the readout. Puts the cursor where it belongs.
    private def refresh : Nil
      here = @spot

      if here
        @pane.show @map.level, here[0], here[1], @lore
      else
        @pane.clear
      end

      @map.cursor = @cursoring ? here : nil
    end
  end
end
