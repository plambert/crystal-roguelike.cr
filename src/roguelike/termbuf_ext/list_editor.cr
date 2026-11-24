require "termbuf-widgets"

# Extraction candidate: `TermBuf::Widgets::ListEditor`, for termbuf-widgets.cr.
#
# `SelectionList` chooses among rows that are given. `Form` edits values that
# each have a row of their own. Neither lets a person change which rows there
# are or the order they come in.
#
# This type is written in `TermBuf::Widgets` rather than in `Roguelike`.
# Extracting it is then a file move with no edits.
module TermBuf::Widgets
  # A list a person puts in order: rows are added, removed, edited and moved
  # up and down.
  #
  #     editor = ListEditor(String).new ["bread", "cheese"]
  #     editor.label = ->(item : String) { item }
  #     editor.on_new = -> { "something" }
  #     editor.on_change = ->(items : Array(String)) { save items; nil }
  #
  #     1. bread
  #     2. cheese
  #
  # The editor knows nothing about what a row is. `#label` gives the words of
  # a row, and `#tail` gives words drawn against its right edge. `#on_new`
  # makes the row `+` adds, and `#on_edit` is told which row `Enter` was
  # pressed on, so the caller opens whatever edits one.
  #
  # `Up` and `Down` move the highlight. `[` and `]` move the row itself.
  # `+` and `Insert` add a row after the highlight, and `-`, `Delete` and
  # `Backspace` remove the row. `#on_change` runs after each of those with
  # the rows as they now stand.
  #
  # `Up` on the first row and `Down` on the last run `#on_overrun`, so a
  # caller with something above or below the list moves the keyboard there.
  class ListEditor(T) < Widget
    include Interactive

    # What is shown when there are no rows.
    EMPTY = "Nothing yet. Press + to add."

    # The rows, in order.
    getter items : Array(T)

    # The words of a row.
    property label : Proc(T, String) = ->(item : T) { item.to_s }

    # The words drawn against the right edge of a row, or `nil` for none.
    property tail : Proc(T, String)? = nil

    # Makes the row `#add` puts in. `nil` from it adds nothing. With no
    # proc here nothing can be added.
    property on_new : Proc(T?)? = nil

    # Runs when a row is to be edited, with where it is and what it is.
    property on_edit : Proc(Int32, T, Nil)? = nil

    # Runs after the rows change, with the rows as they now stand.
    property on_change : Proc(Array(T), Nil)? = nil

    # Runs when the highlight is asked to go past the first row, with -1, or
    # past the last, with 1.
    property on_overrun : Proc(Int32, Nil)? = nil

    # The most rows the list takes, or `nil` for any number.
    property limit : Int32? = nil

    # Whether each row starts with its place in the list.
    property? numbered : Bool = true

    # Whether a row just added is handed to `#on_edit`.
    property? edits_new : Bool = true

    # What a list with no rows says.
    getter empty_text : String = EMPTY

    # The highlighted row while the list has the keyboard.
    property selected_style : Style = Style::DEFAULT.reverse

    # Every other row.
    property row_style : Style = Style::DEFAULT

    # The window the rows are drawn in. It is what takes the keyboard.
    getter list : VirtualList(T)

    # The line a list with no rows shows.
    @notice : Label

    def initialize(items : Array(T) = [] of T,
                   width : Layout::Sizing = Layout::Sizing.grow,
                   height : Layout::Sizing = Layout::Sizing.fit)
      @items = items.dup
      @width = width
      @height = height
      @direction = Layout::Direction::Column

      held = @items
      @notice = Label.new @empty_text
      @list = VirtualList(T).new Rows(T).from(-> { held.size },
        ->(index : Int32) { held[index] }), height: Layout::Sizing.fit
      @list.on_draw = ->(view : View, index : Int32, item : T, chosen : Bool, lit : Bool) do
        paint view, index, item, chosen && lit
      end
      @list.keymap = moving

      add @notice, @list
      self.keymap = editing
      settle
    end

    # Puts *items* in place of the rows there were.
    def items=(items : Array(T)) : Array(T)
      @items.clear
      @items.concat items
      settle
      @items
    end

    def empty_text=(text : String) : String
      @notice.text = text
      @empty_text = text
    end

    # Which row is highlighted. Zero for a list with no rows.
    def selected : Int32
      @list.selected
    end

    # The highlighted row, or `nil` for a list with no rows.
    def current : T?
      @list.current
    end

    # Highlights the row at *index*, or the nearest there is.
    def select(index : Int32) : Nil
      @list.select index
    end

    # Moves the highlight *step* rows. Going past either end runs
    # `#on_overrun` and leaves the highlight where it was.
    def step(step : Int32) : Nil
      wanted = selected + step
      if @items.empty? || !(0...@items.size).includes?(wanted)
        @on_overrun.try &.call(step.sign)
        return
      end

      @list.select wanted
    end

    # Whether another row fits.
    def room? : Bool
      limit = @limit
      limit.nil? || @items.size < limit
    end

    # Adds the row `#on_new` makes after the highlighted row, and highlights
    # it. Answers where it went, or `nil` when nothing was added.
    def add : Int32?
      return unless room?

      made = @on_new.try &.call
      return if made.nil?

      at = @items.empty? ? 0 : selected + 1
      @items.insert at, made
      settle
      @list.select at
      changed
      @on_edit.try &.call(at, made) if edits_new?
      at
    end

    # Takes the highlighted row out. Answers it, or `nil` for a list with no
    # rows.
    def remove : T?
      return if @items.empty?

      at = selected
      gone = @items.delete_at at
      settle
      @list.select Math.min(at, @items.size - 1)
      changed
      gone
    end

    # Moves the highlighted row *step* places, and the highlight with it.
    # Answers whether it moved.
    def move(step : Int32) : Bool
      from = selected
      to = from + step
      return false unless (0...@items.size).includes?(from) && (0...@items.size).includes?(to)

      @items.swap from, to
      @list.select to
      changed
      true
    end

    # Puts *item* in place of the row at *index*.
    def replace(index : Int32, item : T) : Nil
      return unless (0...@items.size).includes? index
      return if @items[index] == item

      @items[index] = item
      @list.remeasure
      changed
    end

    # Hands the highlighted row to `#on_edit`.
    def edit : Nil
      item = current
      @on_edit.try &.call(selected, item) unless item.nil?
    end

    # Puts the keyboard on the list.
    def focus(app : App) : Nil
      app.focus.focus @list
    end

    # A click on a row highlights it and takes the keyboard.
    def handle(event : Event, context : Context) : Nil
      return unless event.is_a? Events::Mouse

      clicked event, context do
        context.focus.focus @list
        box = @list.content
        row = event.y - box.y + @list.scroll
        @list.select row if (0...box.height).includes?(event.y - box.y) && row < @items.size
      end
    end

    # Shows the notice in place of an empty list, and keeps the highlight on
    # a row there is.
    private def settle : Nil
      @notice.hidden = !@items.empty?
      @list.remeasure
      @list.select selected
      invalidate_layout
    end

    private def changed : Nil
      invalidate_layout
      @on_change.try &.call(@items.dup)
    end

    # The keys that move the highlight.
    private def moving : Bindings
      Bindings.build do |map|
        map.bind Key.parse("Up"), "the row before", ->(_context : Context) { step(-1) }
        map.bind Key.parse("Down"), "the row after", ->(_context : Context) { step 1 }
        map.bind Key.parse("PageUp"), "a window back",
          ->(_context : Context) { @list.select selected - @list.page }
        map.bind Key.parse("PageDown"), "a window on",
          ->(_context : Context) { @list.select selected + @list.page }
        map.bind Key.parse("Home"), "the first row", ->(_context : Context) { @list.select 0 }
        map.bind Key.parse("End"), "the last row",
          ->(_context : Context) { @list.select @items.size - 1 }
      end
    end

    # The keys that change the rows.
    private def editing : Bindings
      Bindings.build do |map|
        ["Enter", "Space"].each do |key|
          map.bind Key.parse(key), "edit this row", ->(_context : Context) { edit }
        end
        ["+", "Insert"].each do |key|
          map.bind Key.parse(key), "add a row after this one", ->(_context : Context) { add; nil }
        end
        ["-", "Delete", "Backspace"].each do |key|
          map.bind Key.parse(key), "remove this row", ->(_context : Context) { remove; nil }
        end
        map.bind Key.parse("["), "move this row up", ->(_context : Context) { move(-1); nil }
        map.bind Key.parse("]"), "move this row down", ->(_context : Context) { move 1; nil }
      end
    end

    # Draws one row. *lit* says it is highlighted and the list has the
    # keyboard.
    private def paint(view : View, index : Int32, item : T, lit : Bool) : Nil
      style = lit ? @selected_style : @row_style
      view.fill Rect.new(0, 0, view.width, 1), ' ', style

      ending = @tail.try &.call(item)
      taken = ending ? Unicode.string_width(ending, view.policy) + 1 : 0
      taken = 0 if taken >= view.width
      head = numbered? ? "#{(index + 1).to_s.rjust @items.size.to_s.size}. " : ""
      text = Unicode.ellipsize "#{head}#{@label.call item}", view.width - taken, "…", view.policy

      view.write 0, 0, text, style
      view.write view.width - taken + 1, 0, ending, style if ending && taken > 0
    end
  end
end
