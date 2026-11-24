require "../../crystal-roguelike"

module Roguelike::Ui
  # What the two overlays of the filter editor share: the box they draw, and
  # how the letter keys drive a `Widgets::Form`.
  module FilterBox
    # Cells left clear to the left and right of the box.
    COLUMN_MARGIN = 2

    # Rows left clear above and below it.
    ROW_MARGIN = 1

    # The widest the box grows.
    WIDTH = 72

    # The smallest the box is, whatever the screen.
    LEAST = {30, 8}

    # Sizes the box for *screen*.
    def fit_into(screen : Rect) : Nil
      widest = (screen.width - 2 * COLUMN_MARGIN).clamp LEAST[0], WIDTH
      tallest = Math.max screen.height - 2 * ROW_MARGIN, LEAST[1]
      self.width = Layout::Sizing.fixed widest
      self.height = Layout::Sizing.fit min: LEAST[1], max: tallest
    end

    # Activates the row of *form* with the keyboard.
    private def activate_row(form : Widgets::Form, context : Widgets::Context) : Nil
      row = form.focused_row
      return unless row && row.enabled?

      row.activate unless row.enter
      context.consume
    end

    # Takes the choice on the row of *form* with the keyboard *step* places
    # along.
    private def turn_row(form : Widgets::Form, step : Int32) : Nil
      row = form.focused_row
      row.input.move step if row.is_a? Widgets::Form::ChoiceRow
    end

    # The letter keys of the control scheme, bound to *target*, which
    # answers `#dismiss`, `#show_help`, `#activate`, `#step` and `#turn`.
    def self.bindings(target, app : Widgets::App, modern : Bool) : Widgets::Bindings
      up, down, back, on = modern ? {"w", "s", "a", "d"} : {"k", "j", "h", "l"}

      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Escape"), "go back",
          ->(_context : Widgets::Context) { target.dismiss; nil }
        ["F1", "?"].each do |key|
          map.bind TermBuf::Key.parse(key), "show the keys that work here",
            ->(_context : Widgets::Context) { target.show_help app; nil }
        end
        if modern
          map.bind TermBuf::Key.parse("f"), "activate the focused row",
            ->(context : Widgets::Context) { target.activate context; nil }
        end
        map.bind TermBuf::Key.parse(down), "the row below",
          ->(context : Widgets::Context) { target.step 1, context; nil }
        map.bind TermBuf::Key.parse(up), "the row above",
          ->(context : Widgets::Context) { target.step(-1, context); nil }
        map.bind TermBuf::Key.parse(back), "the choice before",
          ->(_context : Widgets::Context) { target.turn(-1); nil }
        map.bind TermBuf::Key.parse(on), "the choice after",
          ->(_context : Widgets::Context) { target.turn 1; nil }
      end
    end
  end

  # The editor of one rule, which `Enter` on a row of a `FilterEditor` opens
  # over it.
  #
  # It is a modal overlay with a `Widgets::Form`. The first row opens a
  # menu of the sorts of item, one row for each trait says whether the rule
  # wants it, wants it not, or does not ask, and the last row chooses what
  # the rule decides.
  # The line at the top says the rule in words as it stands.
  #
  # Every change applies as it is made and runs `#on_change` with the rule.
  # `Escape` closes the editor.
  class RuleEditor(O) < Widgets::Overlay
    include FilterBox

    # What the border says.
    TITLE = "Rule"

    # The key of the row that chooses the sort of item.
    GROUP_KEY = "group"

    # What that row says, and what heads its menu.
    GROUP_LABEL = "Sort of item"

    # What that row shows for a rule about every sort.
    ANY = "Anything"

    # What starts the key of a trait's row.
    TRAIT_PREFIX = "trait-"

    # The values of a trait's row.
    EITHER = "either"
    YES    = "yes"
    NO     = "no"

    # The key of the row that chooses what the rule decides.
    OUTCOME_KEY = "outcome"

    # Runs after each change, with the rule as it now stands.
    property on_change : Proc(ItemFilter::Rule(O), Nil)? = nil

    # The traits that get a row.
    property traits : Array(ItemFilter::Trait)

    # The rule as it stands.
    getter rule : ItemFilter::Rule(O)

    # The form showing, rebuilt each time the editor opens.
    getter form : Widgets::Form

    # The list of keys `?` and `F1` show over the editor.
    getter help : Help

    # The menu of the sorts of item.
    getter menu : Widgets::Menu

    # Whether the letter keys are the modern ones.
    @modern = false

    # The rule in words.
    @summary : Widgets::Label

    def initialize(@traits : Array(ItemFilter::Trait) = ItemFilter::Trait.values,
                   z : Int32 = Widgets::Overlay::Z::DIALOG - 3)
      @rule = ItemFilter::Rule(O).new O.values.first
      @summary = Widgets::Label.new
      @form = Widgets::Form.new actions: false, height: Layout::Sizing.fit
      @help = Help.new
      @menu = Widgets::Menu.new
      @menu.column_margin = COLUMN_MARGIN
      @menu.row_margin = ROW_MARGIN

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @border = Widgets::Border.rounded title: " #{TITLE} "
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z
      add @summary, @form
    end

    # Whether the editor is up.
    def showing? : Bool
      open?
    end

    # Puts the editor up on *app*, showing *rule*.
    def show(app : Widgets::App, rule : ItemFilter::Rule(O), modern : Bool = false) : Nil
      @rule = rule
      @modern = modern
      remove @form
      @form = form_for rule
      @form.attach app
      add @form
      summarize

      bindings = FilterBox.bindings self, app, modern
      @help.sections = [Keys::Section.new("rule", bindings, [
        {"Up Down", "the row above or below"},
        {"Left Right", "the choice before or after"},
        {"Enter Space", "choose the sort of item, or take the next choice"},
      ])]
      self.keymap = bindings
      fit_into app.tree.screen
      open app
    end

    # The form for *rule*.
    private def form_for(rule : ItemFilter::Rule(O)) : Widgets::Form
      form = Widgets::Form.new actions: false, height: Layout::Sizing.fit

      form.section "Which items" do |section|
        section.action GROUP_KEY, GROUP_LABEL, hint: RuleEditor.named(rule.group),
          help: "The sort of item the rule is about. Enter chooses"

        @traits.each do |trait|
          held = rule.wants? trait
          section.choice "#{TRAIT_PREFIX}#{trait.to_s.underscore}", trait.label,
            [{EITHER, "Either"}, {YES, "Yes"}, {NO, "No"}],
            value: held.nil? ? EITHER : (held ? YES : NO),
            help: "Yes: #{trait.clause true}. No: #{trait.clause false}"
        end
      end

      form.section "What to do" do |section|
        section.choice OUTCOME_KEY, "Then", O.values.map { |outcome| {outcome.to_s.underscore, outcome.label.capitalize} },
          value: rule.outcome.to_s.underscore,
          help: "What happens to an item the rule matches"
      end

      form
    end

    # What the row of the sort of item shows for *group*.
    def self.named(group : ItemFilter::Group?) : String
      group.try(&.noun.capitalize) || ANY
    end

    # Puts the menu of the sorts of item up over the editor.
    def choose_group : Nil
      app = @app
      return unless app

      groups = [nil.as(ItemFilter::Group?)] + ItemFilter::Group.values.map(&.as(ItemFilter::Group?))
      entries = groups.map_with_index do |group, index|
        Widgets::Menu::Entry.new Widgets::Menu.letter(index), RuleEditor.named(group)
      end

      @menu.navigation = @modern ? Widgets::Navigation.selectable : Widgets::Navigation.new
      @menu.on_choose = nil
      @menu.on_choose_index = ->(index : Int32?) do
        changed GROUP_KEY, groups[index].try(&.to_s) || "" if index
        nil
      end
      @menu.show app, GROUP_LABEL, entries
      @menu.select_index groups.index(@rule.group) || 0
    end

    # Sizes the box again for a screen that has changed size.
    def refit(screen : Rect) : Nil
      fit_into screen if showing?
    end

    # Takes the editor down and gives the keyboard back.
    def dismiss : Nil
      return unless open?

      @menu.cancel if @menu.showing?
      @help.close_with nil if @help.open?
      self.keymap = nil
      close
    end

    # Puts the list of keys up over the editor.
    def show_help(app : Widgets::App) : Nil
      @help.screen_rows = app.tree.screen.height
      @help.open app
    end

    # Activates the focused row.
    def activate(context : Widgets::Context) : Nil
      activate_row @form, context
    end

    # Moves the keyboard *step* rows along.
    def step(step : Int32, context : Widgets::Context) : Nil
      @form.step_row step, context
    end

    # Takes the focused choice *step* places along.
    def turn(step : Int32) : Nil
      turn_row @form, step
    end

    # The keyboard goes to the first row.
    protected def initial_focus : Widgets::Widget?
      @form.reachable.first?.try &.target
    end

    # Takes each change the form reports.
    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      if event.is_a? Widgets::Form::Changed
        context.consume
        changed event.key, event.value.to_s
        return
      end

      if event.is_a?(Widgets::Form::Activated) && event.key == GROUP_KEY
        context.consume
        choose_group
        return
      end

      super
    end

    # Builds the rule again with *value* under *key*, and reports it.
    private def changed(key : String, value : String) : Nil
      group = @rule.group
      outcome = @rule.outcome
      tests = @rule.tests

      if key == GROUP_KEY
        group = ItemFilter::Group.parse? value
        row = @form.row GROUP_KEY
        row.hint = RuleEditor.named group if row.is_a? Widgets::Form::ActionRow
      elsif key == OUTCOME_KEY
        outcome = O.parse?(value) || outcome
      elsif trait = ItemFilter::Trait.parse?(key.lchop TRAIT_PREFIX)
        tests = tests.reject(&.trait.==(trait))
        tests += [ItemFilter::Test.new(trait, value == YES)] unless value == EITHER
        tests = tests.sort_by &.trait.value
      end

      @rule = ItemFilter::Rule(O).new outcome, group, tests
      summarize
      @on_change.try &.call(@rule)
    end

    private def summarize : Nil
      @summary.text = FilterEditor.sentence @rule
    end
  end

  # An editor for an `ItemFilter::List`, which a row of the options screen
  # opens over it.
  #
  # It is a modal overlay. The rules are a `Widgets::ListEditor`, each row
  # saying its rule in words and ending with what the rule decides. Under
  # them a `Widgets::Form` chooses what happens to an item no rule matches,
  # adds a rule, and puts the rules the editor was given as its default
  # back.
  #
  # *O* is the enum of outcomes. It answers `#label` with the word a row
  # ends with. The editor knows nothing else about what the rules are for,
  # so the same one edits the rules of automatic pickup and any other list.
  #
  # Every change applies as it is made and runs `#on_change` with the whole
  # list. `Escape` closes the editor.
  class FilterEditor(O) < Widgets::Overlay
    include FilterBox

    # The key of the row that chooses the outcome when no rule matches.
    OTHERWISE_KEY = "otherwise"

    # The key of the row that adds a rule.
    ADD_KEY = "add"

    # The key of the row that puts the default rules back.
    RESET_KEY = "reset"

    # What the line under the rules says.
    HINT = "+ add  - remove  [ ] move"

    # Runs after each change, with the rules as they now stand.
    property on_change : Proc(ItemFilter::List(O), Nil)? = nil

    # Runs after the editor closes.
    property on_close : Proc(Nil)? = nil

    # The rules the reset row puts back.
    property default : ItemFilter::List(O)

    # The rules as they stand.
    getter rules : ItemFilter::List(O)

    # The rows of rules.
    getter list : Widgets::ListEditor(ItemFilter::Rule(O))

    # The rows under the rules, rebuilt each time the editor opens.
    getter form : Widgets::Form

    # The editor of one rule.
    getter rule_editor : RuleEditor(O)

    # The list of keys `?` and `F1` show over the editor.
    getter help : Help

    # Whether the letter keys are the modern ones.
    @modern = false

    # *title* is what the border says, and *intro* the line over the rules.
    def initialize(title : String, intro : String, @default : ItemFilter::List(O),
                   traits : Array(ItemFilter::Trait) = ItemFilter::Trait.values,
                   z : Int32 = Widgets::Overlay::Z::DIALOG - 5)
      @rules = @default
      @list = Widgets::ListEditor(ItemFilter::Rule(O)).new
      @form = Widgets::Form.new actions: false, height: Layout::Sizing.fit
      @rule_editor = RuleEditor(O).new traits
      @help = Help.new
      @hint = Widgets::Label.new HINT

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @border = Widgets::Border.rounded title: " #{title} "
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      @list.limit = ItemFilter::LIMIT
      @list.empty_text = "No rules. Press + to add one."
      @list.label = ->(rule : ItemFilter::Rule(O)) { rule.phrase }
      @list.tail = ->(rule : ItemFilter::Rule(O)) { rule.outcome.label }
      @list.on_new = -> { ItemFilter::Rule(O).new(O.values.first).as(ItemFilter::Rule(O)?) }
      @list.on_change = ->(rules : Array(ItemFilter::Rule(O))) { take @rules.with(rules); nil }
      @list.on_edit = ->(index : Int32, rule : ItemFilter::Rule(O)) { edit index, rule; nil }
      @list.on_overrun = ->(step : Int32) { leave_list if step > 0; nil }

      add Widgets::Label.new(intro), @list, @hint, @form
    end

    # A rule and what it decides, as one line.
    def self.sentence(rule : ItemFilter::Rule(O)) : String forall O
      "#{rule.phrase}: #{rule.outcome.label}"
    end

    # Whether the editor is up.
    def showing? : Bool
      open?
    end

    # Puts the editor up on *app*, showing *rules*.
    def show(app : Widgets::App, rules : ItemFilter::List(O), modern : Bool = false) : Nil
      @rules = rules
      @modern = modern
      @list.items = rules.rules
      @list.select 0
      rebuild app

      bindings = FilterBox.bindings self, app, modern
      bindings.bind TermBuf::Key.parse("Tab"), "the next control",
        ->(context : Widgets::Context) { context.focus.next; nil }
      bindings.bind TermBuf::Key.parse("Shift+Tab"), "the control before",
        ->(context : Widgets::Context) { context.focus.previous; nil }
      @help.sections = [Keys::Section.new("rules", bindings, [
        {"Up Down", "the row above or below"},
        {"Enter Space", "edit a rule, or activate a row"},
        {"+ Insert", "add a rule after this one"},
        {"- Delete Backspace", "remove this rule"},
        {"[ ]", "move this rule up or down"},
        {"Left Right", "the choice before or after"},
      ])]
      self.keymap = bindings
      fit_into app.tree.screen
      open app
    end

    # Builds the rows under the rules for the rules as they stand.
    private def rebuild(app : Widgets::App) : Nil
      remove @form
      @form = Widgets::Form.new actions: false, height: Layout::Sizing.fit
      @form.section "After the rules" do |section|
        section.choice OTHERWISE_KEY, "Anything else",
          O.values.map { |outcome| {outcome.to_s.underscore, outcome.label.capitalize} },
          value: @rules.otherwise.to_s.underscore,
          help: "What happens to an item no rule matches"
        section.action ADD_KEY, "Add a rule", hint: "Enter",
          help: "Add a rule at the end of the list"
        section.action RESET_KEY, "Reset", hint: "Enter",
          help: "Put the rules back as the game sets them"
      end
      @form.keymap = form_keys app
      @form.attach app
      add @form
    end

    # The form's own row keys, with `Up` on the first row going to the rules.
    private def form_keys(app : Widgets::App) : Widgets::Bindings
      form = @form
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Up"), "the row before",
          ->(context : Widgets::Context) { step(-1, context); nil }
        map.bind TermBuf::Key.parse("Down"), "the row after",
          ->(context : Widgets::Context) { form.step_row 1, context }
        map.bind TermBuf::Key.parse("Tab"), "the next control",
          ->(context : Widgets::Context) { form.tab 1, context }
        map.bind TermBuf::Key.parse("Shift+Tab"), "the control before",
          ->(context : Widgets::Context) { form.tab(-1, context) }
        map.bind TermBuf::Key.parse("Home"), "the first row",
          ->(context : Widgets::Context) { form.end_row(-1, context) }
        map.bind TermBuf::Key.parse("End"), "the last row",
          ->(context : Widgets::Context) { form.end_row 1, context }
      end
    end

    # Sizes the box again for a screen that has changed size.
    def refit(screen : Rect) : Nil
      fit_into screen if showing?
      @rule_editor.refit screen
    end

    # Takes the editor down and gives the keyboard back.
    def dismiss : Nil
      return unless open?

      @rule_editor.dismiss
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

    # Whether the rules have the keyboard.
    def listing? : Bool
      @list.list.focused?
    end

    # Edits the highlighted rule, or activates the focused row under them.
    def activate(context : Widgets::Context) : Nil
      return @list.edit if listing?

      activate_row @form, context
    end

    # Moves the keyboard *step* rows along, across the rules and the rows
    # under them.
    def step(step : Int32, context : Widgets::Context) : Nil
      return @list.step step if listing?

      first = @form.reachable.first?
      current = @form.focused_row
      if step < 0 && first && current && first.same?(current)
        current.leave
        context.focus.focus @list.list
      else
        @form.step_row step, context
      end
    end

    # Takes the focused choice *step* places along.
    def turn(step : Int32) : Nil
      turn_row @form, step unless listing?
    end

    # Puts the keyboard on the first row under the rules.
    private def leave_list : Nil
      app = @app
      target = @form.reachable.first?.try &.target
      app.focus.focus target if app && target
    end

    # Opens the editor of one rule on the rule at *index*.
    private def edit(index : Int32, rule : ItemFilter::Rule(O)) : Nil
      app = @app
      return unless app

      @rule_editor.on_change = ->(changed : ItemFilter::Rule(O)) do
        @list.replace index, changed
        nil
      end
      @rule_editor.show app, rule, @modern
    end

    # Keeps *rules* and reports them.
    private def take(rules : ItemFilter::List(O)) : Nil
      return if rules == @rules

      @rules = rules
      @on_change.try &.call(rules)
    end

    # The keyboard goes to the rules, or to the rows under them when there
    # are no rules.
    protected def initial_focus : Widgets::Widget?
      return @list.list unless @list.items.empty?

      @form.reachable.first?.try &.target
    end

    # Takes what the rows under the rules report.
    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      case event
      when Widgets::Form::Changed
        context.consume
        if event.key == OTHERWISE_KEY
          outcome = O.parse? event.value.to_s
          take @rules.with(outcome) unless outcome.nil?
        end
      when Widgets::Form::Activated
        context.consume
        activated event.key
      else
        super
      end
    end

    private def activated(key : String) : Nil
      app = @app
      return unless app

      case key
      when ADD_KEY
        @list.select @list.items.size - 1
        @list.focus app
        @list.add
      when RESET_KEY
        @list.items = @default.rules
        @list.select 0
        take @default
        row = @form.row OTHERWISE_KEY
        row.value = @default.otherwise.to_s.underscore if row.is_a? Widgets::Form::ChoiceRow
      end
    end
  end
end
