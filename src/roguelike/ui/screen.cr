module Roguelike::Ui
  # The regions the game is drawn in. This class does not decide what goes in
  # them.
  #
  #     ┌──────────────────────────┬────────────┐
  #     │ map                      │ sidebar    │
  #     │                          │            │
  #     ├──────────────────────────┴────────────┤
  #     │ status                                │
  #     │ log                                   │
  #     └───────────────────────────────────────┘
  #
  # The map takes whatever width is left. The sidebar has a fixed width. It
  # holds a name and a short description. Those read at a width that does not
  # change.
  #
  # The status line is one row. The log is `LOG_ROWS` rows. Both run the
  # whole width, so a long message is not cut off at the sidebar.
  #
  # This class opens no terminal. It reads no event. A `Screen` is a widget
  # tree. A spec builds one, renders it into a buffer, and reads the cells
  # back.
  class Screen
    # How wide the sidebar is.
    #
    # Twenty-four columns holds "a masterwork +1 chain mail" on one line. That
    # is about the longest item name that has to fit without wrapping.
    SIDEBAR_WIDTH = 24

    # The narrowest screen that keeps the sidebar.
    #
    # Under this width the sidebar is hidden rather than squeezed. The
    # number is the sidebar width plus enough map to play in.
    SIDEBAR_MINIMUM_COLUMNS = 60

    # Rows the message log is given.
    LOG_ROWS = 4

    # How many rows are not the map. The rule and the log.
    #
    # There was a status row between them. Everything on it is in the
    # sidebar now, stacked, where there is room for it and for a bar beside
    # each number.
    CHROME_ROWS = 1 + LOG_ROWS

    # The narrowest terminal the game is drawn in.
    #
    # Under this width the log wraps most messages over several rows and the
    # map shows less than one room. The notice is drawn instead of the game,
    # asking for a larger window.
    MINIMUM_COLUMNS = 40

    # The shortest terminal the game is drawn in.
    #
    # `CHROME_ROWS` of the height is not the map. This height leaves ten rows
    # to play in.
    MINIMUM_ROWS = 16

    # The whole tree. `App` and `Layout::Tree` take it.
    #
    # It holds both the game and the notice that there is no room for the
    # game. `#fit` decides which one draws. Swapping between them hides one
    # widget and unhides the other. It does not rebuild the tree.
    getter root : Widgets::Panel

    # The four regions. Hidden while there is no room for them.
    getter playing : Widgets::Panel

    # What draws instead when the terminal is too small.
    getter notice : Widgets::Panel

    # The line in the notice that says how big the terminal is now.
    getter notice_text : Widgets::Label

    # Where the floor is drawn.
    getter map : Widgets::Panel

    # What the character is, and what is around them.
    getter sidebar : Widgets::Panel

    # What has just happened, oldest first.
    getter log : Widgets::Panel

    # The rule between the map and the sidebar. It hides when the sidebar
    # hides.
    getter gutter : Widgets::Divider

    def initialize
      # A map pane has no padding. A map is a grid of cells, and a column
      # given to a margin is one fewer column of the floor.
      @map = Widgets::Panel.new(
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)

      # A blank row between the panes stacked in it. Each writes its own
      # heading and rule, and two of them touching read as one pane.
      @sidebar = Widgets::Panel.new(
        width: Layout::Sizing.fixed(SIDEBAR_WIDTH),
        height: Layout::Sizing.grow,
        padding: Layout::Padding.symmetric(horizontal: 1),
        gap: 1)

      @gutter = Widgets::Divider.new Widgets::Divider::Orientation::Vertical

      @log = Widgets::Panel.new(
        width: Layout::Sizing.grow,
        height: Layout::Sizing.fixed(LOG_ROWS),
        padding: Layout::Padding.symmetric(horizontal: 1))

      upper = Widgets::Panel.new(
        direction: Layout::Direction::Row,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      upper.add @map, @gutter, @sidebar

      @playing = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      @playing.add upper,
        Widgets::Divider.new(Widgets::Divider::Orientation::Horizontal),
        @log

      @notice_text = Widgets::Label.new "", align: TermBuf::Unicode::Align::Center
      @notice = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow,
        padding: Layout::Padding.all(1),
        align_x: Layout::Align::Center,
        align_y: Layout::Align::Center)
      @notice.add @notice_text
      @notice.hidden = true

      @root = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      @root.add @playing, @notice
    end

    # Whether a terminal of *columns* by *rows* has room for the game.
    def self.fits?(columns : Int32, rows : Int32) : Bool
      columns >= MINIMUM_COLUMNS && rows >= MINIMUM_ROWS
    end

    # What to tell a person whose terminal is *columns* by *rows*.
    def self.too_small(columns : Int32, rows : Int32) : String
      "This game requires #{MINIMUM_COLUMNS} columns and #{MINIMUM_ROWS} rows " \
      "in the terminal, please resize larger. This one is #{columns} by #{rows}."
    end

    # Answers the layout to a screen of *columns* by *rows*.
    #
    # The layout engine divides the space it is given. It never decides that a
    # pane is not worth showing. This method makes that decision. It records
    # the decision with `#hidden?`. A hidden widget leaves the layout. It takes no size, no
    # position and no gap.
    #
    # Whatever owns the terminal calls this before the first frame. It calls
    # it again on every resize.
    def fit(columns : Int32, rows : Int32) : Nil
      room = Screen.fits? columns, rows

      unless room
        @notice_text.text = Screen.too_small columns, rows
      end

      @playing.hidden = !room
      @notice.hidden = room

      wanted = room && columns >= SIDEBAR_MINIMUM_COLUMNS
      @sidebar.hidden = !wanted
      @gutter.hidden = !wanted
    end

    # Whether the game is being drawn. The notice draws otherwise.
    def playing? : Bool
      !@playing.hidden?
    end

    # Puts *widget* in the map pane. Takes out whatever was there.
    #
    # `Ui::MapPane` goes here.
    def show(widget : Widgets::Widget) : Nil
      @map.clear
      @map.add widget
    end

    # Puts *widget* in the log pane. Takes out whatever was there.
    #
    # `TermBuf::Widgets::Pager` goes here.
    def show_log(widget : Widgets::Widget) : Nil
      @log.clear
      @log.add widget
    end

    # How wide the log pane's text is on a screen of *columns*.
    #
    # The pane runs the whole width. Its padding takes one column on each
    # side.
    def self.log_width(columns : Int32) : Int32
      Math.max columns - 2, 0
    end

    # Puts *widgets* in the sidebar, stacked in the order given. Takes out
    # whatever was there.
    #
    # `Ui::CharacterPane` goes at the top, then `Ui::NearbyPane` and
    # `Ui::ExaminePane`. What the character is does not move when what is in
    # sight does, so the block a person reads every turn is the fixed one.
    def show_sidebar(*widgets : Widgets::Widget) : Nil
      @sidebar.clear
      widgets.each { |widget| @sidebar.add widget }
    end

    # Whether the sidebar is being shown.
    def sidebar? : Bool
      !@sidebar.hidden?
    end

    # How many rows the map pane gets on a screen of *rows*.
    def self.map_rows(rows : Int32) : Int32
      Math.max rows - CHROME_ROWS, 0
    end
  end
end
