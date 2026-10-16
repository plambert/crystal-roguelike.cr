require "../../crystal-roguelike"

module Roguelike::Ui
  # Which of the three panels has the focus, and how that shows.
  #
  # `Tab` moves it in the order map, info, log and round again. `Shift+Tab`
  # goes back. A click in a panel moves it there. A hidden info panel is
  # passed over.
  #
  # The ring takes no keys itself, and no widget takes the keyboard for it.
  # The game's keys reach the application's keymap whichever panel has the
  # focus, so the movement keys move the character from the info and log
  # panels too.
  class FocusRing
    # The panels, in the order `Tab` visits them.
    enum Panel
      Map
      Info
      Log
    end

    # The panel with the focus.
    getter current : Panel = Panel::Map

    def initialize(@screen : Screen)
    end

    # Moves the focus to the next panel. Answers that panel.
    def next : Panel
      step 1
    end

    # Moves the focus to the previous panel. Answers that panel.
    def previous : Panel
      step(-1)
    end

    # Moves the focus to *panel*. Answers the panel with the focus.
    #
    # A panel that is hidden keeps the focus where it is. So does the panel
    # that has it already, and its fade does not start again.
    def focus(panel : Panel) : Panel
      return @current if panel == @current || !shown?(panel)

      @current = panel
    end

    # Whether the map has the focus.
    def map? : Bool
      @current.map?
    end

    # Puts the focus back on the map when the panel that had it is gone.
    # `Play#fit` calls this after the screen is fitted.
    def fit : Nil
      return if shown? @current

      @current = Panel::Map
    end

    # The panel at *x*, *y* of the screen, or `nil` for a cell in none of
    # them. The rule beside the info panel counts as the info panel, since
    # it is that panel's scrollbar.
    def under(x : Int32, y : Int32) : Panel?
      return Panel::Map if within? @screen.map, x, y
      return Panel::Log if within? @screen.log, x, y
      return Panel::Info if within?(@screen.info, x, y) || within?(@screen.gutter, x, y)

      nil
    end

    private def within?(widget : Widgets::Widget, x : Int32, y : Int32) : Bool
      !widget.hidden? && widget.rect.contains?(x, y)
    end

    private def shown?(panel : Panel) : Bool
      !panel.info? || @screen.info?
    end

    private def step(by : Int32) : Panel
      order = Panel.values
      index = order.index!(@current)

      order.size.times do
        index = (index + by) % order.size
        return focus(order[index]) if shown? order[index]
      end

      @current
    end
  end
end
