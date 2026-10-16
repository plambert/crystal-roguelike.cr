require "../../crystal-roguelike"

module Roguelike::Ui
  # The regions the game is drawn in. This class does not decide what goes in
  # them.
  #
  #     ┌────────────┬──────────────────────────────┐
  #     │ info       │ map                          │
  #     │            │                              │
  #     │            │                              │
  #     │            ├──────────────────────────────┤
  #     │            │ log                          │
  #     └────────────┴──────────────────────────────┘
  #
  # The info panel runs the whole height on the left. Its width depends on
  # the terminal width. See `.info_width`. The vitals are pinned at its top.
  # The sections under them scroll as one when they are taller than the
  # room left, and the rule beside the panel carries the thumb.
  #
  # The map and the log share the right side. The map takes whatever is
  # left. A rule under the map names the floor. The log is `LOG_ROWS` rows,
  # or `TALL_LOG_ROWS` on a tall terminal.
  #
  # This class opens no terminal. It reads no event. A `Screen` is a widget
  # tree. A spec builds one, renders it into a buffer, and reads the cells
  # back.
  class Screen
    # How wide the info panel is on a terminal of `INFO_GROWS_FROM` columns
    # or fewer.
    #
    # Twenty-four columns holds "a masterwork +1 chain mail" on one line. That
    # is about the longest item name that has to fit without wrapping.
    INFO_WIDTH = 24

    # The widest the info panel gets.
    INFO_MOST_WIDTH = 36

    # The terminal width the info panel starts to grow at.
    #
    # An 80 column terminal keeps the narrow panel, so the map still shows a
    # whole room.
    INFO_GROWS_FROM = 100

    # How many terminal columns the info panel takes for each column it
    # grows.
    INFO_GROWTH = 4

    # The fewest map columns worth playing in beside the info panel.
    LEAST_MAP_COLUMNS = 35

    # The narrowest screen that keeps the info panel.
    #
    # Under this width the panel is hidden rather than squeezed. The number
    # is the panel, the rule beside it, and enough map to play in.
    INFO_MINIMUM_COLUMNS = INFO_WIDTH + 1 + LEAST_MAP_COLUMNS

    # The info panel's width under the name it had before it moved left.
    SIDEBAR_WIDTH = INFO_WIDTH

    # :ditto:
    SIDEBAR_MINIMUM_COLUMNS = INFO_MINIMUM_COLUMNS

    # Rows the message log is given.
    LOG_ROWS = 4

    # Rows the message log is given on a terminal taller than `TALL_ROWS`.
    TALL_LOG_ROWS = 6

    # The height above which a terminal counts as tall.
    TALL_ROWS = 40

    # The share of the terminal's height the focused log may grow to, in
    # percent.
    LOG_MOST_SHARE = 25

    # What a banner too wide for the window ends with.
    BANNER_ELLIPSIS = "\u2026"

    # The banner, or `nil` when nothing put one up.
    #
    # `replay view` puts the transport on it. It takes the top row of the log
    # pane, so the map keeps every row it has and the log shows one line
    # fewer.
    getter banner : Widgets::Label? = nil

    # The height `#fit` was last given.
    @rows : Int32 = 0

    # How many rows the log pane is now. `#fit` sets it to
    # `.log_height`, and `#grow_log` changes it.
    getter log_size : Int32 = LOG_ROWS

    # The narrowest terminal the game is drawn in.
    #
    # Under this width the log wraps most messages over several rows and the
    # map shows less than one room. The notice is drawn instead of the game,
    # asking for a larger window.
    MINIMUM_COLUMNS = 40

    # The shortest terminal the game is drawn in.
    #
    # The rule and the log take five rows of this height. That leaves eleven
    # rows of map.
    MINIMUM_ROWS = 16

    # The window the info panel's sections scroll in.
    #
    # It never takes the keyboard, and it binds no keys. The movement keys
    # move the character. The wheel scrolls it, and so does the thumb on the
    # rule beside it.
    class Scroll < Widgets::Scrollable
      def focusable? : Bool
        false
      end

      # A window can be any height, since it scrolls what does not fit. The
      # engine measures its least height from its content, which would push
      # it past the room under the pinned vitals.
      def min_height : Int32
        clip_y? ? 0 : super
      end
    end

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

    # The info panel: the pinned block over the scrolling sections. The
    # focus tint goes on this, so it covers both.
    getter info_panel : Widgets::Panel

    # What is pinned at the top of the info panel.
    getter pinned : Widgets::Panel

    # The window the info panel's sections scroll in.
    getter info : Scroll

    # What has just happened, oldest first.
    getter log : Widgets::Panel

    # The rule between the info panel and the right side. It runs the
    # panel's whole height and carries the thumb of the sections' scroll. It
    # hides when the panel hides.
    getter gutter : Widgets::RuleBar

    # The rule under the map. It names the floor.
    getter rule : Widgets::Divider

    def initialize
      # A map pane has no padding. A map is a grid of cells, and a column
      # given to a margin is one fewer column of the floor.
      @map = Widgets::Panel.new(
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)

      # The sections pad their own rows, so their headers can span the
      # whole width.
      @pinned = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.fit)
      @info = Scroll.new(
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      @info.keymap = nil
      @info_panel = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.fixed(INFO_WIDTH),
        height: Layout::Sizing.grow)
      @info_panel.add @pinned, @info

      @gutter = Widgets::RuleBar.new @info, Widgets::Scrollbar::Orientation::Vertical
      @rule = Widgets::Divider.new Widgets::Divider::Orientation::Horizontal

      # The column on the right is the log's scrollbar, so the padding is on
      # the left only.
      @log = Widgets::Panel.new(
        width: Layout::Sizing.grow,
        height: Layout::Sizing.fixed(LOG_ROWS),
        padding: Layout::Padding.new(left: 1))

      right = Widgets::Panel.new(
        direction: Layout::Direction::Column,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      right.add @map, @rule, @log

      @playing = Widgets::Panel.new(
        direction: Layout::Direction::Row,
        width: Layout::Sizing.grow,
        height: Layout::Sizing.grow)
      @playing.add @info_panel, @gutter, right

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

    # The info panel under the name it had before it moved left.
    def sidebar : Scroll
      @info
    end

    # How wide the info panel is on a terminal of *columns*.
    #
    # It is `INFO_WIDTH` up to `INFO_GROWS_FROM` columns. Past that it gains
    # a column for every `INFO_GROWTH` columns, and stops at
    # `INFO_MOST_WIDTH`, which a terminal of 148 columns reaches. Item names
    # then stop wrapping, and the map keeps most of the extra width.
    def self.info_width(columns : Int32) : Int32
      grown = Math.max(columns - INFO_GROWS_FROM, 0) // INFO_GROWTH
      Math.min INFO_WIDTH + grown, INFO_MOST_WIDTH
    end

    # Whether a terminal of *columns* keeps the info panel.
    def self.info?(columns : Int32) : Bool
      columns >= INFO_MINIMUM_COLUMNS
    end

    # How many rows the log pane is on a terminal of *rows*.
    def self.log_height(rows : Int32) : Int32
      rows > TALL_ROWS ? TALL_LOG_ROWS : LOG_ROWS
    end

    # The most rows the focused log pane grows to on a terminal of *rows*.
    # It is `LOG_MOST_SHARE` percent of the height, and never less than
    # `.log_height`.
    def self.log_most(rows : Int32) : Int32
      Math.max rows * LOG_MOST_SHARE // 100, log_height(rows)
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

    # What to tell a person whose terminal was found to have *capabilities*,
    # or `nil` when it has the 256 colours the game is drawn in.
    #
    # The palette is greys. Sixteen colours fold them onto black and white,
    # and the lit shades of a wall land on black, so the game refuses to draw
    # rather than draw that. The message names the variables detection read,
    # since those are what a person can change.
    def self.too_few_colors(capabilities : TermBuf::Capabilities,
                            env : Hash(String, String) = ENV.to_h) : String?
      return if capabilities.includes? TermBuf::Capability::Color256

      found = capabilities.includes?(TermBuf::Capability::Color16) ? "16 colours" : "no colour"
      read = %w[TERM COLORTERM VTE_VERSION NO_COLOR].compact_map do |name|
        env[name]?.try { |value| "#{name}=#{value}" }
      end
      read << "no TERM" unless env["TERM"]?

      "This game requires 256 colours, and this terminal was found to have " \
      "#{found} (#{read.join ", "}). A terminal that has them is usually " \
      "told apart by TERM=xterm-256color or COLORTERM=truecolor. " \
      "--dump-terminal-info prints everything the game found."
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

      wanted = room && Screen.info? columns
      @info_panel.hidden = !wanted
      @gutter.hidden = !wanted
      @info_panel.width = Layout::Sizing.fixed(Screen.info_width columns)
      @log_size = Screen.log_height rows
      @log.height = Layout::Sizing.fixed(@log_size)

      # The engine does not hold a scroll to the content it finds, and a
      # resize changes both. The top is always in range.
      @info.scroll_y = 0
      @rows = rows
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
    # `TermBuf::Widgets::Pager` goes here. A banner already up stays up, and
    # it stays above whatever this puts in.
    def show_log(widget : Widgets::Widget) : Nil
      found = @banner
      @log.clear
      @log.add found if found
      @log.add widget
    end

    # Puts a one row banner above the log. Answers the label it wrote in.
    #
    # The caller writes the text. This decides where the row is and how wide
    # it is.
    def show_banner : Widgets::Label
      found = @banner
      return found if found

      made = Widgets::Label.new "",
        wrap: Layout::Wrap::None,
        ellipsis: BANNER_ELLIPSIS
      made.style = Palette::STRONG

      @banner = made

      held = @log.children.dup
      @log.clear
      @log.add made
      held.each { |child| @log.add child }
      made
    end

    # How many rows the message log has for its lines, on the screen `#fit`
    # was last given.
    #
    # A banner takes one of them.
    def log_rows : Int32
      @banner ? @log_size - 1 : @log_size
    end

    # Makes the log pane *rows* rows tall. The map gives up the rows, or
    # takes them back. `#fit` puts it back to `.log_height`.
    def grow_log(rows : Int32) : Nil
      @log_size = rows
      @log.height = Layout::Sizing.fixed(rows)
    end

    # How wide the log pane's text is on a screen of *columns*.
    #
    # The pane runs the width of the map. Its padding takes one column on
    # the left, and the scrollbar takes one on the right.
    def self.log_width(columns : Int32) : Int32
      beside = info?(columns) ? info_width(columns) + 1 : 0
      Math.max columns - beside - 2, 0
    end

    # Pins *pinned* at the top of the info panel and stacks *sections* under
    # it, in the order given. Takes out whatever was there.
    #
    # The vitals of `Ui::CharacterPane` are what is pinned. They are what a
    # person reads every turn, so they never scroll away.
    def show_info(pinned : Widgets::Widget, sections : Enumerable) : Nil
      @pinned.clear
      @pinned.add pinned
      @info.clear
      sections.each { |section| @info.add section }
    end

    # Whether the info panel is being shown.
    def info? : Bool
      !@info_panel.hidden?
    end

    # :ditto:
    def sidebar? : Bool
      info?
    end

    # How many rows the map pane gets on a screen of *rows*. The rule and the
    # log take the rest.
    def self.map_rows(rows : Int32) : Int32
      Math.max rows - 1 - log_height(rows), 0
    end
  end
end
