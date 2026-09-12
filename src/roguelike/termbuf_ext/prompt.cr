require "termbuf-widgets"

# Extraction candidate: `TermBuf::Widgets::Prompt`, for termbuf-widgets.cr.
#
# `Dialog.confirm` asks a yes or no question in a box. It needs `Tab` to reach
# a button and `Enter` to press it. That is three keystrokes for one decision.
#
# A one-line prompt takes one keystroke. `git add -p`, `less`, `apt` and every
# roguelike ask that way. The widget catalogue has nothing that does it.
#
# This type is written in `TermBuf::Widgets` rather than in `Roguelike`.
# Extracting it is then a file move with no edits.
#
# Two questions remain open:
#
# * Should an answer arrive as a `Message` or through `#on_answer`? The
#   catalogue uses `Message` for every other input widget. A prompt is
#   answered and then dismissed. `#on_answer` runs as soon as a key arrives.
#   A `Message` would arrive on the next pump.
# * Should `#ask` take the `App` at all? It takes one so that it can push a
#   focus scope. `Overlay#open` takes one for the same reason. A prompt that
#   did not push a scope could not take the keyboard: `Router` consults the
#   chain's keymaps before any widget's `#handle`, so an application binding
#   on `y` would answer before the prompt saw the key.
module TermBuf::Widgets
  # A question answered by one keystroke.
  #
  #     prompt.on_answer = ->(key : Char?) { leave if key == 'y' }
  #     prompt.ask app, "Really leave?", "yn", default: 'n'
  #
  # The widget draws one row. It draws nothing while nobody is asking.
  #
  # A question pushes a focus scope with the prompt as its root. Every key
  # then reaches the prompt and stops there. An application binding on `y`
  # would otherwise answer before the prompt saw the key. Answering the
  # question pops the scope.
  class Prompt < Widget
    # What the prompt draws when a key is the default.
    #
    # The convention is an upper case letter for the default answer. `[yN]`
    # says that `n` happens on `Enter`.
    property style_question : Style = Style::DEFAULT
    property style_keys : Style = Style::DEFAULT.bold

    # The question. Empty while nobody is asking.
    getter question : String = ""

    # The keys that answer it, in the order the prompt offers them.
    getter keys : String = ""

    # The key `Enter` answers with. `nil` when `Enter` answers nothing.
    getter default : Char?

    # Whether the prompt is waiting for an answer.
    getter? asking : Bool = false

    # What runs when a key answers.
    #
    # The argument is the key. It is `nil` when the person cancelled with
    # `Escape`.
    property on_answer : Proc(Char?, Nil)? = nil

    # The application the question was asked on. `nil` while nobody is asking.
    @app : App? = nil

    # The focus scope the question pushed.
    @scope : Focus::Scope? = nil

    def initialize(style : Style? = nil)
      @width = Layout::Sizing.grow
      @height = Layout::Sizing.fixed 1
      @style = style
      @hidden = true
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
      self.hidden = false

      return if @asking

      @asking = true
      @app = app
      @scope = app.focus.push self
      app.focus.focus self
    end

    # Takes the question down without an answer. Runs `#on_answer` with `nil`.
    def cancel : Nil
      return unless @asking

      finish nil
    end

    # The keyboard lands here while a question is up. It lands nowhere else.
    def focusable? : Bool
      @asking
    end

    # The row the prompt draws.
    def line : String
      return "" unless @asking

      "#{@question} [#{offered}]"
    end

    # The keys as the prompt offers them. The default key is upper case.
    def offered : String
      chosen = @default
      return @keys unless chosen

      @keys.gsub(chosen, chosen.upcase)
    end

    def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
      width = Unicode.string_width line, policy

      Layout::Intrinsic.new 1, Math.max(width, 1)
    end

    def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
      1
    end

    # Takes every key while a question is up.
    #
    # A key in `#keys` answers. `Escape` cancels. `Enter` answers with the
    # default. Every other key is consumed and ignored.
    def handle(event : Event, context : Context) : Nil
      return unless @asking
      return unless event.is_a? Events::Key

      context.consume
      key = event.key

      return cancel if key.is? Key::Name::Escape

      if key.is? Key::Name::Enter
        chosen = @default
        finish chosen if chosen
        return
      end

      return unless key.character?

      typed = key.char
      finish typed if @keys.includes? typed
    end

    def draw(view : View) : Nil
      return unless @asking
      return if view.width <= 0 || view.height <= 0

      view.write 0, 0, "#{@question} [", @style_question
      spot = Unicode.string_width "#{@question} [", view.policy
      view.write spot, 0, offered, @style_keys
      view.write spot + Unicode.string_width(offered, view.policy), 0, "]",
        @style_question
    end

    # Takes the question down. Runs `#on_answer` with *key*.
    private def finish(key : Char?) : Nil
      @asking = false
      @question = ""
      @keys = ""
      @default = nil
      self.hidden = true

      app = @app
      @app = nil
      @scope = nil
      app.try &.focus.pop

      @on_answer.try &.call(key)
    end
  end
end
