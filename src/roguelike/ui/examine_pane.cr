module Roguelike::Ui
  # What is on one square, written out in the sidebar.
  #
  # This pane holds the last square it was pointed at. It does not blank when
  # the pointer moves off the map. A panel that empties whenever the pointer
  # crosses the log is a panel nobody can read.
  class ExaminePane
    # The heading. It says what the pane is for while the pane is empty.
    HEADING = "Look"

    # What the pane says before anything has been looked at.
    NOTHING = "Point at the map, or press x."

    # The widget itself. A caller puts it in a tree.
    getter root : Widgets::Panel

    # Where the readout points, in the level's own coordinates.
    getter where : Widgets::Label

    # What is on that square.
    getter what : Widgets::Label

    # A sentence about it.
    getter detail : Widgets::Label

    # What is lying on the square.
    getter litter : Widgets::Label

    def initialize
      @where = Widgets::Label.new ""
      @what = Widgets::Label.new NOTHING
      @detail = Widgets::Label.new ""
      @litter = Widgets::Label.new ""
      @litter.hidden = true

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
        @where, @what, @detail, @litter
    end

    # Says what is on *level* at *x*, *y*.
    #
    # *lore* names whatever is lying there, because the name depends on what
    # the character has found out.
    def show(level : Level, x : Int32, y : Int32, lore : Lore? = nil) : Nil
      terrain = level.terrain x, y

      @where.text = "#{x}, #{y}"
      @where.hidden = false
      @what.text = terrain.label
      @what.style = Palette[terrain].style
      @detail.text = terrain.description

      pile = level.items x, y
      @litter.hidden = pile.empty?
      @litter.text = listed pile, lore
    end

    # What is lying on a square, written out.
    private def listed(pile : Array(Item), lore : Lore?) : String
      return "" if pile.empty?
      return "Here: #{pile.size} things" unless lore

      named = pile.map { |item| lore.name(item).as(String) }
      "Here: #{named.join ", "}"
    end

    # Puts the pane back to the state before anything was looked at.
    def clear : Nil
      @where.text = ""
      # An empty label still takes a row. A blank row under the rule reads as
      # something missing. A hidden label takes no row.
      @where.hidden = true
      @what.text = NOTHING
      @what.style = nil
      @detail.text = ""
      @litter.text = ""
      @litter.hidden = true
    end
  end
end
