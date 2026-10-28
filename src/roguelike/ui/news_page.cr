require "../ui"

module Roguelike
  module Ui
    # The what's new screen, which the title screen opens.
    #
    # It is the help screen's dialog and list with the release notes for rows,
    # so it scrolls the same way: the arrows a row, the page keys a window,
    # `Space` half a window.
    class NewsPage < Help
      # The widest a line of the notes is, in cells.
      WIDTH = 60

      # The sections shown, newest first. They are read when the dialog opens.
      property news : Array(WhatsNew::Section) = [] of WhatsNew::Section

      def initialize
        super 0_u64
        self.title = "what's new"
      end

      # Fills the rows from `news`.
      def rebuild : Nil
        @rows.clear

        WhatsNew.lines(@news, WIDTH).each do |line|
          @rows << (line.heading ? Row.new(line.text, header: true) : Row.new(line.text))
        end
      end
    end
  end
end
