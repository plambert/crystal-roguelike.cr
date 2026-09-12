module Roguelike::Ui
  # What one thing looks like on the screen.
  record Look, glyph : Char, style : Style

  # What terrain looks like.
  #
  # This table sits apart from `Terrain`. What a square is made of is the
  # model's to say. What it looks like is the screen's. A theme is a different
  # table here. A theme is not a change to the game.
  #
  # Every style is a constant. The style table interns each one once. A style
  # built inside a draw call would intern one style per cell. One frame bounds
  # that count by the screen size. An animation does not bound it at all.
  module Palette
    GRANITE   = Style::DEFAULT.fg TermBuf::Color.rgb(0x6E, 0x72, 0x7A)
    SANDSTONE = Style::DEFAULT.fg TermBuf::Color.rgb(0xA8, 0x8A, 0x55)
    SHALE     = Style::DEFAULT.fg TermBuf::Color.rgb(0x55, 0x68, 0x80)
    STONE     = Style::DEFAULT.fg TermBuf::Color.rgb(0x60, 0x63, 0x6B)
    DIRT      = Style::DEFAULT.fg TermBuf::Color.rgb(0x7A, 0x62, 0x48)
    WOOD      = Style::DEFAULT.fg TermBuf::Color.rgb(0xC0, 0x8A, 0x40)
    STAIRS    = Style::DEFAULT.fg TermBuf::Color.rgb(0xE0, 0xE4, 0xEC)
    HERO      = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0xFF, 0xFF)).bold

    # The character. Roguelikes have drawn the player as `@` since 1980. A
    # person who has played one looks for it first.
    PLAYER = Look.new '@', HERO

    # All three rocks draw as `#`. Their colours differ. That is the roguelike
    # convention. It is also why the three are separate `Terrain` members
    # rather than one wall with a colour field.
    LOOKS = {
      Terrain::Granite    => Look.new('#', GRANITE),
      Terrain::Sandstone  => Look.new('#', SANDSTONE),
      Terrain::Shale      => Look.new('#', SHALE),
      Terrain::StoneFloor => Look.new('.', STONE),
      Terrain::DirtFloor  => Look.new('.', DIRT),
      Terrain::ClosedDoor => Look.new('+', WOOD),
      Terrain::OpenDoor   => Look.new('\'', WOOD),
      Terrain::StairsUp   => Look.new('<', STAIRS),
      Terrain::StairsDown => Look.new('>', STAIRS),
    }

    # How *terrain* draws.
    def self.[](terrain : Terrain) : Look
      LOOKS[terrain]
    end
  end
end
