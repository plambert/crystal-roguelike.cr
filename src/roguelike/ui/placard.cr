require "../../crystal-roguelike"

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

    @named_choices = [] of Widgets::Prompt::Choice
    @choice_index : Int32 = 0
    private property named_lines : Array(String) = [] of String

    # What runs when a key answers. The argument is the key, or `nil` when
    # the person pressed `Escape`.
    property on_answer : Proc(Char?, Nil)? = nil

    # What the offered keys are drawn in.
    property keys_style : Style = Style::DEFAULT.bold

    private getter instructions : Widgets::Label

    def initialize(z : Int32 = Widgets::Overlay::Z::DIALOG)
      @rows = Array.new(MOST_LINES) do
        Widgets::Label.new "", wrap: Layout::Wrap::None
      end

      @offered = Widgets::Label.new ""
      @offered.style = @keys_style
      @instructions = Widgets::Label.new ""
      @instructions.hidden = true

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 2, 0, 2
      @width = Layout::Sizing.fit min: LEAST[0]
      @height = Layout::Sizing.fit min: LEAST[1]
      @border = Widgets::Border.rounded
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      @rows.each { |row| add row }
      add @instructions, @offered
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
      @named_choices.clear
      @named_lines.clear
      @instructions.text = ""
      @instructions.hidden = true
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

    # Shows selectable named outcomes, answering with each choice's existing
    # character value. Escape takes the safe default.
    def show_named(app : Widgets::App, title : String, lines : Array(String),
                   choices : Enumerable(Widgets::Prompt::Choice), default : Char,
                   footer : String = "") : Nil
      @named_choices = choices.to_a
      raise ArgumentError.new "a placard needs at least one choice" if @named_choices.empty?
      unless @named_choices.any? { |choice| choice.key == default && choice.enabled }
        raise ArgumentError.new "default #{default.inspect} is not an enabled choice"
      end

      @heading = title
      @keys = @named_choices.map(&.key).join
      @default = default
      @choice_index = @named_choices.index { |choice| choice.key == default } || 0
      @named_lines = lines.dup
      self.border = Widgets::Border.rounded title: " #{title} "
      self.keymap = named_answers
      @instructions.text = footer
      @instructions.hidden = footer.empty?
      @offered.text = offering
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

      unless @named_choices.empty?
        line_limit = Math.max screen.height - 8, 1
        lines = if @named_lines.size > line_limit
                  shown = @named_lines.first(line_limit - 1)
                  shown << "… #{@named_lines.size - shown.size} more lines omitted"
                else
                  @named_lines.dup
                end
        say lines
      end

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
      return @named_choices.map_with_index do |choice, index|
        index == @choice_index ? "[ #{choice.label} ]" : choice.label
      end.join("  ") unless @named_choices.empty?

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

    private def named_answers : Widgets::Bindings
      map = Widgets::Bindings.new
      navigation = Widgets::Navigation.selectable
      navigation.previous_row.each do |key|
        map.bind key, "the choice before", ->(_context : Widgets::Context) { move_choice(-1); nil }
      end
      navigation.next_row.each do |key|
        map.bind key, "the choice after", ->(_context : Widgets::Context) { move_choice(1); nil }
      end
      navigation.activate.each do |key|
        map.bind key, "choose the highlighted outcome",
          ->(_context : Widgets::Context) { choose_highlighted; nil }
      end
      map.bind TermBuf::Key.parse("Escape"), "choose the safe outcome",
        ->(_context : Widgets::Context) { finish @default; nil }
      map
    end

    private def move_choice(step : Int32) : Nil
      index = @choice_index + step
      while index >= 0 && index < @named_choices.size
        if @named_choices[index].enabled
          @choice_index = index
          update_named_offering "W/S · f choose · Esc=Quit"
          invalidate_layout
          return
        end
        index += step
      end
    end

    private def choose_highlighted : Nil
      choice = @named_choices[@choice_index]?
      finish choice.key if choice && choice.enabled
    end

    private def update_named_offering(footer : String) : Nil
      @instructions.text = footer
      @instructions.hidden = footer.empty?
      @offered.text = offering
    end

    # Takes the box down. Runs `#on_answer` with *key*.
    #
    # The keymap goes with it. A closed box that kept its bindings would
    # answer again on the next press of the same key, before the next frame
    # rebuilt the focus ring.
    private def finish(key : Char?) : Nil
      @keys = ""
      @default = nil
      @named_choices.clear
      @named_lines.clear
      @instructions.hidden = true
      self.keymap = nil

      close

      @on_answer.try &.call(key)
    end
  end
end
