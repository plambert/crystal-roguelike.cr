require "../../crystal-roguelike"

module Roguelike::Ui
  # An order a list of items can be shown in.
  #
  # Sorting changes only the order of the rows on the screen. Every item keeps
  # its letter, and nothing in the game changes.
  #
  # Members are only ever added at the end.
  enum ItemSort
    Name
    Weight
    Class

    # The orders a list of carried items offers, in the order the picker
    # shows them.
    def self.carried : Array(ItemSort)
      [Name, Weight, Class]
    end

    # The orders the pick-up list offers.
    def self.floor : Array(ItemSort)
      [Name, Class]
    end

    # What the picker calls this order.
    def label : String
      to_s.downcase
    end
  end

  class Play
    # The title of the menu that picks an order.
    SORT_TITLE = "Sort by"

    # The order each list of items was last sorted in, by the list's name.
    # A list with no entry keeps the order it comes in. This lasts for the
    # session and is not saved.
    @sorts = {} of String => ItemSort

    # The order the list named *list* is sorted in, or `nil` for none yet.
    def sort_of(list : String) : ItemSort?
      @sorts[list]?
    end

    # The positions of *items* in the order *list* is sorted in. Items that
    # sort the same keep the order they came in.
    private def sort_order(list : String, items : Array(Item)) : Array(Int32)
      order = (0...items.size).to_a
      sort = @sorts[list]?
      return order unless sort

      lore = @game.lore
      order.sort_by do |index|
        item = items[index]
        name = Naming.listed(lore, item).downcase
        case sort
        in .name?   then {0, name, index}
        in .weight? then {-item.weight, name, index}
        in .class?  then {Play.class_rank(item), name, index}
        end
      end
    end

    # Where the class *item* belongs to comes in `PACK_CLASSES`.
    def self.class_rank(item : Item) : Int32
      PACK_CLASSES.index(pack_class(item.kind.item_class)) || PACK_CLASSES.size
    end

    # *rows* with a heading before each class, when *list* is sorted by class
    # and the rows hold more than one class. *items* are what the rows show,
    # in the same order. *header* makes a heading row from its text.
    private def with_headers(list : String, rows : Array(R), items : Array(Item),
                             & : String -> R) : Array(R) forall R
      return rows unless @sorts[list]?.try(&.class?)

      classes = items.map { |item| Play.pack_class item.kind.item_class }
      return rows if classes.uniq.size < 2

      headed = [] of R
      last = nil
      rows.each_with_index do |row, index|
        name = classes[index]
        headed << yield name.capitalize unless name == last
        last = name
        headed << row
      end
      headed
    end

    # Binds the sort key on the item list that is up. The key puts up the
    # orders in *orders*. *again* puts the list back up afterward, with the
    # name of the page that was showing.
    private def offer_sort(list : String, orders : Array(ItemSort),
                           &again : String? -> Nil) : Nil
      labels = orders.map &.label
      offer_sort_key do
        page = @menu.page_name
        current = @sorts[list]?.try { |sort| orders.index sort }
        pick_sort(labels, current) do |index|
          @sorts[list] = orders[index] if index
          again.call page
        end
      end
    end

    # Binds the sort key on the menu that is up to run *open*.
    private def offer_sort_key(&open : -> Nil) : Nil
      key = TermBuf::Key.character Keys.sort_key(control_scheme)
      @menu.extra_keys = [{key, "sort the list", open}]
    end

    # Puts up the orders named *labels* in place of the list that is up, with
    # the one at *current* marked. Runs *picked* with the position of the
    # order picked, or `nil` for `Escape`.
    #
    # The menu takes the place of the list without closing it, so nothing the
    # list does on a choice or on `Escape` runs.
    private def pick_sort(labels : Array(String), current : Int32?,
                          &picked : Int32? -> Nil) : Nil
      @tooltip.hide
      entries = labels.map_with_index do |label, index|
        Widgets::Menu::Entry.new Widgets::Menu.letter(index), label,
          mark: index == current ? '*' : ' '
      end

      @menu.on_highlight = nil
      @menu.on_highlight_index = nil
      @menu.on_choose = nil
      @menu.on_choose_index = ->(index : Int32?) { picked.call index; nil }
      @menu.column_margin = Widgets::Menu::COLUMN_MARGIN
      @menu.show application, SORT_TITLE, entries
      @menu.select_index current if current
    end
  end
end
