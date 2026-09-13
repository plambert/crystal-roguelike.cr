module Roguelike::Ui
  # What is underfoot and what is in sight, written out in the sidebar.
  #
  # Two sections. "Here" is the square the character stands on: what is lying
  # there, what is bolted to it, and the staircase if there is one. "Seen" is
  # everything the character can see from that square, creatures first and
  # then items, nearest first.
  #
  # Both read what is there now. Neither reads `Knowledge`. A creature that
  # walked out of sight and an item under a square nobody has light on are
  # gone from this pane, which is what separates it from the map: the map
  # draws what was last seen, and this says what is seen.
  #
  # `ExaminePane` is the other half of the sidebar. That one describes one
  # square somebody pointed at. This one describes the two a person needs
  # without pointing at anything.
  class NearbyPane
    # The heading over what is underfoot.
    HERE = "Here"

    # The heading over what is in sight.
    SEEN = "Seen"

    # What a section says when it has nothing to list.
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
      empty = [] of Widgets::Label

      fill @here, empty, MOST_HERE
      fill @seen, empty, LEAST_SEEN
    end

    # Writes the "Here" section.
    private def underfoot(game : Game) : Nil
      floor = game.floor
      spot = game.player.at
      rows = [] of Widgets::Label

      terrain = floor.terrain spot[0], spot[1]
      rows << row(terrain.label, Palette[terrain].style) if worth_saying? terrain

      fitting = floor.fixture spot[0], spot[1]
      rows << row(fitting.label, Palette[fitting].style) if fitting

      floor.items(spot[0], spot[1]).each do |item|
        rows << row(game.name(item), Palette[item].style)
      end

      fill @here, rows, MOST_HERE
    end

    # Whether standing on *terrain* is worth a row of its own.
    #
    # A floor is not. A staircase is: it is the one square on the level worth
    # coming back to, and a person who walked onto it in the dark has no other
    # way to be told.
    private def worth_saying?(terrain : Terrain) : Bool
      terrain.stairs_down? || terrain.stairs_up?
    end

    # Writes the "Seen" section.
    #
    # Creatures first, then items, each nearest first. The square the
    # character stands on is left out: "Here" has already said what is on it.
    private def in_sight(game : Game, sight : Vision) : Nil
      rows = [] of Widgets::Label

      creatures(game, sight).each do |creature|
        rows << row(creature.label, Palette[creature].style)
      end

      litter(game, sight).each do |item|
        rows << row(game.name(item), Palette[item].style)
      end

      fill @seen, rows, Math.max(@budget - @here.children.size, LEAST_SEEN)
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

    # Every item lying on a square the character can see, nearest first.
    #
    # The character's own square is not one of them. "Here" has it.
    private def litter(game : Game, sight : Vision) : Array(Item)
      here = game.player.at
      found = [] of Lying

      game.floor.each_pile do |column, row, pile|
        next if {column, row} == here
        next unless sight.includes? column, row

        pile.each { |item| found << Lying.new({column, row}, item) }
      end

      found.sort_by! { |lying| NearbyPane.order here, lying.spot }
      found.map &.item
    end

    # One item and the square it is lying on, while the list is being sorted.
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
    private def fill(panel : Widgets::Panel, rows : Array(Widgets::Label),
                     most : Int32) : Nil
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
    private def row(text : String, style : Style?) : Widgets::Label
      label = Widgets::Label.new text
      label.style = style
      label
    end
  end
end
