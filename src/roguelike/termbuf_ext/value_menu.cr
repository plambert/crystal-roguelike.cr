require "termbuf-widgets"
require "./menu"
require "./navigation"

module TermBuf::Widgets
  # A typed selection adapter over the shared menu layout.
  class ValueMenu(T)
    # One selectable value and its presentation.
    record Entry(U), value : U, text : String, enabled : Bool = true,
      mark : Char? = nil, mark_style : Style? = nil,
      tail : Char? = nil, tail_style : Style? = nil,
      shortcut : Char? = nil, disabled_reason : String? = nil

    # The menu that draws and navigates the rows.
    getter menu : Menu

    # The bindings and row presentation used by the adapter.
    getter navigation : Navigation

    # What runs when a value is chosen.
    property on_choose : Proc(T, Nil)? = nil

    # What runs when the menu is canceled.
    property on_back : Proc(Nil)? = nil

    # What runs when the highlighted value changes.
    property on_highlight : Proc(T?, Nil)? = nil

    private getter value_pages : Array(Array(Entry(T))) = [] of Array(Entry(T))

    def initialize(@menu : Menu = Menu.new,
                   @navigation : Navigation = Navigation.selectable)
      @menu.navigation = @navigation
      own_callbacks
    end

    # Takes ownership of the shared menu's value callbacks after another
    # adapter has used it.
    def claim : Nil
      @menu.on_choose = nil
      @menu.on_highlight = nil
      own_callbacks
    end

    private def own_callbacks : Nil
      @menu.on_choose_index = ->(index : Int32?) do
        if index
          entry = @value_pages[@menu.page]?.try(&.[index])
          @on_choose.try &.call entry.value if entry
        else
          @on_back.try &.call
        end
        nil
      end
      @menu.on_highlight_index = ->(index : Int32?) do
        @on_highlight.try &.call value_at(index)
        nil
      end
    end

    # Sets the navigation contract on the shared menu.
    def navigation=(navigation : Navigation) : Navigation
      @navigation = navigation
      @menu.navigation = navigation
      navigation
    end

    # The currently highlighted value, or `nil` for an empty page.
    def selected_value : T?
      value_at @menu.selected_index
    end

    # The currently highlighted row index, or `nil` for an empty page.
    def selected_index : Int32?
      @menu.selected_index
    end

    # Moves the highlight to *index* and brings it into view.
    def select_index(index : Int32) : Nil
      @menu.select_index index
    end

    # Restores a row and, when supplied, a page before it.
    def restore_selection(index : Int32, page : Int32? = nil) : Nil
      @menu.restore_selection index, page: page
    end

    # Restores the row carrying *value*, keeping its semantic identity across
    # a rebuilt list.
    def restore_value(value : T, page : Int32? = nil) : Bool
      pages = @value_pages
      if wanted_page = page
        index = pages[wanted_page]?.try { |entries| entries.index { |entry| entry.value == value } }
        if index
          @menu.restore_selection index, page: wanted_page
          return true
        end
      else
        pages.each_with_index do |entries, page_index|
          index = entries.index { |entry| entry.value == value }
          next unless index

          @menu.restore_selection index, page: page_index
          return true
        end
      end

      false
    end

    # Shows *entries* under *title*.
    def show(app : App, title : String?, entries : Enumerable(Entry(T))) : Nil
      claim
      @value_pages = [entries.to_a]
      rows = @value_pages[0].map { |entry| menu_entry(entry) }
      @menu.show app, title, rows
    end

    # Shows *pages* under *title*, opening on *page*.
    def show(app : App, title : String?, pages : Array({String, Array(Entry(T))}),
             page : Int32) : Nil
      claim
      @value_pages = pages.map(&.[1])
      rows = pages.map do |name, entries|
        {name, entries.map { |entry| menu_entry(entry) }}
      end
      @menu.show app, title, rows, page
    end

    # Takes the menu down without a choice.
    def cancel : Nil
      @menu.cancel
    end

    # Builds a row for this adapter's value type.
    def entry(value : T, text : String, enabled : Bool = true,
              mark : Char? = nil, mark_style : Style? = nil,
              tail : Char? = nil, tail_style : Style? = nil,
              shortcut : Char? = nil,
              disabled_reason : String? = nil) : Entry(T)
      Entry(T).new value, text, enabled, mark, mark_style, tail, tail_style,
        shortcut, disabled_reason
    end

    private def value_at(index : Int32?) : T?
      return unless index

      @value_pages[@menu.page]?.try(&.[index]).try(&.value)
    end

    private def menu_entry(entry : Entry(T)) : Menu::Entry
      Menu::Entry.new '\0', entry.text, entry.enabled,
        entry.mark, entry.mark_style, entry.tail, entry.tail_style,
        entry.shortcut, entry.disabled_reason
    end
  end
end
