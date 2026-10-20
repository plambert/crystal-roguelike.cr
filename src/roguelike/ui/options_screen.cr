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

    # Takes the form's messages as they are posted.
    #
    # The form tells of a change by relaying the message its row's widget
    # sent. The router delivers a message sent during a drain on the drain
    # after, which in the game's loop is the next keystroke. This takes the
    # form's own `Form::Changed` at once and passes everything else on.
    class Relay
      include Widgets::Mailbox

      def initialize(@screen : OptionsScreen)
      end

      def post(message : Widgets::Message, source : Widgets::Widget) : Nil
        if message.is_a?(Widgets::Form::Changed) && source.same?(@screen.form)
          @screen.changed message.key, message.value
        else
          @screen.routed_by.try &.post(message, source)
        end
      end
    end

    def initialize(@root : Path = Submit.root, z : Int32 = Widgets::Overlay::Z::DIALOG - 10)
      @options = Options.new
      @form = OptionsScreen.form_for @options, Tester::ANONYMOUS
      @help = Help.new

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
      @form.mailbox = Relay.new self
      @form.attach app
      add @form

      @help.sections = [Keys.options_screen(self, app)]
      self.keymap = @help.sections.first.bindings
      fit_into app.tree.screen
      open app
    end

    # The form for *options*, a section for each heading in
    # `Options::SETTINGS`, with *name* in the tester's row.
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
    end

    # Takes the screen down and gives the keyboard back.
    def dismiss : Nil
      return unless open?

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

    # Hands the key being answered to a text row that has the keyboard, so
    # what is typed there goes into the field. Answers whether it did.
    def typed?(context : Widgets::Context) : Bool
      row = focused_row
      event = context.event
      return false unless row.is_a?(Widgets::Form::TextRow) && event.is_a?(TermBuf::Events::Key)

      row.press event.key
      true
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

    # Does what `Enter` means on the row with the keyboard. A toggle flips
    # and a choice moves on.
    def press(context : Widgets::Context) : Nil
      return if typed? context

      case row = focused_row
      when Widgets::Form::ToggleRow then row.activate
      when Widgets::Form::ChoiceRow then row.input.cycle
      end
    end

    # The keyboard goes to the first row.
    protected def initial_focus : Widgets::Widget?
      @form.reachable.first?.try &.target
    end

    # Keeps *value* under *key* and applies it.
    #
    # The tester's name goes to `tester.json` through `Options.rename`. Every
    # other key is set on the options, which are written whole. A key a flag
    # set for this run becomes the person's own, so the file keeps it.
    def changed(key : String, value : Widgets::Form::Value) : Nil
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
