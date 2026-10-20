require "../../crystal-roguelike"

module Roguelike::Ui
  # The options screen, which `o` on the title screen and `O` in play open.
  #
  # It is a modal overlay over the whole screen, with a border titled
  # `Options`, and it dims what is behind it. Inside is a `Widgets::Form`
  # built from `Options::SETTINGS`, one section per `Setting#section` in the
  # order the settings are listed.
  #
  # Every change applies as it is made. The screen sets the value on the
  # options, writes the file, and hands the options to `#on_change`, which
  # pushes them to the session. There is no OK and no Cancel. `Escape`
  # closes the screen and gives the keyboard back.
  #
  # Nothing here is game state. The screen spends no turn and writes nothing
  # to the replay log.
  class OptionsScreen < Widgets::Overlay
    # What the border says.
    TITLE = "Options"

    # Cells left clear to the left and right of the box.
    COLUMN_MARGIN = 2

    # Rows left clear above and below it.
    ROW_MARGIN = 1

    # The widest the box grows, which fits the longest help line.
    WIDTH = 72

    # The smallest the box is, whatever the screen.
    LEAST = {30, 8}

    # The key of the row that opens the theme editor.
    THEME_KEY = "theme"

    # What that row says. It is no wider than the widest label already on
    # the screen, so the labels keep their column.
    THEME_LABEL = "Color theme"

    # What its input column says.
    THEME_HINT = "Enter to edit"

    # The setting that row follows.
    DISPLAY_LAST = "bar_color"

    # The state directory the files are written under.
    property root : Path

    # Runs after each change, with the options as they now stand.
    property on_change : Proc(Options, Nil)? = nil

    # Runs after the screen closes.
    property on_close : Proc(Nil)? = nil

    # The form showing, rebuilt each time the screen opens.
    getter form : Widgets::Form

    # The options the form edits.
    getter options : Options

    # The list of keys `?` and `F1` show over the screen.
    getter help : Help

    # The color theme editor, which the "Color theme" row opens over
    # the screen.
    getter theme_editor : ThemeEditor

    def initialize(@root : Path = Submit.root, z : Int32 = Widgets::Overlay::Z::DIALOG - 10)
      @options = Options.new
      @form = OptionsScreen.form_for @options, Tester::ANONYMOUS
      @help = Help.new
      @theme_editor = ThemeEditor.new @root

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @border = Widgets::Border.rounded title: " #{TITLE} "
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z
      add @form
    end

    # Whether the screen is up.
    def showing? : Bool
      open?
    end

    # Puts the screen up on *app*, showing *options*.
    #
    # The tester name is read from the state directory, since it is kept in
    # `tester.json` rather than with the options.
    def show(app : Widgets::App, options : Options) : Nil
      @options = options
      remove @form
      @form = OptionsScreen.form_for options, Options.name(@root)
      @form.attach app
      add @form

      @theme_editor.root = @root
      @help.sections = [Keys.options_screen(self, app)]
      self.keymap = @help.sections.first.bindings
      fit_into app.tree.screen
      open app
    end

    # The form for *options*, a section for each heading in
    # `Options::SETTINGS`, with *name* in the tester's row. The row that
    # opens the theme editor ends the Display section.
    #
    # A key a flag set for this run carries a note naming the flag.
    def self.form_for(options : Options, name : String) : Widgets::Form
      form = Widgets::Form.new actions: false, height: Layout::Sizing.fit

      Options::SETTINGS.each do |setting|
        held = setting.key == "name" ? name : options[setting.key]

        form.section setting.section do |section|
          row setting, held, section
        end

        flag = options.flag setting.key
        form.note setting.key, "Set by #{flag} for this run" if flag

        if setting.key == DISPLAY_LAST
          form.section(setting.section).action THEME_KEY, THEME_LABEL, hint: THEME_HINT,
            help: "Choose the color of each thing the game draws"
        end
      end

      form
    end

    # Adds the row for *setting*, holding *held*, to *section*.
    private def self.row(setting : Options::Setting, held : Options::Value,
                         section : Widgets::Form::Section) : Nil
      key, label, help = setting.key, setting.label, setting.help

      case setting.kind
      in .toggle?
        section.toggle key, label, value: held == true, help: help
      in .choice?
        section.choice key, label, setting.choices, value: held.to_s, help: help
      in .number?
        range = setting.range || (0..100)
        section.number key, label, value: held.is_a?(Int32) ? held : range.begin,
          range: range, step: setting.step, help: help
      in .text?
        section.text key, label, value: held.to_s, help: help
      end
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
      @theme_editor.refit screen
    end

    # Puts the theme editor up over the screen.
    def show_theme_editor(app : Widgets::App) : Nil
      @theme_editor.show app
    end

    # Takes the screen down and gives the keyboard back.
    def dismiss : Nil
      return unless open?

      @theme_editor.dismiss
      @help.close_with nil if @help.open?
      self.keymap = nil
      close
      @on_close.try &.call
    end

    # Puts the list of keys up over the screen.
    def show_help(app : Widgets::App) : Nil
      @help.screen_rows = app.tree.screen.height
      @help.open app
    end

    # The row with the keyboard, or `nil` when no row has it.
    def focused_row : Widgets::Form::Row?
      @form.focused_row
    end

    # Hands the key being answered to the row with the keyboard when the row
    # takes it as text. Answers whether it did.
    def typed?(context : Widgets::Context) : Bool
      @form.type context
    end

    # Moves the keyboard *step* rows along.
    def step(step : Int32, context : Widgets::Context) : Nil
      @form.step_row step, context unless typed? context
    end

    # Takes the choice *step* places along, or steps a number.
    def turn(step : Int32, context : Widgets::Context) : Nil
      return if typed? context

      case row = focused_row
      when Widgets::Form::ChoiceRow then row.input.move step
      when Widgets::Form::NumberRow then row.input.step_by step
      end
    end

    # The keyboard goes to the first row.
    protected def initial_focus : Widgets::Widget?
      @form.reachable.first?.try &.target
    end

    # Takes each change the form reports.
    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      if event.is_a? Widgets::Form::Changed
        context.consume
        changed event.key, event.value
        return
      end

      if event.is_a?(Widgets::Form::Activated) && event.key == THEME_KEY
        context.consume
        app = @app
        show_theme_editor app if app
        return
      end

      super
    end

    # Keeps *value* under *key* and applies it.
    #
    # The tester's name goes to `tester.json` through `Options.rename`. Every
    # other key is set on the options, which are written whole. A key a flag
    # set for this run becomes the person's own, so the file keeps it.
    private def changed(key : String, value : Widgets::Form::Value) : Nil
      return unless value.is_a? Options::Value

      if key == "name"
        Options.rename @root, value.to_s
        return
      end

      @options[key] = value
      if @options.overridden? key
        @options.adopt key
        @form.note key, nil
      end
      @options.write @root
      @on_change.try &.call(@options)
    end
  end
end
