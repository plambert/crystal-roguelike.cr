module Roguelike::Ui
  # What is on one square, written out in the sidebar.
  #
  # This pane holds the last square it was pointed at. It does not blank
  # when the pointer moves off the map, because the pointer crosses the log
  # on its way to anywhere else.
  class ExaminePane
    # The heading. It says what the pane is for while the pane is empty.
    HEADING = "Look"

    # What the pane says before anything has been looked at.
    NOTHING = "Point at the map, or press x."

    # What the pane says about a square the character has never seen.
    #
    # The pointer reaches any square of the floor. The readout must not, or
    # the whole map could be read with the mouse and the field of view would
    # be worth nothing.
    UNSEEN = "out of sight"

    # What the pane adds about a square the character remembers but cannot
    # see. What is there now may be something else.
    REMEMBERED = "remembered"

    # What the pane says about a shape against light behind it.
    MOVING = "something moving against the light"

    # The widget itself. A caller puts it in a tree.
    getter root : Widgets::Panel

    # Where the readout points, in the floor's own coordinates.
    getter where : Widgets::Label

    # What is on that square.
    getter what : Widgets::Label

    # A sentence about it.
    getter detail : Widgets::Label

    # What a creature on the square is doing. Blank for a square with none.
    getter doing : Widgets::Label

    # What is lying on the square.
    getter litter : Widgets::Label

    # What a shot at the square would do. Blank when nothing is being aimed.
    getter aim : Widgets::Label

    def initialize
      @where = Widgets::Label.new ""
      @what = Widgets::Label.new NOTHING
      @detail = Widgets::Label.new ""
      @doing = Widgets::Label.new ""
      @doing.hidden = true
      @doing.style = Style::DEFAULT.faint

      @litter = Widgets::Label.new ""
      @litter.hidden = true

      @aim = Widgets::Label.new ""
      @aim.hidden = true
      @aim.style = Style::DEFAULT.bold

      heading = Widgets::Label.new HEADING
      heading.style = Style::DEFAULT.bold
      heading.height = Layout::Sizing.fixed 1
      @where.style = Style::DEFAULT.faint
      @where.hidden = true

      @root = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      @root.add heading,
        Widgets::Divider.new(Widgets::Divider::Orientation::Horizontal),
        @where, @what, @detail, @doing, @litter, @aim
    end

    # Says what a shot at the square being pointed at would do. `nil` says
    # nothing at all.
    #
    # `#show` does not touch this row. The readout is pointed at a square
    # whether or not anything is being aimed, so whatever is aiming owns it.
    def aiming=(line : String?) : Nil
      @aim.text = line || ""
      @aim.hidden = line.nil?
    end

    # Says what is on *floor* at *x*, *y*.
    #
    # *lore* names whatever is lying there, because the name depends on what
    # the character has found out. *sight* says which squares the character
    # can see. A `nil` *sight* sees everything.
    def show(floor : Floor, x : Int32, y : Int32, lore : Lore? = nil,
             sight : Vision? = nil, knowledge : Knowledge? = nil) : Nil
      unless sight.nil? || sight.includes?(x, y)
        shape = sight.backlit?(floor, x, y) ? floor.monster(x, y) : nil
        if shape
          outlined x, y, shape
          return
        end

        recalled floor, x, y, lore, knowledge.try &.[](x, y)
        return
      end

      terrain = floor.terrain x, y
      fitting = floor.fixture x, y
      creature = floor.monster x, y

      @where.text = "#{x}, #{y}"
      @where.hidden = false

      @doing.hidden = creature.nil?

      if creature
        @what.text = creature.label
        @what.style = Palette[creature].style
        @detail.text = creature.description
        @doing.text = "It is #{floor.awareness(creature).label}."
      elsif fitting
        @what.text = fitting.label
        @what.style = Palette[fitting].style
        @detail.text = fitting.description
      else
        @what.text = terrain.label
        @what.style = Palette[terrain].style
        @detail.text = terrain.description
      end

      pile = floor.items x, y
      @litter.hidden = pile.empty?
      @litter.text = listed pile, lore
    end

    # Says that *creature* is a shape and no more.
    #
    # Its size, because that is what somebody makes out. Not its name and not
    # what it is doing: a shape against light says neither.
    private def outlined(x : Int32, y : Int32, creature : Monster) : Nil
      @where.text = "#{x}, #{y}"
      @where.hidden = false
      @what.text = creature.species.size.label
      @what.style = Palette.shape(creature.species.size).style
      @detail.text = MOVING
      @doing.text = ""
      @doing.hidden = true
      @litter.text = ""
      @litter.hidden = true
    end

    # Says what *x*, *y* looked like when it was last seen, or that it has
    # never been seen.
    private def recalled(floor : Floor, x : Int32, y : Int32, lore : Lore?,
                         memory : Memory?) : Nil
      @where.text = "#{x}, #{y}"
      @where.hidden = false
      @doing.text = ""
      @doing.hidden = true
      @litter.text = ""
      @litter.hidden = true

      unless memory
        @what.text = UNSEEN
        @what.style = Style::DEFAULT.faint
        @detail.text = ""
        return
      end

      fitting = memory.fixture
      @what.text = fitting ? fitting.label : memory.terrain.label
      @what.style = Style::DEFAULT.faint
      @detail.text = REMEMBERED

      item = memory.item
      return unless item

      @litter.hidden = false
      @litter.text = lore ? "Here: #{lore.name item}" : "Here: something"
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
      @doing.text = ""
      @doing.hidden = true
      @litter.text = ""
      @litter.hidden = true
      self.aiming = nil
    end
  end
end
