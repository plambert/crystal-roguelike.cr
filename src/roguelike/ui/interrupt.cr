module Roguelike::Ui
  # Something that holds the keyboard and answers every key the same way.
  #
  # A run is drawn a step at a time on a timer. A key pressed part way
  # through stops it rather than doing what it usually does, and this is what
  # takes the key. It draws nothing and occupies no cells: it is in the focus
  # stack rather than in the widget tree.
  #
  # `Focus::Scope` gathers focusable widgets from its own root outward, so a
  # scope rooted here holds one widget, and `Router` reads no keymap at all
  # while it is on top. Every binding the application has is out of reach
  # until it lets go.
  class Interrupt < Widgets::Widget
    # What to run when a key arrives.
    property on_key : Proc(Nil)? = nil

    # Whether it is holding the keyboard.
    getter? holding : Bool = false

    # The scope it pushed.
    @scope : Widgets::Focus::Scope? = nil

    def initialize
      @width = Layout::Sizing.fixed 0
      @height = Layout::Sizing.fixed 0
    end

    # The keyboard lands here while it holds. It lands nowhere else.
    def focusable? : Bool
      @holding
    end

    # Takes the keyboard on *app*. Answers whether it got it.
    #
    # An application with no focus stack to push onto cannot give it up, and
    # a run there happens inside one call anyway.
    def grab(app : Widgets::App?) : Bool
      return false if @scope || app.nil?

      @holding = true
      @scope = app.focus.push self
      app.focus.focus self
      @app = app

      true
    end

    # Gives the keyboard back to whatever had it.
    def let_go : Nil
      return unless @scope

      @holding = false
      @scope = nil
      @app.try &.focus.pop
      @app = nil
    end

    # Answers every key by calling `#on_key`, and lets nothing past.
    def handle(event : TermBuf::Event, context : Widgets::Context) : Nil
      return unless @holding
      return unless event.is_a? TermBuf::Events::Key

      context.consume
      @on_key.try &.call
    end

    def draw(view : View) : Nil
    end

    # The application it pushed a scope onto.
    @app : Widgets::App? = nil
  end
end
