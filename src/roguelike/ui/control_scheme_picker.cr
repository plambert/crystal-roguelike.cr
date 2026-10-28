require "../../crystal-roguelike"

module Roguelike::Ui
  # A side-by-side choice of the movement and interaction profiles.
  class ControlSchemePicker < Widgets::Overlay
    # Cells left clear to the left and right of the box.
    COLUMN_MARGIN = 2

    # Rows left clear above and below it.
    ROW_MARGIN = 1

    # The widest the box grows.
    WIDTH = 72

    # The smallest box that holds both cards.
    MINIMUM_WIDTH = 32

    # The smallest height, including the border.
    MINIMUM_HEIGHT = 10

    # A scheme card with its movement diagram and selection marker.
    class Card < Widgets::Panel
      getter scheme : Options::ControlScheme

      getter selection : Widgets::Label

      def initialize(@scheme : Options::ControlScheme)
        super direction: Layout::Direction::Column,
          width: Layout::Sizing.grow,
          height: Layout::Sizing.fit,
          align_x: Layout::Align::Center,
          border: Widgets::Border.rounded(title: @scheme.to_s)

        lines = case @scheme
                in .traditional? then ["y k u", "h @ l", "b j n"]
                in .modern?      then ["q w e", "a @ d", "z s x"]
                end
        lines.each do |line|
          add Widgets::Label.new line, wrap: Layout::Wrap::None,
            align: TermBuf::Unicode::Align::Center
        end

        @selection = Widgets::Label.new "", wrap: Layout::Wrap::None,
          align: TermBuf::Unicode::Align::Center
        add @selection
      end

      # Marks this card as the selected option.
      def select(selected : Bool) : Nil
        @selection.text = selected ? "Selected" : ""
      end
    end

    # What runs when a scheme is confirmed or the chooser is canceled.
    property on_choose : Proc(Options::ControlScheme?, Nil)? = nil

    # The scheme currently highlighted.
    getter selected : Options::ControlScheme = Options::ControlScheme::Modern

    # The Traditional card.
    getter traditional_card : Card

    # The Modern card.
    getter modern_card : Card

    # The row containing both cards.
    getter cards : Widgets::Panel

    def initialize(z : Int32 = Widgets::Overlay::Z::DIALOG)
      @traditional_card = Card.new Options::ControlScheme::Traditional
      @modern_card = Card.new Options::ControlScheme::Modern
      @cards = Widgets::Panel.new direction: Layout::Direction::Row,
        width: Layout::Sizing.grow, height: Layout::Sizing.fit, gap: 1
      @cards.add @traditional_card, @modern_card

      super modal: true, backdrop: true, light_dismiss: false, z: z

      @direction = Layout::Direction::Column
      @padding = Layout::Padding.new 0, 1, 0, 1
      @border = Widgets::Border.rounded title: " Choose control scheme "
      @floating = Layout::Floating.on nil, Layout::AttachPoint::Center,
        Layout::AttachPoint::Center, z: z

      add @cards
      add Widgets::Label.new "r all  f available  i inventory",
        wrap: Layout::Wrap::None
      add Widgets::Label.new "Ctrl+X explore  Shift+dir walk",
        wrap: Layout::Wrap::None
      add Widgets::Label.new "Tab/Shift+Tab cards · a/d/arrows choose",
        wrap: Layout::Wrap::Words
      add Widgets::Label.new "f/Enter confirm · Esc cancel",
        wrap: Layout::Wrap::None
      self.keymap = bindings
      highlight @selected
    end

    # Whether the chooser is up.
    def showing? : Bool
      open?
    end

    # Shows the chooser, highlighting *current* or Modern when none is saved.
    def show(app : Widgets::App,
             current : Options::ControlScheme? = nil) : Nil
      highlight current || Options::ControlScheme::Modern
      self.keymap = bindings
      fit_into app.tree.screen
      open app
    end

    # Sizes the box for *screen* while keeping both cards side by side.
    def fit_into(screen : Rect) : Nil
      widest = Math.max screen.width - 2 * COLUMN_MARGIN, MINIMUM_WIDTH
      tallest = Math.max screen.height - 2 * ROW_MARGIN, MINIMUM_HEIGHT
      self.width = Layout::Sizing.fit min: MINIMUM_WIDTH, max: Math.min(widest, WIDTH)
      self.height = Layout::Sizing.fit min: MINIMUM_HEIGHT, max: tallest
    end

    # Sizes the box again after the terminal changes size.
    def refit(screen : Rect) : Nil
      fit_into screen if showing?
    end

    # The modal root owns keyboard focus while the chooser is open.
    def focusable? : Bool
      true
    end

    # Takes the chooser down without a choice.
    def cancel : Nil
      finish nil if open?
    end

    private def bindings : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("a"), "choose Traditional",
          ->(_context : Widgets::Context) { highlight Options::ControlScheme::Traditional; nil }
        map.bind TermBuf::Key.parse("Left"), "choose Traditional",
          ->(_context : Widgets::Context) { highlight Options::ControlScheme::Traditional; nil }
        map.bind TermBuf::Key.parse("d"), "choose Modern",
          ->(_context : Widgets::Context) { highlight Options::ControlScheme::Modern; nil }
        map.bind TermBuf::Key.parse("Right"), "choose Modern",
          ->(_context : Widgets::Context) { highlight Options::ControlScheme::Modern; nil }
        {"Tab", "Shift+Tab"}.each do |key|
          map.bind TermBuf::Key.parse(key), "change selected scheme",
            ->(_context : Widgets::Context) { cycle; nil }
        end
        map.bind TermBuf::Key.parse("f"), "confirm the selected scheme",
          ->(_context : Widgets::Context) { finish @selected; nil }
        map.bind TermBuf::Key.parse("Enter"), "confirm the selected scheme",
          ->(_context : Widgets::Context) { finish @selected; nil }
        map.bind TermBuf::Key.parse("Escape"), "leave without choosing",
          ->(_context : Widgets::Context) { finish nil; nil }
      end
    end

    private def cycle : Nil
      next_scheme = @selected.traditional? ? Options::ControlScheme::Modern : Options::ControlScheme::Traditional
      highlight next_scheme
    end

    private def highlight(scheme : Options::ControlScheme) : Nil
      @selected = scheme
      @traditional_card.select scheme.traditional?
      @modern_card.select scheme.modern?
    end

    private def finish(scheme : Options::ControlScheme?) : Nil
      self.keymap = nil
      close
      @on_choose.try &.call scheme
    end
  end
end
