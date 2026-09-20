module Roguelike::Ui
  # Every message of the run, in a box over the game.
  #
  # The log pane is four rows. A turn that says more than four things pushes
  # the first of them off, and `Widgets::Pager` holds at a page boundary so
  # that nothing goes past unread. This is the other half of that: what was
  # read and then walked away from.
  #
  # The box holds a window over the lines and no copy of them beyond the
  # wrapping. It is opened with `HistoryPane::TOGGLE`, scrolled with the
  # arrows, the page keys and the wheel, and closed with `Escape`.
  class HistoryPane < Widgets::Overlay
    # The key that opens the box, and one of the keys that closes it.
    TOGGLE = "Ctrl+P"

    # What is drawn in the top edge of the box.
    TITLE = " messages "

    # What the box says when nothing has happened yet.
    EMPTY = "Nothing has happened yet."

    # How many cells the box leaves clear to its left and to its right.
    COLUMN_MARGIN = 6

    # How many rows it leaves clear above and below itself.
    ROW_MARGIN = 2

    # The narrowest box, and the shortest.
    LEAST = {40, 8}

    # The lines the box shows, wrapped to its width, oldest first.
    getter lines : Array(String) = [] of String

    # The window they are drawn through.
    getter list : Widgets::VirtualList(String)

    # Whether the window is still waiting to be put at the newest line.
    #
    # Where the window can sit depends on how many lines fit, and that is
    # not known until the box has been laid out. So the box asks for the
    # newest line and the next frame answers.
    @to_newest : Bool = false

    # How many cells wide the lines are drawn, as `#fit_into` last worked it
    # out.
    #
    # This is not read off the drawn rectangle. A box sized for a screen that
    # changed has not been laid out at the new size yet.
    getter room : Int32 = 0

    def initialize(z : Int32 = Z::DIALOG)
      @list = Widgets::VirtualList(String).new Widgets::Rows.of(@lines)

      # The keys are bound on the box rather than on the list. A list moves a
      # selection and brings it into view; this box scrolls, and where it
      # sits is the whole of what it holds.
      @list.keymap = nil
      @list.on_draw = ->(view : View, _index : Int32, line : String, _chosen : Bool, _lit : Bool) do
        view.write 0, 0, line
        nil
      end

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @width = Layout::Sizing.fixed LEAST[0]
      @height = Layout::Sizing.fixed LEAST[1]
      @border = Widgets::Border.rounded title: TITLE
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      self.keymap = scrolling

      add @list
    end

    # Whether the box is up.
    def showing? : Bool
      open?
    end

    # Puts *said* up on *app*, oldest first, showing the newest.
    #
    # The lines are wrapped here rather than cut, because a message longer
    # than the box is a message with its end missing.
    def show(app : Widgets::App, said : Array(String)) : Nil
      fit_into app.tree.screen

      @lines.clear
      said.each { |line| @lines.concat Widgets::Pager.wrap(line, @room) }
      @lines << EMPTY if @lines.empty?

      @to_newest = true
      open app
    end

    # Takes the box down.
    def hide : Nil
      return unless open?

      close
    end

    # Puts it up if it is down, and down if it is up.
    def toggle(app : Widgets::App, said : Array(String)) : Nil
      open? ? hide : show app, said
    end

    # Sizes the box to *screen*.
    #
    # The screen less a margin on every side. The lines are wrapped to what
    # is left inside the border and the padding, which `#room` answers.
    def fit_into(screen : Rect) : Nil
      width = Math.max screen.width - 2 * COLUMN_MARGIN, LEAST[0]
      height = Math.max screen.height - 2 * ROW_MARGIN, LEAST[1]

      self.width = Layout::Sizing.fixed width
      self.height = Layout::Sizing.fixed height
      @room = Math.max width - inset.horizontal, 1
    end

    # Puts the window at the newest line once there is a rectangle to work
    # it out from.
    #
    # A widget is drawn after it is laid out, and the box is laid out after
    # `#show` has put it in the tree. This is the first moment the list knows
    # how many lines it shows.
    #
    # The line is chosen rather than scrolled to. A list brings its chosen
    # row back into view whenever the window it is drawn in changes size, so
    # a box that scrolled without choosing would jump to the top the next
    # time the terminal was resized.
    def draw(view : View) : Nil
      if @to_newest
        @to_newest = false
        @list.select @lines.size - 1
      end

      super
    end

    # The keyboard lands on the list, which the keys below scroll.
    def focusable? : Bool
      false
    end

    # How many lines a page key moves.
    def page : Int32
      @list.page
    end

    # Moves the window *lines* down. A negative number moves it back.
    def scroll_by(lines : Int32) : Nil
      @list.scroll_by 0, lines
    end

    # Puts the window at the oldest line, or at the newest.
    def scroll_to_end(newest : Bool) : Nil
      @list.select newest ? @lines.size - 1 : 0
    end

    # The keys the box answers.
    #
    # `less` and every roguelike after it. The arrows and `jk` move a line,
    # the page keys and the space bar move a window, and `Escape`, `q` and
    # the key that opened the box all close it.
    private def scrolling : Widgets::Bindings
      Widgets::Bindings.build do |map|
        {"Up", "k"}.each do |key|
          map.bind TermBuf::Key.parse(key), "a line back",
            ->(_context : Widgets::Context) { scroll_by -1; nil }
        end

        {"Down", "j"}.each do |key|
          map.bind TermBuf::Key.parse(key), "a line on",
            ->(_context : Widgets::Context) { scroll_by 1; nil }
        end

        {"PageUp", "Ctrl+B"}.each do |key|
          map.bind TermBuf::Key.parse(key), "a window back",
            ->(_context : Widgets::Context) { scroll_by -page; nil }
        end

        {"PageDown", "Ctrl+F", "Space"}.each do |key|
          map.bind TermBuf::Key.parse(key), "a window on",
            ->(_context : Widgets::Context) { scroll_by page; nil }
        end

        map.bind TermBuf::Key.parse("Home"), "the oldest message",
          ->(_context : Widgets::Context) { scroll_to_end false; nil }
        map.bind TermBuf::Key.parse("End"), "the newest message",
          ->(_context : Widgets::Context) { scroll_to_end true; nil }

        {"Escape", "q", TOGGLE}.each do |key|
          map.bind TermBuf::Key.parse(key), "close the messages",
            ->(_context : Widgets::Context) { hide; nil }
        end
      end
    end
  end
end
