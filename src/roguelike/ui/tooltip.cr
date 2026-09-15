module Roguelike::Ui
  # A box of lines hanging beside one row of the sidebar or of a menu.
  #
  # The sidebar writes an item in sixteen columns and a menu cuts a long row
  # at its own edge. This is where the rest of what is known about the item
  # goes. It hangs to the left of the row, and the layout puts it on the right
  # when there is no room on the left, so it covers the map rather than the
  # thing it is about.
  #
  # A sidebar row raises it when the pointer crosses it. A menu raises it from
  # whichever row the highlight is on, so the arrows raise it as well as the
  # pointer.
  #
  # It takes neither the keyboard nor the pointer. A pointer that crossed it
  # would be a pointer that could never reach the row under it, and the box
  # would flicker as the two took turns.
  class Tooltip < Widgets::Popover
    # How many lines it holds. Nothing written about one item is longer.
    MOST_LINES = 8

    # The most cells the box takes across, border and all.
    #
    # Wide enough for the longest line anything writes into it: a name with a
    # blessing, a condition and an enchantment on it, and the sentence saying
    # nobody has found out what the thing is.
    WIDTH = 44

    # The fewest. A box narrower than this says nothing worth reading, so a
    # target with less room than this beside it gets one that overlaps.
    LEAST_WIDTH = 16

    # The rows the lines are drawn on.
    getter rows : Array(Line)

    # The row it is hanging off, or `nil` while it is down.
    getter target : Widgets::Widget? = nil

    # What it was put up on, or `nil` while it is down.
    @shown_on : Widgets::App? = nil

    # How far left of the target it hangs, and how far down.
    #
    # A sidebar row is a widget of its own, so the box sits against it. A menu
    # row is not: the whole list is one widget and the row is an offset into
    # it.
    getter dx : Int32 = -1
    getter dy : Int32 = 0

    # Which layer it is painted on.
    #
    # Above a dialog, because it hangs off the rows of one. A box under the
    # menu it belongs to would be covered by the menu, and dimmed by the wash
    # the menu puts over everything below it.
    LAYER = Widgets::Overlay::Z::DIALOG + 1

    def initialize
      # Sized to its own text rather than to the box. The box is what is
      # sized to the rows: a `Grow` row would give the box nothing to grow
      # to and every box would come out at its floor.
      @rows = Array.new(MOST_LINES) { Line.new Layout::Sizing.fit }

      super element: Layout::AttachPoint::RightTop,
        parent: Layout::AttachPoint::LeftTop,
        dx: -1,
        z: LAYER,
        light_dismiss: false,
        width: Layout::Sizing.fit(min: LEAST_WIDTH, max: WIDTH),
        height: Layout::Sizing.fit,
        padding: Layout::Padding.symmetric(horizontal: 1),
        border: Widgets::Border.rounded,
        cancel_key: nil

      @rows.each { |row| add row }
    end

    # Nothing in it takes the keyboard.
    def focusable? : Bool
      false
    end

    # Whether it is up.
    def showing? : Bool
      open?
    end

    # Puts *lines* up on *app*, hanging off *beside*.
    #
    # *dx* and *dy* move it off the target's top left corner. A menu passes
    # both: the list is one widget and the row is an offset down it.
    #
    # Putting the same lines up in the same place again does nothing, so the
    # box does not blink while the pointer rests on one row.
    def show(app : Widgets::App, beside : Widgets::Widget,
             lines : Array(String), dx : Int32 = -1, dy : Int32 = 0) : Nil
      return if open? && @target == beside && @dx == dx && @dy == dy &&
                written == lines

      @target = beside
      @shown_on = app
      @dx = dx
      @dy = dy

      # The pointer goes past it. A box that took the pointer would be a box
      # the pointer could never get past to reach the row under it.
      self.floating = Layout::Floating.on beside,
        Layout::AttachPoint::RightTop, Layout::AttachPoint::LeftTop,
        dx: dx, dy: dy, z: LAYER, capture: false

      @rows.each_with_index do |row, index|
        text = lines[index]?
        row.clear
        row.hidden = text.nil?
        next unless text

        row.put 0, text, index.zero? ? Style::DEFAULT.bold : Palette::PLAIN
      end

      open app
    end

    # How wide the box may be.
    #
    # The cap depends on where the row it hangs off ends up, and the layout
    # settles that in the pass that asks this. So it is worked out here rather
    # than when the box goes up. A box sized when it went up would be sized
    # against wherever the row was on the frame before, which for a menu that
    # has only just opened is nowhere at all.
    def width : Layout::Sizing
      app = @shown_on
      beside = @target
      return super unless app && beside

      Layout::Sizing.fit min: LEAST_WIDTH, max: Tooltip.room(app, beside, @dx)
    end

    # How wide the box may be beside *beside*, without landing on it.
    #
    # It hangs to the left, and the layout flips it to the right when there is
    # no room there. So the room it has is the wider of the two sides, less
    # the gap *dx* asks for. A box sized to that is never clamped back over
    # what it hangs off.
    def self.room(app : Widgets::App, beside : Widgets::Widget, dx : Int32) : Int32
      screen = app.tree.screen
      box = beside.rect
      gap = dx.abs

      left = box.x - screen.x - gap
      right = screen.x + screen.width - (box.x + box.width) - gap

      Math.max Math.min(WIDTH, Math.max(left, right)), LEAST_WIDTH
    end

    # Takes it down.
    def hide : Nil
      return unless open?

      @target = nil
      @shown_on = nil
      close
    end

    # What is written on it now.
    def written : Array(String)
      @rows.reject(&.hidden?).map &.text
    end
  end
end
