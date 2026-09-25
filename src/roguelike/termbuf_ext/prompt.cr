require "termbuf-widgets"

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
    # The question. Empty while nobody is asking.
    getter question : String = ""

    # The keys that answer it, in the order the prompt offers them.
    getter keys : String = ""

    # The key `Enter` answers with. `nil` when `Enter` answers nothing.
    getter default : Char?

    # What runs when a key answers.
    #
    # The argument is the key. It is `nil` when the person canceled with
    # `Escape`.
    property on_answer : Proc(Char?, Nil)? = nil

    # The row the question is drawn on.
    getter line : Widgets::Label

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

      @line.text = question
      @offered.text = "[#{offered}]"
      @offered.style = @keys_style
      self.keymap = answers

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

    # Takes the question down. Runs `#on_answer` with *key*.
    #
    # The keymap goes with it. A closed prompt that kept its bindings would
    # answer again on the next press of the same key, before the next frame
    # rebuilt the focus ring.
    private def finish(key : Char?) : Nil
      @question = ""
      @keys = ""
      @default = nil
      self.keymap = nil

      close

      @on_answer.try &.call(key)
    end
  end
end
