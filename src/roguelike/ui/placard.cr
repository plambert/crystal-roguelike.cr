module Roguelike::Ui
  # A box of lines answered by one keystroke.
  #
  # `Widgets::Prompt` asks a question on one row. A title screen and an end
  # screen are several rows of text with the same one-keystroke answer under
  # them, so this holds a column of lines rather than a question.
  #
  # The lines are set before it goes up and do not change while it is up.
  # Nothing in it can be scrolled and nothing in it can be typed into. A
  # person reads it and presses one key.
  class Placard < Widgets::Overlay
    # How many cells it leaves clear to its left and to its right.
    COLUMN_MARGIN = 4

    # How many rows it leaves clear above and below itself.
    ROW_MARGIN = 1

    # The narrowest box, and the shortest.
    LEAST = {32, 5}

    # The most lines one holds. A longer list is cut and the last line says
    # how much was left out.
    MOST_LINES = 40

    # The rows the lines are drawn on, top first.
    #
    # Every one is in the tree. `#say` hides the ones it has no line for
    # rather than taking them out of it.
    getter rows : Array(Widgets::Label)

    # The row the offered keys are drawn on.
    getter offered : Widgets::Label

    # What it is headed with. Empty while nothing is up.
    getter heading : String = ""

    # The keys that answer it, in the order it offers them.
    getter keys : String = ""

    # The key `Enter` answers with. `nil` when `Enter` answers nothing.
    getter default : Char? = nil

    # What runs when a key answers. The argument is the key, or `nil` when
    # the person pressed `Escape`.
    property on_answer : Proc(Char?, Nil)? = nil

    # What the offered keys are drawn in.
    property keys_style : Style = Style::DEFAULT.bold

    def initialize(z : Int32 = Widgets::Overlay::Z::DIALOG)
      @rows = Array.new(MOST_LINES) do
        Widgets::Label.new "", wrap: Layout::Wrap::None
      end

      @offered = Widgets::Label.new ""
      @offered.style = @keys_style

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 2, 0, 2
      @width = Layout::Sizing.fit min: LEAST[0]
      @height = Layout::Sizing.fit min: LEAST[1]
      @border = Widgets::Border.rounded
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      @rows.each { |row| add row }
      add @offered
    end

    # The keyboard lands here. The box holds no control of its own, and focus
    # has to land somewhere inside the scope it pushed.
    def focusable? : Bool
      open?
    end

    # Whether the box is up.
    def showing? : Bool
      open?
    end

    # Puts *lines* up on *app* under *title*, answered by any of *keys*.
    #
    # *default* names the key `Enter` answers with. It has to be one of
    # *keys*. *footer* is the row under the lines, which says what the keys
    # do. The offered keys are drawn after it.
    def show(app : Widgets::App, title : String, lines : Array(String),
             keys : String, default : Char? = nil,
             footer : String = "") : Nil
      if default && !keys.includes? default
        raise ArgumentError.new "default #{default.inspect} is not one of #{keys.inspect}"
      end

      @heading = title
      @keys = keys
      @default = default

      self.border = Widgets::Border.rounded title: " #{title} "
      say lines
      @offered.text = footer.empty? ? offering : "#{footer}  #{offering}"
      self.keymap = answers
      fit_into app.tree.screen

      open app
    end

    # What is written on it now, top first.
    def lines : Array(String)
      @rows.reject(&.hidden?).map &.text
    end

    # Puts *lines* on the rows. Hides the rows it has no line for.
    #
    # A list longer than `MOST_LINES` is cut, and the last row says how many
    # were left out rather than leaving them off without a word.
    def say(lines : Array(String)) : Nil
      shown = lines
      if lines.size > MOST_LINES
        shown = lines.first(MOST_LINES - 1)
        shown << "and #{lines.size - shown.size} more"
      end

      @rows.each_with_index do |row, index|
        row.text = shown[index]? || ""
        row.hidden = index >= shown.size
      end
    end

    # Sizes the box to *screen*.
    #
    # It grows to fit its widest line and stops at the screen less a margin
    # on every side. A line wider than that is cut at the edge, because
    # `Layout::Wrap::None` is what keeps a list of items one to a row.
    def fit_into(screen : Rect) : Nil
      widest = Math.max screen.width - 2 * COLUMN_MARGIN, LEAST[0]
      tallest = Math.max screen.height - 2 * ROW_MARGIN, LEAST[1]

      self.width = Layout::Sizing.fit min: LEAST[0], max: widest
      self.height = Layout::Sizing.fit min: LEAST[1], max: tallest
    end

    # Takes the box down without an answer. Runs `#on_answer` with `nil`.
    def cancel : Nil
      return unless open?

      finish nil
    end

    # The keys as it offers them. The default key is upper case.
    #
    # `[Yn]` says that `y` is what `Enter` answers with, which is the
    # convention `Widgets::Prompt` follows as well.
    def offering : String
      chosen = @default
      return "[#{@keys}]" unless chosen

      "[#{@keys.gsub chosen, chosen.upcase}]"
    end

    # The bindings it answers.
    #
    # A key outside this set reaches the box and stops. It is modal, so
    # nothing behind it answers.
    private def answers : Widgets::Bindings
      map = Widgets::Bindings.new

      @keys.each_char do |key|
        map.bind TermBuf::Key.character(key), "answer #{key}",
          ->(_context : Widgets::Context) { finish key; nil }
      end

      map.bind TermBuf::Key.named(TermBuf::Key::Name::Escape),
        "leave it unanswered",
        ->(_context : Widgets::Context) { finish nil; nil }

      chosen = @default
      if chosen
        map.bind TermBuf::Key.named(TermBuf::Key::Name::Enter), "answer #{chosen}",
          ->(_context : Widgets::Context) { finish chosen; nil }
      end

      map
    end

    # Takes the box down. Runs `#on_answer` with *key*.
    #
    # The keymap goes with it. A closed box that kept its bindings would
    # answer again on the next press of the same key, before the next frame
    # rebuilt the focus ring.
    private def finish(key : Char?) : Nil
      @keys = ""
      @default = nil
      self.keymap = nil

      close

      @on_answer.try &.call(key)
    end
  end
end
