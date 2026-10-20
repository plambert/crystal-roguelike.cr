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
  #
  # A focused info or log panel has a tinted ground. It fades from
  # `Palette.focus_flash` to `Palette.focus_ground` when `Motion.on?`, and
  # takes the gray at once otherwise. The map has no tint. The rule beside
  # the focused panel is drawn in `Palette.focus_rule`. For the info panel
  # that is the rule on its right. For the log it is the rule above it. For
  # the map it is both of those, since the map sits between them.
  class FocusRing
    # The panels, in the order `Tab` visits them.
    enum Panel
      Map
      Info
      Log
    end

    # The panel with the focus.
    getter current : Panel = Panel::Map

    # The fading ground the focused panel is drawn on.
    getter tint : Widgets::Tint

    # The application the fade arms its timers on. `nil` draws the end of
    # the fade at once.
    property app : Widgets::App? = nil

    # What runs when the focus moves, given the panel that had it and the
    # panel that has it now.
    property on_change : Proc(Panel, Panel, Nil)? = nil

    def initialize(@screen : Screen)
      @tint = Widgets::Tint.new Palette.focus_flash, Palette.focus_ground
      show
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

      moved panel
      panel
    end

    # Whether the map has the focus.
    def map? : Bool
      @current.map?
    end

    # Puts the focus back on the map when the panel that had it is gone.
    # `Play#fit` calls this after the screen is fitted.
    def fit : Nil
      return if shown? @current

      moved Panel::Map
    end

    private def moved(panel : Panel) : Nil
      was = @current
      @current = panel
      show
      @on_change.try &.call(was, panel)
    end

    # The panel at *x*, *y* of the screen, or `nil` for a cell in none of
    # them. The rule beside the info panel counts as the info panel, since
    # it is that panel's scrollbar.
    def under(x : Int32, y : Int32) : Panel?
      return Panel::Map if within? @screen.map, x, y
      return Panel::Log if within? @screen.log, x, y
      return Panel::Info if within?(@screen.info_panel, x, y) || within?(@screen.gutter, x, y)

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

    # Draws the focus where it now is.
    private def show : Nil
      tinted = case @current
               in .info? then @screen.info_panel
               in .log?  then @screen.log
               in .map?  then nil
               end

      tinted ? @tint.apply(tinted, @app, Motion.on?) : @tint.clear

      @screen.gutter.style = @current.log? ? nil : Palette.focus_rule
      @screen.rule.style = @current.info? ? nil : Palette.focus_rule
    end
  end
end
