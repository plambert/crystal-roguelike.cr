require "../ui"

module Roguelike
  module Ui
    # The help screen, which `?` and `F1` open.
    #
    # termbuf's overlay lists every key that works right now. This one puts
    # two things above that list: the run's seed, which is what a person
    # needs to report a bug or play the same dungeon again, and the eight
    # movement keys drawn around the character with an arrow for each, which
    # reads faster than eight rows of "move north-west".
    class Help < Widgets::HelpOverlay
      # The run's seed. The session sets it when the run starts.
      property seed : UInt64

      # The movement keys around the character. Each arrow points from `@`
      # toward the key that moves that way. The arrows are the plain text
      # ones at U+2190 to U+2199, one cell each.
      DIAGRAM = [
        "y k u",
        " ↖↑↗",
        "h←@→l",
        " ↙↓↘",
        "b j n",
      ]

      def initialize(@seed : UInt64 = 0)
        super()
      end

      # The rows the overlay rebuilds as it opens, with the seed and the
      # diagram above them.
      def refresh(app : Widgets::App) : Nil
        super

        above = [] of Row
        above << Row.new("run", "", header: true)
        above << Row.new("seed", @seed.to_s)
        above << Row.new("moving", "", header: true)
        DIAGRAM.each_with_index do |line, index|
          above << Row.new(line, index == 2 ? "move, or attack what is there" : "")
        end

        above.reverse_each { |row| @rows.unshift row }
        @list.rows = Widgets::Rows.of @rows
        @list.select first_binding
        @list.scroll_to_row 0
      end
    end
  end
end
