module Roguelike::Ui
  # A box of lines hanging to the left of the row the pointer is over.
  #
  # The sidebar writes an item in sixteen columns. This is where the rest of
  # what is known about it goes. It hangs to the left so that it covers the
  # map rather than the sidebar: a person reading it can still see the row
  # they are pointing at.
  #
  # It takes neither the keyboard nor the pointer. A pointer that crossed it
  # would be a pointer that could never reach the row under it, and the box
  # would flicker as the two took turns.
  class Tooltip < Widgets::Popover
    # How many lines it holds. Nothing written about one item is longer.
    MOST_LINES = 8

    # How wide the box is inside its border.
    WIDTH = 34

    # The rows the lines are drawn on.
    getter rows : Array(Line)

    # The row it is hanging off, or `nil` while it is down.
    getter target : Widgets::Widget? = nil

    def initialize
      @rows = Array.new(MOST_LINES) { Line.new }

      super element: Layout::AttachPoint::RightTop,
        parent: Layout::AttachPoint::LeftTop,
        dx: -1,
        light_dismiss: false,
        width: Layout::Sizing.fixed(WIDTH + 2),
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
    # Putting the same lines up beside the same row again does nothing, so
    # the box does not blink while the pointer rests on one row.
    def show(app : Widgets::App, beside : Widgets::Widget,
             lines : Array(String)) : Nil
      return if open? && @target == beside && written == lines

      @target = beside
      self.floating = Layout::Floating.on beside,
        Layout::AttachPoint::RightTop, Layout::AttachPoint::LeftTop,
        dx: -1, z: z

      @rows.each_with_index do |row, index|
        text = lines[index]?
        row.clear
        row.hidden = text.nil?
        next unless text

        row.put 0, text, index.zero? ? Style::DEFAULT.bold : Palette::PLAIN
      end

      open app
    end

    # Takes it down.
    def hide : Nil
      return unless open?

      @target = nil
      close
    end

    # What is written on it now.
    def written : Array(String)
      @rows.reject(&.hidden?).map &.text
    end
  end
end
