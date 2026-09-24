module Roguelike::Ui
  # What is underfoot and what is in sight, written out in the sidebar.
  #
  # Two sections. "Here" is the square the character stands on. It says what
  # the square is made of, what is bolted to it, and what is lying there.
  # "Seen" is everything the character can see from that square. Creatures
  # come first, then items. Both are nearest first.
  #
  # Both sections read what is there now. Neither reads `Knowledge`. A
  # creature that has walked out of sight leaves this pane, and so does an
  # item nobody has light on. The map instead draws what was last seen.
  #
  # Pointing at a row raises a tooltip about what is on it: the creature, the
  # item, the fixture or the terrain the row names. The pane writes the lines
  # and `Play` puts the box up.
  #
  # `ExaminePane` is the other half of the sidebar. That pane describes one
  # square somebody pointed at. This pane writes both its sections without
  # being pointed anywhere.
  class NearbyPane
    # The heading over what is underfoot.
    HERE = "Here"

    # The heading over what is in sight.
    SEEN = "Seen"

    # What "Seen" says when it has nothing to list.
    #
    # "Here" never says this. It has the terrain to fall back on.
    NOTHING = "nothing"

    # How many rows the "Here" section takes before it elides.
    #
    # A pile deep enough to need more than this is a pile to walk onto and
    # read with `,`.
    MOST_HERE = 5

    # How many rows the "Seen" section takes at the narrowest, whatever the
    # budget says.
    LEAST_SEEN = 3

    # How many rows both sections take when nobody has said otherwise.
    BUDGET = 20

    # The widget itself. A caller puts it in a tree.
    getter root : Widgets::Panel

    # The rows under "Here".
    getter here : Widgets::Panel

    # The rows under "Seen".
    getter seen : Widgets::Panel

    # What runs when the pointer crosses a row.
    #
    # `Play` puts the lines up in a tooltip beside the row. A row about
    # nothing in particular, such as the one saying how much was left out,
    # hands over `nil` and takes any box that was up back down.
    property on_point : Proc(Line, Array(String)?, Nil)? = nil

    # How many rows the two sections may take between them.
    #
    # The owner works this out from the height of the screen and sets it on
    # every resize. Anything past it is elided into one row saying how much
    # was left out, so the pane never pushes what is under it off the bottom.
    property budget : Int32 = BUDGET

    def initialize
      @here = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow)

      @seen = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow)

      # A blank row between the two sections. Two lists run together under
      # one rule read as one list.
      @root = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        gap: 1)
      @root.add NearbyPane.section(HERE, @here),
        NearbyPane.section(SEEN, @seen)

      clear
    end

    # One section: a heading, a rule, and *rows* under them.
    #
    # `ExaminePane` writes its own heading the same way. The sidebar is three
    # of these stacked.
    def self.section(title : String, rows : Widgets::Panel) : Widgets::Panel
      heading = Widgets::Label.new title
      heading.style = Style::DEFAULT.bold

      # One row, always. A heading of its own height is the first thing the
      # layout squeezes when the sidebar runs out, and a rule with no
      # heading over it says nothing at all.
      heading.height = Layout::Sizing.fixed 1

      panel = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow)
      panel.add heading,
        Widgets::Divider.new(Widgets::Divider::Orientation::Horizontal),
        rows
      panel
    end

    # Writes both sections from *game* and what it can see.
    #
    # *sight* is what the character can see now. `Play` has already worked it
    # out for the map, and one cast serves both.
    def show(game : Game, sight : Vision) : Nil
      underfoot game
      in_sight game, sight
    end

    # Puts the pane back to the state before there was a game.
    def clear : Nil
      empty = [] of Line

      fill @here, empty, MOST_HERE
      fill @seen, empty, LEAST_SEEN
    end

    # Writes the "Here" section.
    #
    # The terrain always takes the first row. Nobody reads it while it goes
    # on saying the same thing. Everybody notices it change. That is the turn
    # somebody walked onto a staircase or into a doorway.
    private def underfoot(game : Game) : Nil
      floor = game.floor
      spot = game.player.at
      rows = [] of Line

      terrain = floor.terrain spot[0], spot[1]
      rows << row(terrain.label, Palette[terrain].style, Detail.about(terrain))

      fitting = floor.fixture spot[0], spot[1]
      rows << row(fitting.label, Palette[fitting].style, Detail.about(fitting)) if fitting

      # The character stands on these, so they have made all of them out.
      floor.items(spot[0], spot[1]).each do |item|
        rows << row(game.name(item), Palette[item].style, Detail.about(game, item))
      end

      fill @here, rows, MOST_HERE
    end

    # Writes the "Seen" section.
    #
    # Creatures first, then items, each nearest first. The square the
    # character stands on is left out: "Here" has already said what is on it.
    #
    # An item further off than `Regards::READING` is named by its kind alone.
    # The character can see it lying there and cannot read what is on it.
    private def in_sight(game : Game, sight : Vision) : Nil
      rows = [] of Line

      creatures(game, sight).each do |creature|
        rows << creature_row game, sight, creature
      end

      litter(game, sight).each do |lying|
        item = lying.item
        regard = game.regard_of_item lying.spot[0], lying.spot[1], sight
        rows << row(game.name(item, regard), Palette[item].style,
          Detail.about(game, item, regard))
      end

      fill @seen, rows, Math.max(@budget - @here.children.size, LEAST_SEEN)
    end

    # One row for *creature*.
    #
    # A creature on a square the character can see is named. One made out
    # only as a shape against light behind it is not: its size is all that
    # reaches the character, so its size is all this says.
    private def creature_row(game : Game, sight : Vision, creature : Monster) : Line
      regard = game.regard_of creature, sight
      lines = Detail.about game, creature, regard
      return row(creature.label, Palette[creature].style, lines) if regard.everything?

      size = creature.species.size
      row size.label, Palette.shape(size).style, lines
    end

    # Every creature the character can see, nearest first.
    private def creatures(game : Game, sight : Vision) : Array(Monster)
      here = game.player.at
      found = [] of Monster

      game.floor.each_monster do |column, row, creature|
        found << creature if sight.shows? game.floor, column, row
      end

      found.sort_by! { |creature| NearbyPane.order here, creature.at }
    end

    # Every item lying on a square the character can see, nearest first,
    # each with the square it lies on.
    #
    # The character's own square is not one of them. "Here" has it.
    #
    # The square comes back with the item. How well the character has made
    # the item out depends on how far off it is lying, so both the row that
    # names it and the box that hangs off that row need to know where it is.
    private def litter(game : Game, sight : Vision) : Array(Lying)
      here = game.player.at
      found = [] of Lying

      game.floor.each_pile do |column, row, pile|
        next if {column, row} == here
        next unless sight.includes? column, row

        pile.each { |item| found << Lying.new({column, row}, item) }
      end

      found.sort_by! { |lying| NearbyPane.order here, lying.spot }
    end

    # One item and the square it is lying on.
    record Lying, spot : {Int32, Int32}, item : Item

    # How far *there* is from *here*, and which of two equally far squares
    # comes first.
    #
    # The squared distance, then the row, then the column. Two creatures the
    # same distance off are listed the same way every turn.
    def self.order(here : {Int32, Int32}, there : {Int32, Int32}) : {Int32, Int32, Int32}
      across = there[0] - here[0]
      down = there[1] - here[1]

      {across * across + down * down, there[1], there[0]}
    end

    # Puts *rows* in *panel*, no more than *most* of them.
    #
    # A row saying how many were left out goes on the end when there were
    # more. An empty list says so rather than leaving a gap under the rule.
    private def fill(panel : Widgets::Panel, rows : Array(Line),
                     most : Int32) : Nil
      # The rows are built again every turn. The row that held the mark is
      # gone. The mark goes with it.
      unmark
      panel.clear

      if rows.empty?
        panel.add row(NOTHING, Style::DEFAULT.faint)
        return
      end

      room = Math.max most, 1
      return rows.each { |line| panel.add line } if rows.size <= room

      rows.first(room - 1).each { |line| panel.add line }
      panel.add row("and #{rows.size - room + 1} more", Style::DEFAULT.faint)
    end

    # One row of a section.
    #
    # *lines* is what a tooltip says about what is on the row. A row about
    # nothing in particular passes none, and pointing at it takes down
    # whatever box was up.
    #
    # The text starts `Line::INDENT` cells in. The marks go in those cells
    # when the pointer crosses the row. The cells are kept clear on every
    # row, so a row does not move under the pointer.
    private def row(text : String, style : Style?,
                    lines : Array(String)? = nil) : Line
      line = Line.new

      # One row at most, and none when the sidebar has run out of room. A row
      # that could not be squeezed would take its cell off the log below it.
      line.height = Layout::Sizing.fit max: 1
      line.put Line::INDENT, text, style || Style::DEFAULT
      line.on_point = -> { pointed line, lines }
      line
    end

    # The marks on the row the pointer is on.
    MARKS = Line::Marks.new Palette::POINTER, Palette::POINTED,
      Palette::POINTER_MARK

    # Hands *lines* to whoever is watching the pane.
    #
    # The row the pointer is on is marked and the one it left is not. One
    # row is marked at a time.
    #
    # The hook is read here rather than closed over, so a pane whose rows
    # were built before the hook was put on still reports.
    private def pointed(line : Line, lines : Array(String)?) : Nil
      mark line
      @on_point.try &.call(line, lines)
    end

    # Puts the marks on *line* and takes them off the row that had them.
    private def mark(line : Line) : Nil
      before = @marked
      return if before == line

      before.marks = nil if before
      line.marks = MARKS
      @marked = line
    end

    # Takes the marks off the marked row unless *row* is that row.
    #
    # `Play` calls this once a pointer report has been through the tree.
    # *row* is the row of the whole sidebar that the report reached. A
    # pointer on a row of another pane, or off the sidebar, leaves this pane
    # with no marked row.
    def keep(row : Widgets::Widget?) : Nil
      return if row && row.same? @marked

      unmark
    end

    # Takes the marks off the marked row.
    #
    # `Play` calls this when the pointer leaves the sidebar. A row left
    # marked would show the pointer on it after the pointer is gone.
    def unmark : Nil
      found = @marked
      return unless found

      found.marks = nil
      @marked = nil
    end

    # The last row this pane was given as the row under the pointer.
    @marked : Line? = nil
  end
end
