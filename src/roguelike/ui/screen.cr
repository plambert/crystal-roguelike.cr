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

    # The whole tree, for `App` and for `Layout::Tree`.
    getter root : Widgets::Panel

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
      @map = Widgets::Panel.new(
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow,
        padding: Layout::Padding.symmetric(horizontal: 1))

      @sidebar = Widgets::Panel.new(
        width: Layout::Sizing.fixed(SIDEBAR_WIDTH),
        height: Layout::Sizing.grow,
        padding: Layout::Padding.symmetric(horizontal: 1))

      @gutter = Widgets::Divider.new Widgets::Divider::Orientation::Vertical

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

      @root = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      @root.add upper,
        Widgets::Divider.new(Widgets::Divider::Orientation::Horizontal),
        @status,
        @log
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
      wanted = columns >= SIDEBAR_MINIMUM_COLUMNS

      @sidebar.hidden = !wanted
      @gutter.hidden = !wanted
    end

    # Fills each region with something that says where it is.
    #
    # Scaffolding, and the only part of this class with an opinion about what
    # goes where. Phase 3 takes the map, phase 4 the sidebar, phase 7 the
    # status line and phase 8 the log, and when the last of them has gone so
    # has this method.
    def scaffold(seed : UInt64) : Nil
      @map.add Widgets::Label.new("the map arrives in phase 3")

      @sidebar.add Widgets::Label.new("Look"),
        Widgets::Label.new("nothing under the pointer yet")

      @status.add Widgets::Label.new("seed #{seed}    turn 0")

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
