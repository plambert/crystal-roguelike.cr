require "../../crystal-roguelike"

module Roguelike::Ui
  # The color theme editor, which "Color theme" on the options screen
  # opens.
  #
  # It is a second modal overlay over the options screen, with a border
  # titled `Color theme`. A preview sits at the top, drawn in the theme as it
  # stands, and a status line under it says what the last action did. Under
  # those is a `Widgets::Form`. Its "Share" section copies the theme to the
  # clipboard, saves it as a named file in `themes/`, and takes a pasted
  # theme. After it come the colors from `Theme::ENTRIES`, one section per
  # group and one color row per entry. `Enter` on a color row opens the
  # picker.
  #
  # Every change applies as it is made. The editor sets the color on
  # `Theme.current`, writes `theme.json`, rebuilds the palette, and runs
  # `#on_change`, which `Play` points at `Play#retheme`. `Escape` closes the
  # editor and leaves the options screen showing.
  class ThemeEditor < Widgets::Overlay
    # What the border says.
    TITLE = "Color theme"

    # The key of the row that puts every color back.
    RESET_KEY = "reset"

    # The prefix of the action row that resets one color.
    RESET_COLOR_PREFIX = "reset-color-"

    # What that row says.
    RESET_LABEL = "Reset every color"

    # What is asked before every color goes back.
    QUESTION = "Put every color back?"

    # The key of the row that copies the theme to the clipboard.
    COPY_KEY = "copy"

    # The key of the row holding the name the theme is saved under.
    NAME_KEY = "save-name"

    # The key of the row that saves the theme.
    SAVE_KEY = "save"

    # The key of the row a theme is pasted into.
    PASTE_KEY = "paste"

    # The name a theme with none is saved under.
    UNNAMED = "My theme"

    # Cells left clear to the left and right of the box.
    COLUMN_MARGIN = 2

    # Rows left clear above and below it.
    ROW_MARGIN = 1

    # The widest the box grows.
    WIDTH = 72

    # The smallest the box is, whatever the screen.
    LEAST = {30, 10}

    # A few things drawn in the theme as it stands: map glyphs on the map's
    # ground, an item line, and a message line.
    class Preview < Widgets::Widget
      # The squares drawn on the first row.
      TERRAIN = [Terrain::Granite, Terrain::StoneFloor, Terrain::ClosedDoor,
                 Terrain::StoneFloor, Terrain::StairsDown]

      # The creatures drawn after the character.
      KINDS = [Kind::GoblinScout, Kind::Orc, Kind::BlueSlime]

      # The items drawn after the creatures.
      CLASSES = [ItemClass::Potion, ItemClass::Scroll, ItemClass::Treasure]

      # How many rows it takes.
      ROWS = 3

      def initialize
        @width = Layout::Sizing.grow
        @height = Layout::Sizing.fixed ROWS
      end

      # The glyphs of the first row, in order.
      def self.looks : Array(Look)
        looks = TERRAIN.map { |terrain| Palette[terrain] }
        looks << Palette.player
        KINDS.each { |kind| looks << Palette[kind] }
        CLASSES.each { |kind| looks << Palette.items[kind] }
        looks
      end

      # The pieces of the item row and the message row, each with its style.
      def self.lines : Array(Array({String, Style}))
        [
          [{"a dagger", Palette.weapon}, {", ", Palette.plain}, {"a scroll", Palette.scroll},
           {", ", Palette.plain}, {"12 gold", Palette.coin}],
          [{"You hit the orc. ", Palette.plain}, {"The orc dies.", Palette.message_new}],
        ]
      end

      def draw(view : View) : Nil
        return if view.height <= 0

        ground = Palette.ground_style
        view.fill Rect.new(0, 0, view.width, 1), ' ', ground
        Preview.looks.each_with_index do |look, index|
          column = 1 + 2 * index
          break if column >= view.width

          view.write_char column, 0, look.glyph, look.style.bg(Palette.ground)
        end

        Preview.lines.each_with_index(1) do |pieces, row|
          break if row >= view.height

          column = 0
          pieces.each do |text, style|
            view.write column, row, text, style
            column += text.size
          end
        end
      end
    end

    # The state directory the theme is written under.
    property root : Path

    # Runs after each change, once the palette is rebuilt.
    property on_change : Proc(Nil)? = nil

    # Runs after the editor closes.
    property on_close : Proc(Nil)? = nil

    # Asks a yes or no question and hands the key pressed to the proc.
    # `Play` points it at its own prompt. With none set, the question is
    # answered yes.
    property confirm : Proc(String, Proc(Char?, Nil), Nil)? = nil

    # How many colors the picker offers.
    property depth : Widgets::Depth = Widgets::Depth::TrueColor

    # The scheme used by this editor's form navigation.
    property control_scheme : Options::ControlScheme = Options::ControlScheme::Traditional

    def modern_controls? : Bool
      @control_scheme.modern?
    end

    # The form showing, rebuilt each time the editor opens.
    getter form : Widgets::Form

    # What the theme looks like, above the form.
    getter preview : Preview

    # The list of keys `?` and `F1` show over the editor.
    getter help : Help

    # What the last action did, under the preview. Hidden while empty.
    getter status : Widgets::Label

    # The application the editor is up on.
    @app : Widgets::App? = nil

    def initialize(@root : Path = Submit.root, z : Int32 = Widgets::Overlay::Z::DIALOG - 5)
      @preview = Preview.new
      @status = Widgets::Label.new
      @status.hidden = true
      @status.width = Layout::Sizing.grow
      @status.height = Layout::Sizing.fit min: 1
      @form = ThemeEditor.form_for Theme.current, @depth
      @help = Help.new

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @gap = 1
      @padding = Layout::Padding.new 0, 1, 0, 1
      @border = Widgets::Border.rounded title: " #{TITLE} "
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z
      add @preview, @status, @form
    end

    # Whether the editor is up.
    def showing? : Bool
      open?
    end

    # Puts the editor up on *app*, showing `Theme.current`.
    def show(app : Widgets::App) : Nil
      @app = app
      tell ""
      remove @form
      @form = ThemeEditor.form_for Theme.current, @depth, modern_controls?, ThemeEditor.save_name
      @form.attach app
      add @form

      @help.sections = [Keys.theme_editor(self, app)]
      self.keymap = @help.sections.first.bindings
      fit_into app.tree.screen
      open app
    end

    # The form for *theme*: the share section, a section for each group in
    # `Theme::ENTRIES` with a color row for each entry, and the reset row at
    # the end. Each picker offers *depth* colors. The name row starts at
    # *name*.
    def self.form_for(theme : Theme, depth : Widgets::Depth,
                      modern : Bool = false, name : String = UNNAMED) : Widgets::Form
      form = Widgets::Form.new actions: false, depth: depth, height: Layout::Sizing.fit

      form.section "Share" do |section|
        section.action COPY_KEY, "Copy theme", "to the clipboard"
        section.text NAME_KEY, "Save as", name
        section.action SAVE_KEY, "Save theme", "to a file"
        section.text PASTE_KEY, "Paste theme", "", placeholder: "paste JSON here"
      end

      Theme::ENTRIES.each do |entry|
        form.section entry.group do |section|
          section.color entry.key, entry.label, theme[entry.key]
          if modern
            section.action reset_color_key(entry.key), "Reset #{entry.label}"
          end
        end
      end

      form.section "Reset" do |section|
        section.action RESET_KEY, RESET_LABEL
      end

      form
    end

    # Sizes the box for *screen*. The rows scroll in what is left.
    def fit_into(screen : Rect) : Nil
      widest = (screen.width - 2 * COLUMN_MARGIN).clamp LEAST[0], WIDTH
      tallest = Math.max screen.height - 2 * ROW_MARGIN, LEAST[1]
      self.width = Layout::Sizing.fixed widest
      self.height = Layout::Sizing.fit min: LEAST[1], max: tallest
    end

    # Sizes the box again for a screen that has changed size.
    def refit(screen : Rect) : Nil
      fit_into screen if showing?
    end

    # Takes the editor down and gives the keyboard back to the options
    # screen.
    def dismiss : Nil
      return unless open?

      @help.close_with nil if @help.open?
      self.keymap = nil
      close
      @on_close.try &.call
    end

    # Puts the list of keys up over the editor.
    def show_help(app : Widgets::App) : Nil
      @help.screen_rows = app.tree.screen.height
      @help.open app
    end

    # The row with the keyboard, or `nil` when no row has it.
    def focused_row : Widgets::Form::Row?
      @form.focused_row
    end

    # Whether a row's picker is up.
    def picking? : Bool
      @form.rows.any? { |row| row.is_a?(Widgets::Form::ColorRow) && row.open? }
    end

    # Moves the keyboard *step* rows along.
    def step(step : Int32, context : Widgets::Context) : Nil
      @form.step_row step, context unless @form.type context
    end

    # Activates the focused row, while leaving typed color values to the form.
    def activate(context : Widgets::Context) : Nil
      return if @form.type context

      row = focused_row
      return unless row && row.enabled?

      if row.enter
        context.consume
      else
        row.activate
        context.consume
      end
    end

    # Moves the keyboard to the first row of the section *step* sections
    # along.
    def leap(step : Int32, context : Widgets::Context) : Nil
      return if @form.type context

      sections = @form.sections.reject &.rows.empty?
      current = focused_row
      at = sections.index { |section| current && section.rows.includes?(current) } || 0
      wanted = sections[(at + step).clamp(0, sections.size - 1)]?
      row = wanted.try &.rows.find(&.focusable?)
      target = row.try &.target
      return unless row && target

      current.try &.leave
      context.focus.focus target
      @form.bring row
    end

    # Puts the color of the row with the keyboard back to its default.
    def reset_row : Nil
      row = focused_row
      return unless row.is_a? Widgets::Form::ColorRow

      reset_color row.key
    end

    private def reset_color(key : String) : Nil
      row = @form.row(key).as?(Widgets::Form::ColorRow)
      return unless row

      color = Theme::DEFAULT[key]
      return if color == Theme.current[key]

      row.value = color
      apply Theme.current.with(key, color)
    end

    # The name the theme in use is saved under unless another is typed.
    def self.save_name : String
      Theme.current_name || UNNAMED
    end

    # Says *text* on the status line. Empty text hides the line.
    def tell(text : String) : Nil
      @status.text = text
      @status.hidden = text.empty?
    end

    # Puts the theme in use on the clipboard as JSON, under the name in the
    # name row.
    def copy : Nil
      copier = @app.try &.copy
      return tell "This terminal gives the game no clipboard. Save writes a file instead." unless copier

      name = typed_name || ThemeEditor.save_name
      copier.call Theme.current.to_named_json(name)
      tell "Copied #{name} to the clipboard."
    end

    # Saves the theme in use under the name in the name row.
    def save : Nil
      name = typed_name
      return tell "Type a name to save the theme under." unless name

      path = ThemeLibrary.save @root, name, Theme.current
      Theme.current_name = name
      Theme.current.write @root, name
      tell "Saved #{name} as #{path}."
    rescue error : File::Error | ArgumentError
      tell "The theme was not saved: #{error.message}"
    end

    # Reads *text* as a theme and draws with it. A theme that names itself
    # is saved under that name too. Text that does not read changes nothing.
    def import(text : String) : Nil
      theme, name = Theme.parse text
    rescue error : Theme::Unreadable
      tell "#{error.message} Nothing was changed."
    else
      use theme, name
      unless name
        return tell "Using the pasted theme. Type a name and save it to keep it."
      end

      begin
        ThemeLibrary.save @root, name, theme
        tell "Using #{name}, saved in the themes folder."
      rescue error : File::Error | ArgumentError
        tell "Using #{name}. It was not saved: #{error.message}"
      end
    end

    # Draws with *theme*, called *name*, and shows its colors in the rows.
    def use(theme : Theme, name : String?) : Nil
      Theme.current_name = name
      @form.rows.each do |row|
        row.value = theme[row.key] if row.is_a? Widgets::Form::ColorRow
      end
      @form[NAME_KEY] = ThemeEditor.save_name
      apply theme
    end

    # The name in the name row, or `nil` when it cannot name a file.
    private def typed_name : String?
      typed = @form[NAME_KEY].as?(String).try &.strip
      typed if typed && ThemeLibrary.file_name(typed)
    end

    # Asks first, and on yes puts every color back to its default.
    def reset_all : Nil
      asked = @confirm
      return reset_everything unless asked

      asked.call QUESTION, ->(key : Char?) do
        reset_everything if key == 'y'
        nil
      end
    end

    # The keyboard goes to the first row.
    protected def initial_focus : Widgets::Widget?
      @form.reachable.first?.try &.target
    end

    # Takes each change and each press the form reports, a line handed
    # over in a text row, and a paste into the paste row.
    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      case event
      when TermBuf::Events::Paste
        pasted event
      when Widgets::Field::Accepted
        accepted event
      when Widgets::Form::Changed
        context.consume
        color = event.value
        apply Theme.current.with(event.key, ThemeEditor.stored(color)) if color.is_a? TermBuf::Color
        return
      when Widgets::Form::Activated
        if activated event.key
          context.consume
          return
        end
      end

      super
    end

    # Reads a paste into the paste row as a theme. The paste is left
    # unclaimed, so a paste notice still hears that it is over.
    private def pasted(event : TermBuf::Events::Paste) : Nil
      return unless focused_row.try(&.key) == PASTE_KEY

      @form[PASTE_KEY] = ""
      import event.text
    end

    # Saves on `Enter` in the name row, and reads the paste row as a theme
    # on `Enter` there.
    private def accepted(event : Widgets::Field::Accepted) : Nil
      case focused_row.try &.key
      when NAME_KEY
        save
      when PASTE_KEY
        text = event.text.presence || @form[PASTE_KEY].as?(String) || ""
        @form[PASTE_KEY] = ""
        import text unless text.blank?
      end
    end

    # Does what the action row filed under *key* does, and answers whether
    # it was one of the editor's.
    private def activated(key : String) : Bool
      case key
      when COPY_KEY  then copy
      when SAVE_KEY  then save
      when RESET_KEY then reset_all
      when .starts_with?(RESET_COLOR_PREFIX)
        reset_color key[RESET_COLOR_PREFIX.size..]
      else
        return false
      end
      true
    end

    private def self.reset_color_key(key : String) : String
      "#{RESET_COLOR_PREFIX}#{key}"
    end

    # *color* as the theme keeps it, which is always `Rgb`. A palette index
    # the picker chose at 256 colors becomes that index's own channels.
    def self.stored(color : TermBuf::Color) : TermBuf::Color
      return color if color.rgb?

      red, green, blue = color.channels
      TermBuf::Color.rgb red, green, blue
    end

    # Draws with *theme* from now on and writes it.
    private def apply(theme : Theme) : Nil
      Theme.current = theme
      theme.write @root, Theme.current_name
      Palette.rebuild
      @on_change.try &.call
    end

    private def reset_everything : Nil
      use Theme::DEFAULT, nil
    end
  end
end
