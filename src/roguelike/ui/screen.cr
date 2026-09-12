module Roguelike::Ui
  # The regions the game is drawn in, and nothing about what goes in them.
  #
  #     ┌──────────────────────────┬────────────┐
  #     │ map                      │ sidebar    │
  #     │                          │            │
  #     ├──────────────────────────┴────────────┤
  #     │ status                                │
  #     │ log                                   │
  #     └───────────────────────────────────────┘
  #
  # The map grows to whatever is left. The sidebar is a fixed width, because
  # what goes in it is a name and a short description and those read at a
  # width that does not move. The status line is one row and the log is
  # `LOG_ROWS`, both across the whole screen, because a message cut off at the
  # sidebar would be a message half read.
  #
  # Nothing here opens a terminal or reads an event. A `Screen` is a widget
  # tree, so a spec builds one, renders it into a buffer and reads the cells
  # back.
  class Screen
    # How wide the sidebar is. Twenty-four columns holds "a masterwork +1
    # chain mail" on one line, which is about the longest thing that has to
    # fit without wrapping.
    SIDEBAR_WIDTH = 24

    # Under this the sidebar is dropped rather than squeezed, because a map
    # pane narrower than the sidebar beside it is no longer a map pane. The
    # number is the sidebar plus enough map to play in.
    SIDEBAR_MINIMUM_COLUMNS = 60

    # Rows the message log is given.
    LOG_ROWS = 4

    # Rows that are not the map: the rule, the status line and the log.
    CHROME_ROWS = 1 + 1 + LOG_ROWS

    # The narrowest terminal the game is drawn in.
    #
    # Under this the log wraps to something nobody can read and the map shows
    # less than a room. There is no point drawing a game there, so the notice
    # is drawn instead and the player is asked for a larger window.
    MINIMUM_COLUMNS = 40

    # The shortest, for the same reason: `CHROME_ROWS` of it is not the map,
    # so this leaves ten rows to play in.
    MINIMUM_ROWS = 16

    # The whole tree, for `App` and for `Layout::Tree`.
    #
    # Holds both the game and the notice that there is no room for it. Which
    # one is drawn is `#fit`'s to decide, and swapping between them is two
    # widgets being hidden and unhidden rather than a tree being rebuilt.
    getter root : Widgets::Panel

    # The four regions, hidden while there is no room for them.
    getter playing : Widgets::Panel

    # What is drawn instead when the terminal is too small.
    getter notice : Widgets::Panel

    # The line in the notice that says how big the terminal is now.
    getter notice_text : Widgets::Label

    # The status line's scaffolding, until phase 7 puts something real there.
    getter status_text : Widgets::Label

    # Where the level is drawn.
    getter map : Widgets::Panel

    # What is under the pointer, and later the character summary.
    getter sidebar : Widgets::Panel

    # One row: hit points, attributes, depth, gold.
    getter status : Widgets::Panel

    # What has just happened, oldest first.
    getter log : Widgets::Panel

    # The rule between the map and the sidebar, which goes when it does.
    getter gutter : Widgets::Divider

    def initialize
      # No padding: a map is a grid of cells and a column given up to a
      # margin is a column of the level nobody can see.
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

    # What to say to somebody whose terminal is *columns* by *rows*.
    def self.too_small(columns : Int32, rows : Int32) : String
      "This game requires #{MINIMUM_COLUMNS} columns and #{MINIMUM_ROWS} rows " \
      "in the terminal, please resize larger. This one is #{columns} by #{rows}."
    end

    # Answers the layout to a screen of *columns* by *rows*.
    #
    # The layout engine apportions what it is given and does not decide that a
    # pane is no longer worth having, so that decision is made here and said
    # with `#hidden?`, which takes a widget out of the layout entirely — no
    # size, no position, and no gap where it was.
    #
    # Called before the first frame and again on every resize, by whatever
    # owns the terminal.
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

    # Whether the game, rather than the notice, is being drawn at the size it
    # was last fitted to.
    def playing? : Bool
      !@playing.hidden?
    end

    # Puts *widget* in the map pane, taking out whatever was there.
    #
    # What `Ui::MapPane` is hung on, and what a level being swapped for
    # another goes through.
    def show(widget : Widgets::Widget) : Nil
      @map.clear
      @map.add widget
    end

    # Puts *widget* in the sidebar, taking out whatever was there.
    #
    # What `Ui::ExaminePane` is hung on.
    def show_sidebar(widget : Widgets::Widget) : Nil
      @sidebar.clear
      @sidebar.add widget
    end

    # Fills the regions that have nothing of their own yet with something that
    # says where they are.
    #
    # Scaffolding. Phase 7 takes the status line and phase 8 the log, and when
    # the second of them has gone so has this method.
    def scaffold(seed : UInt64) : Nil
      @status_text.text = "seed #{seed}    turn 0"
      @status.add @status_text

      @log.add Widgets::Label.new(
        "Welcome to the dungeon. ? for the keys, Q to leave.")
    end

    # Whether the sidebar is being shown at the size it was last fitted to.
    def sidebar? : Bool
      !@sidebar.hidden?
    end

    # Rows the map pane comes to on a screen of *rows*, which is what the
    # camera has to work with.
    def self.map_rows(rows : Int32) : Int32
      Math.max rows - CHROME_ROWS, 0
    end
  end
end
