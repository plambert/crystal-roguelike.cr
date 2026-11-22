require "termbuf-widgets"

module TermBuf::Widgets
  # A horizontal rule whose label can carry an aside after it.
  #
  #     rule = AsideRule.new label: "Floor 7"
  #     rule.aside = "Walking to fountain"
  #
  # The two are written together in the middle of the rule, as
  # "Floor 7 - Walking to fountain". When the rule is too narrow for both,
  # the aside is cut short with an ellipsis, and when even `SHORTEST` cells
  # of it will not fit, it is left out. The label is never cut for the
  # aside's sake.
  #
  # The aside takes no part in layout. The rule asks only for its label's
  # width, as a `Divider` does.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`, perhaps as a
  # setting on `Divider` itself.
  class AsideRule < Divider
    # What goes between the label and the aside.
    SEPARATOR = " - "

    # The fewest cells of an aside worth writing when it is cut short.
    SHORTEST = 8

    # Written after the label, or `nil` for none.
    property aside : String? = nil

    def draw(view : View) : Nil
      return if view.width <= 0 || view.height <= 0

      view.fill view.bounds, rule
      text = written view.width, view.policy
      return unless text && horizontal?

      room = view.width - Unicode.string_width(text, view.policy)
      view.write Math.max(room // 2, 0), 0, text
    end

    # What is written on the rule when it is *width* cells wide, with a
    # space at either end. `nil` when nothing is.
    def written(width : Int32, policy : Unicode::WidthPolicy = Unicode.policy) : String?
      label = @label.presence
      aside = @aside.presence
      return fitted(label, width, policy) unless aside
      return fitted(aside, width, policy, cut: true) unless label

      whole = " #{label}#{SEPARATOR}#{aside} "
      return whole if Unicode.string_width(whole, policy) <= width

      head = " #{label}#{SEPARATOR}"
      room = width - Unicode.string_width(head, policy) - 1
      return fitted(label, width, policy) if room < SHORTEST

      "#{head}#{Unicode.ellipsize aside, room, policy: policy} "
    end

    # *text* with a space either side, cut to *width*. An ellipsis marks
    # the cut when *cut* is true.
    private def fitted(text : String?, width : Int32, policy : Unicode::WidthPolicy,
                       cut : Bool = false) : String?
      return unless text

      spaced = " #{text} "
      shown = if cut && Unicode.string_width(spaced, policy) > width
                " #{Unicode.ellipsize text, width - 2, policy: policy} "
              else
                Unicode.truncate spaced, width, policy
              end
      shown.strip.empty? ? nil : shown
    end
  end
end
