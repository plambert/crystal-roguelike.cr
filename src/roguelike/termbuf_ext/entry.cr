require "termbuf-widgets"

# Extraction candidate: `TermBuf::Widgets::Entry`, for termbuf-widgets.cr.
#
# `Prompt` asks a question answered by one keystroke. This is the same box
# with a line to type on instead, which is the other half of the pair and the
# thing every installer, every `git commit` and every "name your character"
# screen puts up.
#
# `Dialog` has buttons. `Field` has no box around it and no question over it.
# Neither is a question with an answer typed into it.
#
# This type is written in `TermBuf::Widgets` rather than in `Roguelike`.
# Extracting it is then a file move with no edits.
#
# Two questions remain open:
#
# * Should an answer arrive as a `Message` rather than through `#on_answer`?
#   `Prompt` answers the same way and the two should match.
# * Should it validate? A caller that refuses an answer has to put the box
#   back up itself, which loses what was typed. A `Proc(String, String?)`
#   answering a complaint would keep the box up with the text still in it.
module TermBuf::Widgets
  # A question with a line typed into it.
  #
  #     entry.on_answer = ->(text : String?) { name_it text if text }
  #     entry.ask app, "What is your name?"
  #
  # An `Overlay`, modal, in the middle of the screen. `Enter` answers with
  # what was typed. `Escape` answers `nil`. Everything `Editor` binds works on
  # the line, so a person gets word motion, a kill ring and a history if the
  # caller gives the editor one.
  class Entry < Overlay
    # The narrowest box.
    LEAST_WIDTH = 24

    # How many cells it leaves clear to its left and to its right.
    COLUMN_MARGIN = 6

    # The row the question is drawn on.
    getter line : Label

    # The line being typed.
    getter field : Field

    # The question. Empty while nobody is asking.
    getter question : String = ""

    # What runs when the question is answered.
    #
    # The argument is what was typed. It is `nil` when the person pressed
    # `Escape`, and it can be empty when they pressed `Enter` on a bare line.
    property on_answer : Proc(String?, Nil)? = nil

    def initialize(z : Int32 = Z::DIALOG, style : Style? = nil)
      @line = Label.new ""
      @field = Field.new

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @gap = 1
      @padding = Layout::Padding.new 0, 2, 0, 2
      @width = Layout::Sizing.fit(min: LEAST_WIDTH)
      @height = Layout::Sizing.fit
      @border = Border.rounded
      @style = style
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      add @line, @field
    end

    # Whether a question is up.
    def asking? : Bool
      open?
    end

    # The keyboard lands on the field rather than on the box.
    def focusable? : Bool
      false
    end

    # What has been typed so far.
    def text : String
      @field.text
    end

    # Asks *question* on *app*, with *value* already on the line.
    #
    # *placeholder* is drawn on an empty line, dimmed, and is not an answer:
    # a person who presses `Enter` on an empty line answers with an empty
    # string.
    #
    # A question already up is replaced. The scope it pushed is kept.
    def ask(app : App, question : String, value : String = "",
            placeholder : String? = nil) : Nil
      @question = question
      @line.text = question
      @field.text = value
      @field.placeholder = placeholder

      fit_into app.tree.screen
      open app
    end

    # Sizes the box to *screen*.
    #
    # It grows to fit the question and stops at the screen less a margin on
    # each side. The line typed into scrolls sideways inside whatever is
    # left, so a long answer is never what decides the width.
    def fit_into(screen : Rect) : Nil
      widest = Math.max screen.width - 2 * COLUMN_MARGIN, LEAST_WIDTH

      self.width = Layout::Sizing.fit min: LEAST_WIDTH, max: widest
    end

    # Takes the question down without an answer. Runs `#on_answer` with `nil`.
    def cancel : Nil
      return unless open?

      finish nil
    end

    # What the field says.
    #
    # `Enter` answers. `Escape` and `Ctrl+C` reach the field first, which
    # gives up on the line and sends `Cancelled`.
    def handle(event : Event, context : Context) : Nil
      case event
      when Field::Accepted
        finish event.text
        context.consume
      when Field::Cancelled, Field::EndOfInput
        finish nil
        context.consume
      end
    end

    # Takes the box down. Runs `#on_answer` with *answer*.
    private def finish(answer : String?) : Nil
      @question = ""
      close

      @on_answer.try &.call(answer)
    end
  end
end
