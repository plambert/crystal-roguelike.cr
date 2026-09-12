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
  # The status line is one row. The log is `LOG_ROWS` rows. Both run the whole
  # width. A message cut off at the sidebar would be half a message.
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
    # A map pane narrower than the sidebar beside it is not a map pane. Under
    # this width the sidebar is hidden rather than squeezed. The number is the
    # sidebar width plus enough map to play in.
    SIDEBAR_MINIMUM_COLUMNS = 60

    # Rows the message log is given.
    LOG_ROWS = 4

    # How many rows are not the map. The rule, the status line and the log.
    CHROME_ROWS = 1 + 1 + LOG_ROWS

    # The narrowest terminal the game is drawn in.
    #
    # Under this width the log wraps to something nobody can read. The map
    # shows less than one room. The notice is drawn instead of the game. The
    # notice asks for a larger window.
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

    # The status line's scaffolding, until phase 7 puts something real there.
    getter status_text : Widgets::Label

    # Where the level is drawn.
    getter map : Widgets::Panel

    # What is under the pointer, and later the character summary.
    getter sidebar : Widgets::Panel

    # One row. It will hold hit points, attributes, depth and gold.
    getter status : Widgets::Panel

    # What has just happened, oldest first.
    getter log : Widgets::Panel

    # The rule between the map and the sidebar. It hides when the sidebar
    # hides.
    getter gutter : Widgets::Divider

    def initialize
      # A map pane has no padding. A map is a grid of cells. A column given
      # to a margin is a column of the level nobody can see.
      @map = Widgets::Panel.new(
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)

      @sidebar = Widgets::Panel.new(
        width: Layout::Sizing.fixed(SIDEBAR_WIDTH),
        height: Layout::Sizing.grow,
        padding: Layout::Padding.symmetric(horizontal: 1))

      @gutter = Widgets::Divider.new Widgets::Divider::Orientation::Vertical

      @status_text = Widgets::Label.new ""
      @status = Widgets::Panel.new(
        width: Layout::Sizing.grow,
        height: Layout::Sizing.fixed(1),
        padding: Layout::Padding.symmetric(horizontal: 1))

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
        @status,
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

    # Puts *widget* in the status row beside the status text.
    #
    # The row is one row tall. Exactly one of the two may be visible at a
    # time. A hidden widget takes no room, so the visible one gets the row.
    #
    # `TermBuf::Widgets::Prompt` goes here. It hides itself while nobody is
    # asking.
    def show_status(widget : Widgets::Widget) : Nil
      @status.add widget
    end

    # Puts *widget* in the sidebar. Takes out whatever was there.
    #
    # `Ui::ExaminePane` goes here.
    def show_sidebar(widget : Widgets::Widget) : Nil
      @sidebar.clear
      @sidebar.add widget
    end

    # Fills the regions that have nothing of their own yet.
    #
    # This is scaffolding. Phase 7 takes the status line. Phase 8 takes the
    # log. This method goes when the second of those lands.
    def scaffold(seed : UInt64) : Nil
      @status_text.text = "seed #{seed}    turn 0"
      @status.add @status_text

      @log.add Widgets::Label.new(
        "Welcome to the dungeon. ? for the keys, Q to leave.")
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
