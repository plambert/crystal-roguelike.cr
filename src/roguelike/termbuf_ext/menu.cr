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
    record Entry, key : Char, text : String, enabled : Bool = true

    # The letters a menu hands out when the caller has none of its own.
    LETTERS = ('a'..'z').to_a + ('A'..'Z').to_a

    # The letter for the row at *index*.
    def self.letter(index : Int32) : Char
      LETTERS[index % LETTERS.size]
    end

    # Which row *letter* is, counting from zero.
    def self.index(letter : Char) : Int32
      LETTERS.index(letter) || -1
    end

    # The most rows shown at once. More than this scrolls.
    property max_rows : Int32 = 14

    # What a row that cannot be picked is drawn in.
    property disabled_style : Style = Style::DEFAULT.faint

    # What the key at the start of a row is drawn in.
    property key_style : Style = Style::DEFAULT.bold

    # What runs when a row is picked.
    #
    # The argument is the key. It is `nil` when the person pressed `Escape`.
    property on_choose : Proc(Char?, Nil)? = nil

    # The rows, in the order they are drawn.
    getter entries : Array(Entry) = [] of Entry

    # The list the rows are drawn through.
    getter list : VirtualList(Entry)

    def initialize(z : Int32 = Z::DIALOG, style : Style? = nil)
      @list = VirtualList(Entry).new Rows.of([] of Entry),
        width: Layout::Sizing.grow,
        height: Layout::Sizing.fit(min: 1)

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @width = Layout::Sizing.fit(min: 20)
      @height = Layout::Sizing.fit
      @border = Border.rounded
      @style = style
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      @list.on_draw = ->(view : View, _index : Int32, entry : Entry, chosen : Bool, lit : Bool) do
        draw_entry view, entry, chosen && lit
        nil
      end

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
      @list.rows = Rows.of @entries
      @list.select 0
      @list.height = Layout::Sizing.fit(min: 1,
        max: Math.max(Math.min(@entries.size, @max_rows), 1))

      self.title = title
      self.keymap = choices

      open app
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

      map
    end

    # Picks whatever the highlight is on.
    private def pick_highlighted : Nil
      found = @list.current
      return unless found && found.enabled

      finish found.key
    end

    # Draws one row as `a - what it is`.
    private def draw_entry(view : View, entry : Entry, lit : Bool) : Nil
      plain = entry.enabled ? Style::DEFAULT : @disabled_style
      plain = plain.reverse if lit

      view.write 0, 0, "#{entry.key}", entry.enabled ? @key_style : plain
      view.write 1, 0, " - #{entry.text}", plain
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
