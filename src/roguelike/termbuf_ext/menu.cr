require "termbuf-widgets"

# Extraction candidate: `TermBuf::Widgets::Menu`, for termbuf-widgets.cr.
#
# `SelectionList` narrows a list by what is typed. `DropdownMenu::Item#hint`
# draws a key against the right edge and, by its own documentation, does not
# bind it.
#
# A list addressed by letter is a different thing. `a - a blessed +0 dagger`
# is how every roguelike shows an inventory, and how `dialog(1)` and `mutt`
# show a menu. One keystroke picks one row. Nothing is typed and nothing is
# narrowed.
#
# This type is written in `TermBuf::Widgets` rather than in `Roguelike`.
# Extracting it is then a file move with no edits.
#
# Three questions remain open:
#
# * Should the keys be assigned here or by the caller? The caller assigns them
#   now, because an inventory letter belongs to the item for as long as it is
#   carried and the menu sees the list only while it is up.
# * Should a menu page when there are more rows than fit? It scrolls now, with
#   the arrows and the page keys. A roguelike pages and offers `a` to `z` per
#   page. Paging needs a second set of letters, which the caller assigns.
# * Should an answer arrive as a `Message`? `#on_choose` runs as soon as a key
#   arrives, the same way `Prompt#on_answer` does.
# * Should the sideways scroll have a scrollbar? It has no mark of its own
#   now. A row cut at the right edge is the only sign there is more.
module TermBuf::Widgets
  # A list of rows, each answered by one keystroke.
  #
  #     menu.on_choose = ->(key : Char?) { use key if key }
  #     menu.show app, "Inventory", entries
  #
  # A menu is an `Overlay`. It draws a box in the middle of the screen and
  # dims everything behind it. It is modal, so a key nothing in it claims
  # stops there.
  #
  # A letter picks its row. The arrows and the page keys move a highlight and
  # `Enter` picks the highlighted row. `Escape` answers nothing.
  class Menu < Overlay
    # One row.
    #
    # *mark* replaces the `-` between the key and the text. A list of items
    # puts the blessing there. The blessing is then one column to read down
    # rather than a word at the front of every name. `nil` keeps the `-`.
    #
    # *tail* is drawn against the right edge of the row, past the text. A
    # list of items puts the slot there.
    record Entry, key : Char, text : String, enabled : Bool = true,
      mark : Char? = nil, mark_style : Style? = nil,
      tail : Char? = nil, tail_style : Style? = nil

    # The letters a menu hands out when the caller has none of its own.
    LETTERS = ('a'..'z').to_a + ('A'..'Z').to_a

    # How many cells the box keeps clear beyond its title.
    #
    # The title is drawn in the top edge of the border with a space on each
    # side and a corner beyond that. A box sized to the title exactly has the
    # last letter or two of it cut.
    TITLE_SLACK = 2

    # The letter for the row at *index*.
    def self.letter(index : Int32) : Char
      LETTERS[index % LETTERS.size]
    end

    # Which row *letter* is, counting from zero.
    def self.index(letter : Char) : Int32
      LETTERS.index(letter) || -1
    end

    # The most rows shown at once, over and above what the screen allows.
    # More than this scrolls.
    #
    # The screen bounds the box as well: a menu leaves `#row_margin` rows
    # clear above and below itself. This is a second ceiling, for a caller
    # that wants a short list on a tall screen. It is no ceiling at all by
    # default.
    property max_rows : Int32 = Int32::MAX

    # How many cells a menu leaves clear to its left and to its right unless
    # a caller asks for more.
    COLUMN_MARGIN = 10

    # How many cells a menu leaves clear to its left and to its right.
    #
    # The box grows to fit its widest row until it reaches this. Past that the
    # rows scroll sideways.
    property column_margin : Int32 = COLUMN_MARGIN

    # How many rows a menu leaves clear above and below itself.
    property row_margin : Int32 = 3

    # How narrow a menu may be, whatever the screen is.
    MINIMUM_WIDTH = 20

    # How short it may be: one row and the border around it.
    MINIMUM_HEIGHT = 3

    # How many cells the pointer, the key and the mark take at the start of a
    # row.
    #
    # `\u27EA a - ` is six cells. The rows scroll under the gutter and the
    # gutter does not move. The key a person has to press stays where they
    # can read it.
    GUTTER = 6

    # Which of those cells each piece is drawn in.
    POINT = 0
    KEY   = 2
    MARK  = 4

    # What goes in the mark cell for a row with no mark of its own.
    SEPARATOR = '-'

    # How many cells are kept clear at the right edge for `Entry#tail`.
    TAIL = 2

    # How many cells are kept clear at the right edge for the mark facing
    # the pointer. The cells are kept clear on every row, so a row does not
    # move when the highlight arrives on it.
    MIRROR = 2

    # How many cells the rows have been scrolled sideways.
    getter offset : Int32 = 0

    # How many cells wide the rows are drawn, as `#fit_into` last worked it
    # out.
    #
    # This is not read off the drawn rectangle. A menu sized again for a
    # screen that changed has not been laid out at the new size yet, and the
    # rectangle still holds the old one.
    getter room : Int32 = 0

    # What a row that cannot be picked is drawn in.
    property disabled_style : Style = Style::DEFAULT.faint

    # What the key at the start of a row is drawn in.
    property key_style : Style = Style::DEFAULT.bold

    # The two marks on the highlighted row. One is at the near edge and one
    # is at the far edge.
    #
    # `nil` for either leaves that cell blank. The cells are kept clear
    # whether or not anything goes in them.
    property pointer : Char? = '\u27EA'
    property pointed : Char? = '\u27EB'

    # What both marks are drawn in.
    property pointer_style : Style = Style::DEFAULT

    # What runs when a row is picked.
    #
    # The argument is the key. It is `nil` when the person pressed `Escape`.
    property on_choose : Proc(Char?, Nil)? = nil

    # What runs when the highlight moves, with the row it is on now.
    #
    # The arrows move it, and so does the pointer crossing a row. It runs once
    # when the menu goes up, with the first row. A caller hangs a box of
    # detail off it.
    property on_highlight : Proc(Entry?, Nil)? = nil

    # The rows, in the order they are drawn.
    getter entries : Array(Entry) = [] of Entry

    # The list the rows are drawn through.
    getter list : Content

    # The list inside a menu.
    #
    # `VirtualList` holds no widget per row, so it cannot be asked how wide
    # its content is: it answers one cell whatever it holds. A menu measures
    # its rows when it goes up and writes the width here, which is what lets
    # the box around it grow to fit them.
    class Content < VirtualList(Entry)
      # How wide the widest row is, in cells.
      property widest : Int32 = 1

      # What runs when the highlight moves, or when the window scrolls under
      # it, with the row the highlight is on.
      #
      # Both count, because a box hung off a row has to follow the row up and
      # down the screen. Nothing runs when a key or a pointer picks the row
      # the highlight was already on.
      property on_select : Proc(Int32, Nil)? = nil

      # What runs when a button is pressed on a row.
      #
      # The highlight has already moved to that row, so whatever this does
      # acts on the row that was clicked.
      property on_click : Proc(Nil)? = nil

      def intrinsic_width(policy : Unicode::WidthPolicy) : Layout::Intrinsic
        Layout::Intrinsic.new 1, Math.max(@widest, 1)
      end

      def select(index : Int32) : Nil
        before = @selected
        super
        moved unless @selected == before
      end

      def scroll_by(dx : Int32, dy : Int32) : Nil
        before = @scroll
        super
        moved unless @scroll == before
      end

      # Says the highlight is somewhere else on the screen than it was.
      private def moved : Nil
        @on_select.try &.call @selected
      end

      # Puts the highlight on the row the pointer is over, and picks the row
      # a button goes down on.
      #
      # A row is not a widget, so there is nothing under the pointer to ask.
      # The row is worked out from how far down the list the report landed.
      #
      # A bare report is not claimed. Whatever is tracking where the pointer
      # is has to hear about every one, including the ones that land here. A
      # press is claimed, because it has been answered.
      def handle(event : Event, context : Context) : Nil
        return unless event.is_a? Events::Mouse

        if scroll_wheel event
          context.consume
          return
        end

        row = scroll_y + event.y - content.y
        return unless row >= 0 && row < @rows.size

        self.select row
        return unless Content.clicked? event

        context.consume
        @on_click.try &.call
      end

      # Whether *event* is a button going down on a row.
      #
      # The left button and nothing else. A release is not a second answer to
      # a press, and the middle and right buttons mean nothing here.
      def self.clicked?(event : Events::Mouse) : Bool
        event.button.left? && event.action.press?
      end
    end

    def initialize(z : Int32 = Z::DIALOG, style : Style? = nil)
      @list = Content.new Rows.of([] of Entry),
        width: Layout::Sizing.fit(min: 1),
        height: Layout::Sizing.fit(min: 1)

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @width = Layout::Sizing.fit(min: MINIMUM_WIDTH)
      @height = Layout::Sizing.fit(min: MINIMUM_HEIGHT)
      @border = Border.rounded
      @style = style
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      @list.on_draw = ->(view : View, _index : Int32, entry : Entry, chosen : Bool, lit : Bool) do
        draw_entry view, entry, chosen && lit
        nil
      end

      @list.on_select = ->(_index : Int32) { highlighted; nil }

      # Clicking a row does what typing its letter does. The pointer has
      # already put the highlight on it.
      @list.on_click = -> { pick_highlighted; nil }

      add @list
    end

    # Whether a menu is up.
    def showing? : Bool
      open?
    end

    # Puts *entries* up on *app* under *title*.
    #
    # A menu already up is replaced. The scope it pushed is kept.
    def show(app : App, title : String?, entries : Enumerable(Entry)) : Nil
      @entries = entries.to_a
      @offset = 0
      @list.rows = Rows.of @entries
      @list.select 0

      self.title = title
      fit_into app.tree.screen, app.tree.policy
      self.keymap = choices

      open app
      highlighted
    end

    # Tells `#on_highlight` which row the highlight is on now.
    private def highlighted : Nil
      @on_highlight.try &.call @list.current
    end

    # How many cells there are between the left edge of the rows and the left
    # edge of the menu.
    #
    # The border and the padding. Something hung off a row by its own left
    # edge has to clear both of them as well as the row.
    def gutter : Int32
      inset.left
    end

    # Sizes the box to its rows and to the screen.
    #
    # The box grows to fit its widest row and to hold every row at once. It
    # stops at the screen less `#column_margin` cells on each side and
    # `#row_margin` rows above and below. What does not fit then scrolls:
    # sideways with the left and right keys, and down with the arrows and the
    # page keys.
    #
    # The title is measured too. It is drawn in the top edge of the border,
    # and a box narrower than its own title has the title cut instead.
    private def fit_into(screen : Rect, policy : Unicode::WidthPolicy) : Nil
      widest_row = @entries.max_of? { |found| GUTTER + Menu.cells(found.text, policy) } || 0
      widest_row += TAIL if @entries.any? &.tail
      widest_row += MIRROR

      @list.widest = Math.max widest_row, Menu.cells(title, policy) + TITLE_SLACK

      widest = Math.max screen.width - 2 * @column_margin, MINIMUM_WIDTH
      tallest = Math.max screen.height - 2 * @row_margin, MINIMUM_HEIGHT

      self.width = Layout::Sizing.fit min: MINIMUM_WIDTH, max: widest
      self.height = Layout::Sizing.fit min: MINIMUM_HEIGHT, max: tallest

      @list.height = Layout::Sizing.fit min: 1,
        max: Math.max(Math.min(@entries.size, @max_rows), 1)

      @room = Math.min @list.widest, Math.max(widest - inset.horizontal, 0)
    end

    # Sizes the box again for a screen that has changed size.
    #
    # A menu that was up when the terminal was resized keeps the bounds the
    # old screen gave it otherwise. Those bounds may be wider or taller than
    # the screen now is.
    def refit(screen : Rect, policy : Unicode::WidthPolicy) : Nil
      return unless showing?

      fit_into screen, policy
      scroll_by 0
    end

    # How many cells *text* takes under *policy*. Nothing takes none.
    def self.cells(text : String?, policy : Unicode::WidthPolicy) : Int32
      return 0 if text.nil? || text.empty?

      Layout::TextMeasure.measure(text, policy).width
    end

    # How many cells of a row are past the right edge of the box.
    def hidden : Int32
      Math.max @list.widest - @room, 0
    end

    # Moves the rows *cells* sideways. A negative number moves them back.
    #
    # The rows stop where the widest one ends. There is nothing past it to
    # look at.
    def scroll_by(cells : Int32) : Nil
      @offset = (@offset + cells).clamp 0, hidden
    end

    # The title in the border, without the spaces around it.
    def title : String?
      @border.try(&.title).try(&.strip)
    end

    # :ditto:
    def title=(title : String?) : String?
      held = @border || Border.rounded
      self.border = held.with_title(title ? " #{title} " : nil)
      title
    end

    # Takes the menu down without a choice. Runs `#on_choose` with `nil`.
    def cancel : Nil
      return unless open?

      finish nil
    end

    # The keyboard lands on the list, which the arrows move.
    def focusable? : Bool
      false
    end

    # The row *key* picks, or `nil` for a key nothing is under.
    def entry(key : Char) : Entry?
      @entries.find { |found| found.key == key }
    end

    # The bindings a menu answers.
    private def choices : Bindings
      map = Bindings.new

      @entries.each do |found|
        next unless found.enabled

        map.bind Key.character(found.key), found.text,
          ->(_context : Context) { finish found.key; nil }
      end

      map.bind Key.named(Key::Name::Escape), "leave the menu",
        ->(_context : Context) { finish nil; nil }
      map.bind Key.named(Key::Name::Enter), "pick the highlighted row",
        ->(_context : Context) { pick_highlighted; nil }
      map.bind Key.named(Key::Name::Left), "the rows sideways, back",
        ->(_context : Context) { scroll_by -1; nil }
      map.bind Key.named(Key::Name::Right), "the rows sideways, on",
        ->(_context : Context) { scroll_by 1; nil }

      map
    end

    # Picks whatever the highlight is on.
    private def pick_highlighted : Nil
      found = @list.current
      return unless found && found.enabled

      finish found.key
    end

    # Draws one row as `\u27EA a - what it is        \u27EB`.
    #
    # The text is written first. Everything else is written over it. A row
    # scrolled sideways slides its text under the gutter and under the marks
    # at the far edge. The key and the marks stay where they are.
    #
    # The highlight covers the text. The color of a mark is part of its
    # meaning. Reversing the gutter would invert that color.
    private def draw_entry(view : View, entry : Entry, lit : Bool) : Nil
      plain = entry.enabled ? Style::DEFAULT : @disabled_style

      view.write GUTTER - @offset, 0, entry.text, lit ? plain.reverse : plain

      view.write 0, 0, " " * GUTTER, plain
      mark = entry.mark || SEPARATOR
      view.write KEY, 0, entry.key.to_s, entry.enabled ? @key_style : plain
      view.write MARK, 0, mark.to_s, entry.mark_style || plain

      draw_marks view, entry, lit, plain
    end

    # Draws the pointer, the mark facing it, and the row's own tail.
    private def draw_marks(view : View, entry : Entry, lit : Bool,
                           plain : Style) : Nil
      near = lit ? @pointer : nil
      far = lit ? @pointed : nil

      view.write POINT, 0, near ? near.to_s : " ", @pointer_style

      edge = view.width - 1
      return if edge < GUTTER

      view.write edge, 0, far ? far.to_s : " ", @pointer_style

      tail = entry.tail
      return unless tail
      return if edge - MIRROR < GUTTER

      view.write edge - MIRROR, 0, tail.to_s, entry.tail_style || plain
    end

    # Takes the menu down. Runs `#on_choose` with *key*.
    #
    # The keymap goes with it. A closed menu that kept its bindings would
    # answer again on the next press of the same key, before the next frame
    # rebuilt the focus ring.
    private def finish(key : Char?) : Nil
      self.keymap = nil
      close

      @on_choose.try &.call(key)
    end
  end
end
