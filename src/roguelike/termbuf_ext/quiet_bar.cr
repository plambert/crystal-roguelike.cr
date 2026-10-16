require "termbuf-widgets"

module TermBuf::Widgets
  # A scrollbar that draws nothing while everything fits.
  #
  #     bar = QuietBar.new pager
  #     row.add pager, bar
  #
  # While the content fits, the column stays blank and shows whatever ground
  # is under it. When the content outgrows the window, the track and the
  # thumb appear. The column is the same width either way, so nothing beside
  # it moves when the bar comes and goes.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`, perhaps as a
  # setting on `Scrollbar` itself, beside `RuleBar`.
  class QuietBar < Scrollbar
    # Whether everything the target holds is showing.
    def fits? : Bool
      held = target
      return true unless held

      axis = vertical? ? 1 : 0
      held.content_size[axis] <= held.viewport_size[axis]
    end

    def draw(view : View) : Nil
      super unless fits?
    end

    # A bar that is not drawn takes no clicks.
    def handle(event : Event, context : Context) : Nil
      super unless fits?
    end
  end
end
