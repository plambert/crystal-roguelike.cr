require "termbuf-widgets"
require "./navigation"

# Extraction candidate: `TermBuf::Widgets::Prompt`, for termbuf-widgets.cr.
#
# `Dialog.confirm` asks a yes or no question. It needs `Tab` to reach a button
# and `Enter` to press it. That is three keystrokes for one decision.
#
# A prompt takes one keystroke. `git add -p`, `less`, `apt` and every roguelike
# ask that way. The widget catalog has nothing that does it.
#
# This type is written in `TermBuf::Widgets` rather than in `Roguelike`.
# Extracting it is then a file move with no edits.
#
# Two questions remain open:
#
# * Should an answer arrive as a `Message` or through `#on_answer`? The
#   catalog uses `Message` for every other input widget. A prompt is
#   answered and then dismissed. `#on_answer` runs as soon as a key arrives. A
#   `Message` would arrive on the next pump.
# * Should the answers be a keymap at all? A keymap lets a caller rebind them.
#   The answers are the question's own text here, so a rebind would leave
#   the prompt offering keys that do nothing. The keymap is built from the
#   keys each time a question is asked.
module TermBuf::Widgets
  # A question answered by one keystroke.
  #
  #     prompt.on_answer = ->(key : Char?) { leave if key == 'y' }
  #     prompt.ask app, "Really leave?", "yn", default: 'n'
  #
  # A prompt is an `Overlay`. It draws a small box in the middle of the screen
  # and dims everything behind it. The text behind stays readable. Nothing
  # behind it answers a key, because the overlay pushes a focus scope and a key
  # nothing in the scope claims stops at the prompt.
  class Prompt < Overlay
    # A named choice that answers with its existing character value.
    record Choice, key : Char, label : String, enabled : Bool = true

    # The question. Empty while nobody is asking.
    getter question : String = ""

    # The keys that answer it, in the order the prompt offers them.
    getter keys : String = ""

    # The key `Enter` answers with. `nil` when `Enter` answers nothing.
    getter default : Char?

    # The navigation contract used for named choices.
    getter navigation : Navigation = Navigation.new

    # What runs when a key answers.
    #
    # The argument is the key. It is `nil` when the person canceled with
    # `Escape`.
    property on_answer : Proc(Char?, Nil)? = nil

    # The row the question is drawn on.
    getter line : Widgets::Label

    @choices : Array(Choice) = [] of Choice
    @choice_index : Int32 = 0
    @choice_mode : Bool = false

    # What the offered keys are drawn in.
    property keys_style : Style = Style::DEFAULT.bold

    def initialize(z : Int32 = Z::DIALOG, style : Style? = nil)
      @line = Label.new ""
      @offered = Label.new ""
      @offered.style = @keys_style

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Row
      @gap = 1
      @padding = Layout::Padding.new 0, 2, 0, 2
      @width = Layout::Sizing.fit(min: 20)
      @height = Layout::Sizing.fit
      @border = Border.rounded
      @style = style
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      add @line, @offered
    end

    # Whether a question is up.
    def asking? : Bool
      open?
    end

    # The keyboard lands here while a question is up.
    #
    # The prompt holds no control of its own. Focus has to land somewhere
    # inside the scope it pushed, and the prompt is the only thing in it.
    def focusable? : Bool
      open?
    end

    # Asks *question* on *app*. Answers it with any one of *keys*.
    #
    # *default* names the key `Enter` answers with. It has to be one of
    # *keys*.
    #
    # A question already up is replaced. The scope it pushed is kept.
    def ask(app : App, question : String, keys : String,
            default : Char? = nil) : Nil
      if default && !keys.includes? default
        raise ArgumentError.new "default #{default.inspect} is not one of #{keys.inspect}"
      end

      @question = question
      @keys = keys
      @default = default
      @choices = [] of Choice
      @choice_mode = false
      @navigation = Navigation.new

      @line.text = question
      @offered.text = "[#{offered}]"
      @offered.style = @keys_style
      install_answers answers

      open app
    end

    # Asks *question* with named choices and injected row navigation.
    #
    # *default* selects the initial choice and is still returned to
    # `#on_answer` when that choice is activated. It is required so the caller
    # chooses the safe initial answer explicitly. Escape always returns `nil`.
    def ask(app : App, question : String, choices : Enumerable(Choice),
            default : Char,
            navigation : Navigation = Navigation.selectable) : Nil
      @choices = choices.to_a
      raise ArgumentError.new "a prompt needs at least one choice" if @choices.empty?
      if default && !@choices.any? { |choice| choice.key == default && choice.enabled }
        raise ArgumentError.new "default #{default.inspect} is not an enabled choice"
      end

      @question = question
      @keys = @choices.map(&.key).join
      @default = default
      @navigation = navigation
      @choice_mode = true
      @choice_index = @choices.index { |choice| choice.key == default } || 0

      @line.text = question
      update_choices
      @offered.style = @keys_style
      install_answers choice_answers

      open app
    end

    # Takes the question down without an answer. Runs `#on_answer` with `nil`.
    def cancel : Nil
      return unless open?

      finish nil
    end

    # The keys as the prompt offers them. The default key is upper case.
    #
    # The convention is an upper case letter for the default answer. `[yN]`
    # says that `n` happens on `Enter`.
    def offered : String
      return named_offered if @choice_mode

      chosen = @default
      return @keys unless chosen

      @keys.gsub(chosen, chosen.upcase)
    end

    # The bindings a question answers.
    #
    # A key outside this set reaches the prompt and stops. The overlay is
    # modal, so nothing behind it answers.
    private def answers : Bindings
      map = Bindings.new

      @keys.each_char do |key|
        map.bind Key.character(key), "answer #{key}",
          ->(_context : Context) { finish key; nil }
      end

      map.bind Key.named(Key::Name::Escape), "leave the question unanswered",
        ->(_context : Context) { finish nil; nil }

      chosen = @default
      if chosen
        map.bind Key.named(Key::Name::Enter), "answer #{chosen}",
          ->(_context : Context) { finish chosen; nil }
      end

      map
    end

    # The bindings a named-choice question answers.
    private def choice_answers : Bindings
      map = Bindings.new

      @navigation.previous_row.each do |key|
        map.bind key, "the choice before",
          ->(_context : Context) { move_choice(-1); nil }
      end
      @navigation.next_row.each do |key|
        map.bind key, "the choice after",
          ->(_context : Context) { move_choice(1); nil }
      end
      @navigation.activate.each do |key|
        map.bind key, "choose the highlighted answer",
          ->(_context : Context) { choose_highlighted; nil }
      end
      @navigation.cancel.each do |key|
        map.bind key, "leave the question unanswered",
          ->(_context : Context) { finish nil; nil }
      end

      map
    end

    # Replaces both the widget and its active focus-scope bindings.
    private def install_answers(bindings : Bindings) : Nil
      self.keymap = bindings
      @scope.try &.keymap = bindings
    end

    # Moves to the next enabled choice in *direction*.
    private def move_choice(direction : Int32) : Nil
      index = @choice_index + direction
      while index >= 0 && index < @choices.size
        if @choices[index].enabled
          @choice_index = index
          update_choices
          invalidate_layout
          return
        end
        index += direction
      end
    end

    # Answers with the highlighted choice when it is enabled.
    private def choose_highlighted : Nil
      choice = @choices[@choice_index]?
      finish choice.key if choice && choice.enabled
    end

    # Updates the named choices in the prompt's offered line.
    private def update_choices : Nil
      @offered.text = named_offered
    end

    # The named choices, with the selected one bracketed.
    private def named_offered : String
      @choices.map_with_index do |choice, index|
        label = choice.enabled ? choice.label : "#{choice.label} (unavailable)"
        index == @choice_index ? "[ #{label} ]" : label
      end.join("   ")
    end

    # Takes the question down. Runs `#on_answer` with *key*.
    #
    # The keymap goes with it. A closed prompt that kept its bindings would
    # answer again on the next press of the same key, before the next frame
    # rebuilt the focus ring.
    private def finish(key : Char?) : Nil
      @question = ""
      @keys = ""
      @default = nil
      @choices = [] of Choice
      @choice_mode = false
      self.keymap = nil

      close

      @on_answer.try &.call(key)
    end
  end
end
