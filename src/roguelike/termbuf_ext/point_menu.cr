require "termbuf-widgets"

# Extraction candidate: `TermBuf::Widgets::PointMenu`, for termbuf-widgets.cr.
#
# `DropdownMenu` hangs off a widget. A context menu hangs off a point, such
# as the cell a pointer went down on, and has to stay on the screen.
#
# This type is written in `TermBuf::Widgets` rather than in `Roguelike`.
# Extracting it is then a file move with no edits.
module TermBuf::Widgets
  # A `DropdownMenu` that opens beside a screen point.
  #
  #     menu.items.replace rows
  #     menu.on_choose = ->(index : Int32) { act index }
  #     menu.open_at app, x, y
  #
  # The menu is modal, so the keyboard stays inside it. A press outside takes
  # it down and goes no further, so the click that dismisses it does not also
  # act on whatever lay under it.
  class PointMenu < DropdownMenu
    # What runs with the index of the item chosen, after the menu is down.
    property on_choose : Proc(Int32, Nil)? = nil

    # What runs when the menu goes down without a choice.
    property on_dismiss : Proc(Nil)? = nil

    # Whether `#choose` is taking the menu down.
    @choosing : Bool = false

    def initialize(max_rows : Int32 = 12)
      super nil, [] of Item, max_rows: max_rows, modal: true
    end

    # Puts the menu up with its top left corner one cell right of *x*, *y*.
    #
    # A menu that would run off an edge of the screen is moved back inside
    # it. The highlight starts on the first item that can be chosen.
    def open_at(app : App, x : Int32, y : Int32) : self
      screen = app.tree.screen
      policy = app.tree.policy
      width = wanted_width(policy) + 2
      height = Math.min(@items.size, @list.max_rows) + 2

      left = (x + 1).clamp screen.x, Math.max(screen.right - width, screen.x)
      top = y.clamp screen.y, Math.max(screen.bottom - height, screen.y)
      anchor_at Layout::AttachPoint::LeftTop, Layout::AttachPoint::LeftTop,
        dx: left, dy: top

      @list.select 0
      open app
    end

    # Chooses the highlighted item, if it can be chosen.
    #
    # The menu is down before `#on_choose` runs, so the choice can put up
    # another box.
    def choose : Nil
      index = selected
      item = current
      return if item.nil? || !item.enabled

      @choosing = true
      close
      @choosing = false
      @on_choose.try &.call index
    end

    # Takes the menu down. A close that is not a choice runs `#on_dismiss`.
    def close : Nil
      was = open?
      super
      @on_dismiss.try &.call if was && !@choosing
    end

    # Takes the press that dismissed the menu, so it goes no further.
    def handle(event : Event, context : Context) : Nil
      was = open?
      super
      return if !was || open? || context.consumed?

      context.consume if event.is_a?(Events::Mouse) && event.action.press?
    end

    # How many cells the widest item wants.
    private def wanted_width(policy : Unicode::WidthPolicy) : Int32
      @items.max_of? do |item|
        wanted = Unicode.string_width item.label, policy
        hint = item.hint
        wanted += DropdownMenu::List::GAP + Unicode.string_width(hint, policy) if hint
        wanted
      end || 0
    end
  end
end
