require "../../crystal-roguelike"

module Roguelike::Ui
  # The debug console, drawn over the game.
  #
  # A box with what the commands have written in it and a line to type on.
  # `Debug::Console` holds the commands and everything they do. This class
  # holds no rule of its own: it takes what was typed, hands it over, and puts
  # what came back on the screen.
  #
  # Nothing builds one of these unless `--debug-console` was passed. The key
  # that opens it is bound in the same place, so a normal run has neither the
  # box nor the key.
  class ConsolePane < Widgets::Overlay
    # The key that closes the box. It is the key that opened it.
    #
    # A tilde cannot be typed into the line while this is bound. Nothing a
    # command takes has one in it.
    TOGGLE = "~"

    # What is drawn in the top edge of the box.
    TITLE = " debug console "

    # What sits in front of the line being typed.
    PROMPT = "> "

    # What the box says before any command has been run.
    OPENING = "Type help for the commands. Escape closes this."

    # The version and the commit, on the first line of the scrollback.
    #
    # A screenshot of the box then says which build it came from.
    # `Roguelike::BUILD` carries a "+" when the build had changes in it that
    # the commit does not.
    def self.stamp : String
      "version #{Roguelike::VERSION} build #{Roguelike::BUILD}"
    end

    # How many cells the box leaves clear to its left and to its right.
    COLUMN_MARGIN = 4

    # How many rows it leaves clear above and below itself.
    ROW_MARGIN = 2

    # The narrowest box, and the shortest.
    LEAST = {40, 8}

    # Rows of the box that are not scrollback: the two border edges and the
    # line being typed.
    CHROME_ROWS = 3

    # The commands, and what they have written.
    getter console : Debug::Console

    # The line being typed.
    getter field : Widgets::Field

    # The rows the scrollback is drawn on, oldest first.
    #
    # Every one of them is in the tree. `#fit_into` hides the ones the box has
    # no room for rather than taking them out of it.
    getter rows : Array(Widgets::Label)

    # The game the commands run against.
    property game : Game

    # What runs after a command, so the owner can redraw the floor.
    property on_command : Proc(Nil)? = nil

    # The most rows of scrollback a box can show.
    #
    # A taller terminal than this shows this many and keeps the rest in
    # `Debug::Console#lines`.
    MOST_ROWS = 60

    def initialize(@game : Game, z : Int32 = Z::DIALOG)
      @console = Debug::Console.new
      @rows = Array.new(MOST_ROWS) { Widgets::Label.new "", wrap: Layout::Wrap::None }

      history = Widgets::History.new
      @field = Widgets::Field.new(
        editor: Widgets::Editor.new,
        prompt: Widgets::Field::Prompt.new(PROMPT))
      @field.editor.history = history
      @field.completions = ->(request : Widgets::Completion::Request) do
        ConsolePane.completion request
      end

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @width = Layout::Sizing.fit min: LEAST[0]
      @height = Layout::Sizing.fit min: LEAST[1]
      @border = Widgets::Border.rounded title: TITLE
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      self.keymap = closing

      @rows.each { |row| add row }
      add @field

      @console.say ConsolePane.stamp
      @console.say OPENING
    end

    # Whether the box is up.
    def showing? : Bool
      open?
    end

    # Puts the box up on *app*.
    def show(app : Widgets::App) : Nil
      fit_into app.tree.screen
      redraw

      open app
    end

    # Takes the box down.
    def hide : Nil
      return unless open?

      close
    end

    # Puts it up if it is down, and down if it is up.
    def toggle(app : Widgets::App) : Nil
      open? ? hide : show app
    end

    # Sizes the box to *screen* and says how many rows of scrollback fit.
    #
    # The box is the screen less a margin on every side. A row the box has no
    # room for is hidden rather than taken out of the tree, so the next size
    # up needs no widget built.
    def fit_into(screen : Rect) : Nil
      width = Math.max screen.width - 2 * COLUMN_MARGIN, LEAST[0]
      height = Math.max screen.height - 2 * ROW_MARGIN, LEAST[1]

      self.width = Layout::Sizing.fixed width
      self.height = Layout::Sizing.fixed height

      room = Math.min Math.max(height - CHROME_ROWS, 1), MOST_ROWS
      @rows.each_with_index { |row, index| row.hidden = index >= room }
    end

    # Puts the tail of what the commands wrote on the rows.
    #
    # The newest line sits against the field. A box with more rows than there
    # are lines leaves the ones above it blank, so the line just typed does
    # not walk down the box as the scrollback fills.
    def redraw : Nil
      showing = @rows.reject &.hidden?
      lines = @console.lines.last showing.size
      blank = showing.size - lines.size

      showing.each_with_index do |row, index|
        row.text = index < blank ? "" : lines[index - blank]
      end
    end

    # The keyboard lands on the line being typed.
    def focusable? : Bool
      false
    end

    # Runs *line* and shows what it wrote.
    def run(line : String) : Nil
      @console.run line, @game
      redraw
      @on_command.try &.call
    end

    # What the field says, and what `TOGGLE` says.
    #
    # `Escape` and `Ctrl+C` reach the field, which gives up on the line and
    # sends `Cancelled`. An empty line is how a person closes the box that
    # way, and a line with something on it is cleared by the first press and
    # closed by the second.
    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      case event
      when Widgets::Field::Accepted
        run event.text
        context.consume
      when Widgets::Field::Cancelled, Widgets::Field::EndOfInput
        hide
        context.consume
      end
    end

    # `TOGGLE` takes the box down.
    private def closing : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse(TOGGLE), "close the debug console",
          ->(_context : Widgets::Context) { hide; nil }
      end
    end

    # What *request* could be finishing, and what it replaces.
    #
    # A path after `save-copy` runs from the last space to the cursor, which
    # is longer than the field's idea of a word. Everything else replaces the
    # field's word.
    def self.completion(request : Widgets::Completion::Request) : Widgets::Completion::Result
      typed = request.text[0, request.cursor]? || ""
      start = typed.rindex(' ').try &.+(1)
      words = typed.split

      if start && words.first?.try(&.downcase) == "save-copy"
        return Widgets::Completion::Result.new paths(typed[start..]), start...request.cursor
      end

      Widgets::Completion::Result.new completions(request)
    end

    # The files and directories whose paths start with *typed*, from the
    # working directory. A directory ends in a slash. A hidden one is offered
    # only when *typed* names a dot.
    def self.paths(typed : String) : Array(String)
      cut = typed.rindex('/').try(&.+ 1) || 0
      above = typed[0, cut]
      begun = typed[cut..]
      where = above.empty? ? "." : above

      names = Dir.children(where).select do |name|
        name.starts_with?(begun) && (begun.starts_with?('.') || !name.starts_with?('.'))
      end

      names.sort.map do |name|
        Dir.exists?(File.join(where, name)) ? "#{above}#{name}/" : "#{above}#{name}"
      end
    rescue File::Error
      [] of String
    end

    # What *request* could be finishing.
    #
    # The first word of a line is a command. Everything after `spawn` is the
    # name of an item kind. `max-columns` and `max-rows` take `off`, and
    # `motion` takes `on` or `off`. Nothing else completes, because nothing
    # else is a word out of a list this class knows.
    def self.completions(request : Widgets::Completion::Request) : Array(String)
      before = request.text[0, request.range.begin]?.try(&.split) || [] of String
      return Debug::Console::TABLE.map(&.name).select &.starts_with?(request.word) if before.empty?

      case before.first.downcase
      when "spawn"
        ItemKind.values.map(&.label).select &.starts_with?(request.word)
      when "max-columns", "max-rows"
        ["off"].select &.starts_with?(request.word)
      when "motion"
        %w[on off].select &.starts_with?(request.word)
      else
        [] of String
      end
    end
  end
end
