module Roguelike::Ui
  # One bar, with the count sitting inside it.
  #
  #     HP ███████23/34██░░░░░
  #
  # The label sits outside the bar and the count sits in it. A person reads
  # the count when they want the number and the fill when they only want to
  # know whether they are in trouble.
  #
  # The fill color comes from `Palette.meter` and the levels the caller
  # names, so a bar shades from green to red as it empties and every bar in
  # the game reads the same way.
  class Meter < Widgets::Widget
    # How many columns the label takes, the space after it included.
    LABEL = 3

    # What the label is drawn in.
    property label_style : Style = Style::DEFAULT.fg TermBuf::Color.rgb(0x6A, 0x70, 0x7C)

    # What the label says. Two columns: `HP`, `MP`, `XP`.
    property label : String

    # How full it is, and how full it goes.
    property value : Int32
    property most : Int32

    # What is written inside the bar. The count when this is `nil`.
    property text : String? = nil

    # The colors it passes through as it empties.
    property levels : Array({Int32, TermBuf::Color})

    def initialize(@label : String,
                   @value : Int32 = 0,
                   @most : Int32 = 1,
                   @levels : Array({Int32, TermBuf::Color}) = Palette::HEALTH)
      @width = Layout::Sizing.grow
      @height = Layout::Sizing.fixed 1
    end

    # Writes a new reading. Answers nothing.
    def show(value : Int32, most : Int32, text : String? = nil) : Nil
      @value = value
      @most = most
      @text = text
    end

    # How full it is, out of a hundred.
    #
    # A bar that goes to zero is empty rather than full. Nothing in the game
    # has a maximum of zero yet, and a bar that read as full would say the
    # opposite of what is true.
    def percent : Int32
      return 0 if @most <= 0

      (100 * @value // @most).clamp 0, 100
    end

    # What is written inside the bar.
    def reading : String
      @text || "#{@value}/#{@most}"
    end

    # What the bar is drawn in now.
    def fill : TermBuf::Color
      Palette.meter @levels, percent
    end

    def intrinsic_width(policy : TermBuf::Unicode::WidthPolicy) : Layout::Intrinsic
      Layout::Intrinsic.new LABEL + 4, LABEL + Math.max(reading.size + 2, 10)
    end

    def height_for_width(width : Int32, policy : TermBuf::Unicode::WidthPolicy) : Int32
      1
    end

    # The label, then one cell at a time across the bar.
    #
    # Each cell is drawn on its own because the two halves of the bar are two
    # different backgrounds and the reading crosses the boundary between
    # them. A cell over the filled part takes whichever of black and white
    # reads better on the fill.
    def draw(view : View) : Nil
      return if view.width <= LABEL || view.height <= 0

      view.write 0, 0, @label, @label_style

      room = view.width - LABEL
      filled = (room * percent / 100.0).round.to_i.clamp 0, room
      color = fill
      over = Palette.readable_on color
      word = reading
      start = (room - word.size) // 2

      room.times do |index|
        inside = index < filled
        at = index - start
        glyph = at >= 0 && at < word.size ? word[at] : ' '

        view.write_char LABEL + index, 0, glyph,
          Style::DEFAULT.fg(inside ? over : Palette::EMPTY_TEXT)
            .bg(inside ? color : Palette::EMPTY)
      end
    end
  end
end
