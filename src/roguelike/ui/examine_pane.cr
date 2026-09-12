module Roguelike::Ui
  # What is on one square, written out in the sidebar.
  #
  # A permanent readout rather than a tooltip: it holds the last square it was
  # pointed at instead of blanking when the pointer moves off the map. A panel
  # that empties itself every time the mouse passes over the log is a panel
  # nobody can read.
  class ExaminePane
    # The heading, which says what the pane is for even when it is empty.
    HEADING = "Look"

    # What is said before anything has been looked at.
    NOTHING = "Point at the map, or press x."

    # The widget itself, for putting in a tree.
    getter root : Widgets::Panel

    # Where the readout is pointed, in the level's own coordinates.
    getter where : Widgets::Label

    # What is there.
    getter what : Widgets::Label

    # A sentence about it.
    getter detail : Widgets::Label

    def initialize
      @where = Widgets::Label.new ""
      @what = Widgets::Label.new NOTHING
      @detail = Widgets::Label.new ""

      heading = Widgets::Label.new HEADING
      heading.style = Style::DEFAULT.bold
      @where.style = Style::DEFAULT.faint
      @where.hidden = true

      @root = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      @root.add heading,
        Widgets::Divider.new(Widgets::Divider::Orientation::Horizontal),
        @where, @what, @detail
    end

    # Says what is on *level* at *x*, *y*.
    def show(level : Level, x : Int32, y : Int32) : Nil
      terrain = level.terrain x, y

      @where.text = "#{x}, #{y}"
      @where.hidden = false
      @what.text = terrain.label
      @what.style = Palette[terrain].style
      @detail.text = terrain.description
    end

    # Puts it back to having been pointed at nothing.
    def clear : Nil
      @where.text = ""
      # A label with nothing in it still takes a row, and a blank row under
      # the rule reads as something missing rather than as nothing to say.
      @where.hidden = true
      @what.text = NOTHING
      @what.style = nil
      @detail.text = ""
    end
  end
end
