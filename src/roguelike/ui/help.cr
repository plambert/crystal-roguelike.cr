require "../ui"

module Roguelike
  module Ui
    # The help screen, which `?` and `F1` open.
    #
    # It shows the run's seed and every key that works, in groups by what the
    # keys are for: the application's own, moving, time, doors and stairs, and
    # so on. The groups are `Keys::Section`s, and each row's key is read from
    # the binding itself, so a key bound somewhere else shows where it is now
    # bound rather than where it used to be.
    #
    # The movement keys are drawn around the character with an arrow for
    # each, which reads faster than eight rows of "move north-west". The
    # arrows are the plain text ones at U+2190 to U+2199, one cell each.
    #
    # The dialog takes the height its rows need, up to `MARGIN` cells from the
    # top and the bottom of the screen. Past that it scrolls, and a scrollbar
    # stands beside the rows while there is anything to scroll. The arrows
    # scroll it a row, the page keys a window, and `Space` half a window down.
    class Help < Widgets::Dialog
      # Cells left clear above and below the dialog when it is at its tallest.
      MARGIN = 3

      # Rows the border, the gap and the Close button take.
      CHROME = 4

      # Cells between the keys and what they do.
      GAP = 2

      # What is written beside the middle row of the diagram.
      MOVING = "move, or attack what is there"

      # One line of the list.
      record Row, keys : String, description : String = "", header : Bool = false

      # A blank line between two groups.
      SPACER = Row.new ""

      # The rows, drawn through a list that measures them.
      #
      # Nothing in the list is chosen, so the keys move the window rather
      # than a selection. Each stops at the end it reaches.
      class List < Widgets::VirtualList(Help::Row)
        # How wide the keys column is, which the descriptions line up against.
        getter keys_width : Int32 = 0

        # The most rows shown at once. Anything past that scrolls.
        property most : Int32 = 14

        # The inherited constructor names its argument `Rows(T)`, and that
        # name is looked up from here, outside the shard's namespace. This
        # one names the type in full and hands on.
        def initialize(rows : Widgets::Rows(Help::Row), width : Widgets::Layout::Sizing,
                       height : Widgets::Layout::Sizing)
          super rows, width, height
          @keymap = List.scrolling self
        end

        # The keys that move the window.
        def self.scrolling(list : List) : Widgets::Bindings
          Widgets::Bindings.build do |map|
            map.bind TermBuf::Key.parse("Up"), "a row back", ->(_context : Widgets::Context) { list.scroll_by dy: -1 }
            map.bind TermBuf::Key.parse("Down"), "a row on", ->(_context : Widgets::Context) { list.scroll_by dy: 1 }
            map.bind TermBuf::Key.parse("PageUp"), "a window back", ->(_context : Widgets::Context) { list.scroll_by dy: -list.page }
            map.bind TermBuf::Key.parse("PageDown"), "a window on", ->(_context : Widgets::Context) { list.scroll_by dy: list.page }
            map.bind TermBuf::Key.parse("Space"), "half a window on", ->(_context : Widgets::Context) { list.scroll_by dy: list.half }
            map.bind TermBuf::Key.parse("Home"), "the first row", ->(_context : Widgets::Context) { list.scroll_to_row 0 }
            map.bind TermBuf::Key.parse("End"), "the last row", ->(_context : Widgets::Context) { list.scroll_to_row list.rows.size }
          end
        end

        # How many rows `Space` moves, which is half a window and at least one.
        def half : Int32
          Math.max page // 2, 1
        end

        def intrinsic_width(policy : TermBuf::Unicode::WidthPolicy) : Widgets::Layout::Intrinsic
          @keys_width = 0
          widest = 0

          rows.size.times do |index|
            row = rows.row index
            width = TermBuf::Unicode.string_width row.keys, policy
            if row.header
              widest = Math.max widest, width
            else
              @keys_width = Math.max @keys_width, width
            end
          end

          rows.size.times do |index|
            row = rows.row index
            next if row.header || row.description.empty?

            widest = Math.max widest,
              @keys_width + GAP + TermBuf::Unicode.string_width(row.description, policy)
          end

          widest = Math.max widest, @keys_width
          Widgets::Layout::Intrinsic.new Math.min(widest, 8), widest
        end

        def height_for_width(width : Int32, policy : TermBuf::Unicode::WidthPolicy) : Int32
          Math.max Math.min(rows.size, @most), 1
        end
      end

      # The run's seed.
      property seed : UInt64

      # The groups of keys, in the order they are shown.
      property sections : Array(Keys::Section) = [] of Keys::Section

      # How many rows the screen has. The owner sets it, and again on a resize.
      property screen_rows : Int32 = 24

      # The rows as they stand, rebuilt every time the dialog opens.
      getter rows = [] of Row

      # The list the rows are drawn through.
      getter list : List

      # The bar beside the list, hidden while every row fits.
      getter bar : Widgets::Scrollbar

      # What a group heading is drawn in.
      property header_style : TermBuf::Style = TermBuf::Style::DEFAULT.bold

      # What a key is drawn in.
      property keys_style : TermBuf::Style = TermBuf::Style::DEFAULT

      # What the description of a key is drawn in.
      property description_style : TermBuf::Style = TermBuf::Style::DEFAULT.faint

      def initialize(@seed : UInt64 = 0)
        @list = List.new Widgets::Rows.of(@rows), Widgets::Layout::Sizing.fit,
          Widgets::Layout::Sizing.fit(min: 1)
        @bar = Widgets::Scrollbar.new @list
        @bar.hidden = true

        body = Widgets::Panel.new direction: Widgets::Layout::Direction::Row,
          gap: 1, width: Widgets::Layout::Sizing.fit, height: Widgets::Layout::Sizing.fit
        body.add @list
        body.add @bar

        super "keys", body: body, actions: {"Close"}
      end

      # Builds the rows from the sections and sizes the list to the screen.
      protected def prepare(app : Widgets::App) : Nil
        rebuild
        @list.most = Math.max screen_rows - 2 * MARGIN - CHROME, 1
        @bar.hidden = @rows.size <= @list.most

        @list.on_draw = ->(view : TermBuf::View, _index : Int32, row : Row, _chosen : Bool, _focused : Bool) do
          draw_row view, row
        end
        @list.rows = Widgets::Rows.of @rows
        @list.scroll_to_row 0
      end

      # The keyboard goes to the list, so that its keys scroll it.
      protected def initial_focus : Widgets::Widget?
        @list
      end

      # Fills `rows` from `sections`. The seed goes under the first heading.
      def rebuild : Nil
        @rows.clear

        @sections.each_with_index do |section, index|
          @rows << SPACER unless index.zero?
          @rows << Row.new(section.title, header: true)
          @rows << Row.new("seed", @seed.to_s) if index.zero?

          moves = Keys.directions section.bindings
          if moves.empty?
            section.bindings.bindings.each do |binding|
              @rows << Row.new(binding.to_s, binding.description)
            end
          else
            Help.diagram(moves).each_with_index do |line, row|
              @rows << Row.new(line, row == 2 ? MOVING : "")
            end
          end
        end
      end

      # The movement keys around the character, as five lines.
      #
      # Each arrow points from `@` toward the key that moves that way. A key
      # with a longer name than one character widens every cell to match, so
      # the columns stay aligned.
      def self.diagram(moves : Hash(Direction, String)) : Array(String)
        cell = Math.max 1, moves.values.max_of?(&.size) || 1
        at = ->(direction : Direction) { (moves[direction]? || "").center cell }
        mid = ->(glyph : String) { glyph.center cell }

        [
          [at.call(Direction::NorthWest), mid.call(" "), at.call(Direction::North), mid.call(" "), at.call(Direction::NorthEast)],
          [mid.call(" "), mid.call("↖"), mid.call("↑"), mid.call("↗"), mid.call(" ")],
          [at.call(Direction::West), mid.call("←"), mid.call("@"), mid.call("→"), at.call(Direction::East)],
          [mid.call(" "), mid.call("↙"), mid.call("↓"), mid.call("↘"), mid.call(" ")],
          [at.call(Direction::SouthWest), mid.call(" "), at.call(Direction::South), mid.call(" "), at.call(Direction::SouthEast)],
        ].map(&.join.rstrip)
      end

      # Draws one row: a heading, a key and what it does, or nothing.
      private def draw_row(view : TermBuf::View, row : Row) : Nil
        return if view.width <= 0

        if row.header
          view.write 0, 0, TermBuf::Unicode.truncate(row.keys, view.width, view.policy), @header_style
          return
        end

        view.write 0, 0, TermBuf::Unicode.truncate(row.keys, view.width, view.policy), @keys_style
        spot = @list.keys_width + GAP
        return if spot >= view.width || row.description.empty?

        view.write spot, 0,
          TermBuf::Unicode.truncate(row.description, view.width - spot, view.policy),
          @description_style
      end
    end
  end
end
