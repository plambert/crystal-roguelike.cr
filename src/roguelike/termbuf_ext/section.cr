require "termbuf-widgets"

module TermBuf::Widgets
  # A block of rows under a header row that a click shows or hides.
  #
  #     section = Section.new "Pack", header_style: Style::DEFAULT.reverse
  #     section.body.add row, row
  #     section.summary = "14"
  #
  # The header is one row painted across the whole width in `#header_style`.
  # A run of sections therefore needs no rule or blank row between them,
  # because each header separates its section from the one above. A collapsed
  # header shows `#summary` against its right edge.
  #
  # A section never takes the keyboard. `Disclosure` takes it, and binds
  # `Enter` and `Space` on its header. That suits a form. It does not suit a
  # panel whose keys belong to whatever owns the screen.
  #
  # `#header` and `#rows` are the rows a keyboard selection would move among.
  # `Scrollable#scroll_to` brings either into view.
  #
  # Extraction candidate: this belongs in `termbuf-widgets.cr`.
  class Section < Widget
    # The header row: the expander, the title, and the summary.
    class Header < Widget
      # The expanders on a terminal that draws them one cell wide, open first.
      GLYPHS = {"▼", "▶"}

      # What stands in for them on a terminal that does not.
      GLYPHS_ASCII = {"-", "+"}

      # How many cells are left at each end of the row.
      INSET = 1

      def initialize
        @width = Layout::Sizing.grow
        @height = Layout::Sizing.fixed 1
      end

      # The section this header opens and closes.
      def section : Section
        parent.as Section
      end

      # The expander under *policy*.
      def glyph(policy : Unicode::WidthPolicy = Unicode.policy) : String
        open, shut = Glyphs.single_cell?(GLYPHS, policy) ? GLYPHS : GLYPHS_ASCII
        section.expanded? ? open : shut
      end

      # What the row says, for a spec or a screen reader.
      def text : String
        found = "#{glyph} #{section.title}"
        summary = section.summary
        return found if section.expanded? || summary.empty?

        "#{found} #{summary}"
      end

      # A press toggles the section and is claimed. The wheel and pointer
      # movement pass on, after `Section#on_point` has heard about them.
      def handle(event : Event, context : Context) : Nil
        return unless event.is_a? Events::Mouse

        if event.action.press? && !event.button.wheel?
          section.toggle
          context.consume
          return
        end

        section.on_point.try &.call
      end

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        wanted = Unicode.string_width("#{glyph policy} #{section.title}", policy)
        Layout::Intrinsic.new 1, wanted + 2 * INSET
      end

      def height_for_width(width : Int32, policy : Unicode::WidthPolicy) : Int32
        1
      end

      def draw(view : View) : Nil
        return if view.width <= 0 || view.height <= 0

        paint = section.header_style
        view.fill view.bounds, ' ', paint

        summary = section.expanded? ? "" : section.summary
        room = view.width - 2 * INSET
        unless summary.empty?
          wide = Unicode.string_width summary, view.policy
          room -= wide + 1
          view.write view.width - INSET - wide, 0, summary, paint if room >= 0
        end
        return if room <= 0

        head = "#{glyph view.policy} "
        view.write INSET, 0, Unicode.truncate(head, room, view.policy), paint

        left = room - Unicode.string_width(head, view.policy)
        return if left <= 0

        title = Unicode.truncate section.title, left, view.policy
        view.write INSET + Unicode.string_width(head, view.policy), 0, title, section.title_style
      end
    end

    # What the header says.
    getter title : String

    # What a collapsed header says against its right edge. Empty says nothing.
    property summary : String = ""

    # The ground and text of the header row.
    property header_style : Style

    # The title's style. The header's own style made bold, unless set.
    property title_style : Style

    # What runs when the section opens or closes, with the section.
    property on_toggle : Proc(Section, Nil)? = nil

    # What runs when the pointer moves over the header.
    property on_point : Proc(Nil)? = nil

    # The header row, which is this widget's first child.
    getter header : Header

    # What is under it, which is its second. The section's rows go in here.
    getter body : Panel

    # Whether the body is showing.
    getter? expanded : Bool = true

    def initialize(@title : String = "",
                   @header_style : Style = Style::DEFAULT.reverse,
                   title_style : Style? = nil,
                   body_padding : Layout::Padding = Layout::Padding.all(0))
      @title_style = title_style || @header_style.bold
      @direction = Layout::Direction::Column
      @width = Layout::Sizing.grow
      @height = Layout::Sizing.fit
      @header = Header.new
      @body = Panel.new width: Layout::Sizing.grow, height: Layout::Sizing.fit,
        padding: body_padding
      add @header
      add @body
    end

    # Opens or closes the body without telling `#on_toggle`.
    def expanded=(expanded : Bool) : Bool
      @expanded = expanded
      @body.hidden = !expanded
      expanded
    end

    # Opens a closed section or closes an open one, and tells `#on_toggle`.
    def toggle : Nil
      self.expanded = !@expanded
      @on_toggle.try &.call(self)
    end

    # The rows of the body that are drawn, top first. A collapsed section has
    # none.
    def rows : Array(Widget)
      return [] of Widget unless @expanded

      @body.children.reject &.hidden?
    end
  end
end
