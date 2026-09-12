module Roguelike::Ui
  # What one thing looks like on the screen.
  record Look, glyph : Char, style : Style

  # What terrain looks like.
  #
  # Apart from `Terrain` on purpose. What a square is made of is the model's
  # to say and what it looks like is the screen's, so a theme is a different
  # table here rather than a change to the game.
  #
  # Every style is a constant, interned once. One worked out per cell per
  # frame interns one per cell, which is bounded by the screen for a frame and
  # by nothing at all across an animation.
  module Palette
    GRANITE   = Style::DEFAULT.fg TermBuf::Color.rgb(0x6E, 0x72, 0x7A)
    SANDSTONE = Style::DEFAULT.fg TermBuf::Color.rgb(0xA8, 0x8A, 0x55)
    SHALE     = Style::DEFAULT.fg TermBuf::Color.rgb(0x55, 0x68, 0x80)
    STONE     = Style::DEFAULT.fg TermBuf::Color.rgb(0x60, 0x63, 0x6B)
    DIRT      = Style::DEFAULT.fg TermBuf::Color.rgb(0x7A, 0x62, 0x48)
    WOOD      = Style::DEFAULT.fg TermBuf::Color.rgb(0xC0, 0x8A, 0x40)
    STAIRS    = Style::DEFAULT.fg TermBuf::Color.rgb(0xE0, 0xE4, 0xEC)
    HERO      = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0xFF, 0xFF)).bold

    # The character. `@` is what a roguelike has drawn the player as since
    # 1980, and anybody who has played one will look for it first.
    PLAYER = Look.new '@', HERO

    # The three rocks are all drawn `#` and told apart by colour, which is the
    # roguelike convention and the reason they are three members rather than
    # one wall with a field on it.
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

    # How *terrain* is drawn.
    def self.[](terrain : Terrain) : Look
      LOOKS[terrain]
    end
  end
end
