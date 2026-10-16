require "termbuf-widgets"

module TermBuf::Widgets
  # A scrollbar that draws as a plain rule while everything fits.
  #
  #     bar = RuleBar.new panel
  #     row.add panel, bar, map
  #
  # It stands where a `Divider` between two panes would stand. While the
  # content fits, it draws the divider's rule and nothing else. When the
  # content outgrows the window, a thumb appears on the rule. The column
  # stays the same width either way, so nothing beside it moves when the
  # thumb comes and goes.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`, perhaps as a
  # setting on `Scrollbar` itself.
  class RuleBar < Scrollbar
    # Whether everything the target holds is showing.
    def fits? : Bool
      held = target
      return true unless held

      axis = vertical? ? 1 : 0
      held.content_size[axis] <= held.viewport_size[axis]
    end

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0
      return super unless fits?

      view.fill view.bounds, vertical? ? track : track_across
    end
  end
end
