require "../../crystal-roguelike"

module Roguelike::Ui
  # Underlines "blessed" and "cursed" where a message names them.
  #
  # Whether an item is blessed or cursed decides whether to use it, so the
  # word stands out from the rest of the line. Only the drawing changes. The
  # log keeps its plain text for saves, replays and the bot.
  #
  # The match is on the whole word and ignores case, so "Cursed" at the start
  # of a sentence counts. "Uncursed" gets nothing. Most things are uncursed,
  # and marking the word would make every line about them look like news.
  module BlessingWords
    # The underline under "blessed".
    BLESSED = Style::DEFAULT.underlined color: TermBuf::Color.rgb(0xFF, 0xFF, 0xFF)

    # The underline under "cursed", in the red the meters use for danger.
    CURSED = Style::DEFAULT.underlined color: Palette::RED

    # The two words, whole.
    WORD = /\b(blessed|cursed)\b/i

    # The accents for every "blessed" and "cursed" in *line*.
    #
    # A terminal that cannot color an underline draws these as a plain one.
    def self.accents(line : String) : Array(Widgets::Pager::Accent)
      found = [] of Widgets::Pager::Accent

      line.scan WORD do |match|
        style = match[1].downcase == "blessed" ? BLESSED : CURSED
        found << Widgets::Pager::Accent.new(match.begin, match[0].size, style)
      end

      found
    end
  end
end
