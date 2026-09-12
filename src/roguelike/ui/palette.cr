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
    IRON      = Style::DEFAULT.fg TermBuf::Color.rgb(0x8A, 0x8E, 0x96)
    HERO      = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0xFF, 0xFF)).bold

    # What light looks like.
    #
    # `Terrain` and `LightKind` carry no colour of their own. The model says
    # what is burning. This table says what burning looks like.
    FLAME   = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0xB0, 0x50)).bold
    GLIMMER = Style::DEFAULT.fg TermBuf::Color.rgb(0x90, 0xB8, 0xFF)

    # What each sort of light is drawn in. Phase 14 tints a lit square with
    # it.
    LIGHTS = {
      LightKind::Flame   => FLAME,
      LightKind::Glimmer => GLIMMER,
    }

    # How *kind* of light draws.
    def self.[](kind : LightKind) : Style
      LIGHTS[kind]
    end

    # What a square offered as an answer is drawn on.
    #
    # The square keeps its own glyph and its own colour. Only the background
    # changes. A person choosing a direction has to see which door is which.
    OFFERED = TermBuf::Color.rgb 0x3A, 0x4E, 0x2A

    # What each class of item is drawn as.
    #
    # The glyphs are the roguelike conventions. A person who has played one
    # reads `)` as a weapon and `!` as a potion without being told.
    WEAPON = Style::DEFAULT.fg TermBuf::Color.rgb(0xC8, 0xCC, 0xD4)
    ARMOUR = Style::DEFAULT.fg TermBuf::Color.rgb(0x9A, 0xA4, 0xB8)
    POTION = Style::DEFAULT.fg TermBuf::Color.rgb(0xE0, 0x5C, 0xA8)
    SCROLL = Style::DEFAULT.fg TermBuf::Color.rgb(0xE8, 0xE2, 0xC8)
    WAND   = Style::DEFAULT.fg TermBuf::Color.rgb(0x8A, 0xD0, 0xC0)
    TOOL   = Style::DEFAULT.fg TermBuf::Color.rgb(0xC0, 0x9A, 0x60)
    COIN   = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0xD0, 0x40)).bold

    ITEMS = {
      ItemClass::Melee      => Look.new(')', WEAPON),
      ItemClass::Launcher   => Look.new(')', WEAPON),
      ItemClass::Ammunition => Look.new(')', WEAPON),
      ItemClass::Thrown     => Look.new(')', WEAPON),
      ItemClass::Armour     => Look.new('[', ARMOUR),
      ItemClass::Potion     => Look.new('!', POTION),
      ItemClass::Scroll     => Look.new('?', SCROLL),
      ItemClass::Wand       => Look.new('/', WAND),
      ItemClass::Light      => Look.new('(', TOOL),
      ItemClass::Treasure   => Look.new('$', COIN),
    }

    # How *item* is drawn where it lies.
    def self.[](item : Item) : Look
      ITEMS[item.kind.item_class]
    end

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

    # How *fitting* draws. An unlit one is cold iron. A lit one is the flame.
    def self.[](fitting : Fixture) : Look
      glyph = fitting.lit? ? fitting.kind.lit_mark : fitting.kind.mark

      Look.new glyph, fitting.lit? ? FLAME : IRON
    end

    # What a square nobody has ever seen draws as. A blank.
    UNSEEN = Look.new ' ', Style::DEFAULT

    # How many steps there are between a remembered square and a brightly lit
    # one.
    #
    # Five is enough that a torch pool has a visible falloff and few enough
    # that the style table settles at a few dozen entries.
    STEPS = 5

    # The step a square draws at when it is remembered rather than seen.
    REMEMBERED = 0

    # How many points of light one step of the ramp is worth.
    LIGHT_PER_STEP = 3

    # The ramp every square is drawn through.
    #
    # A blend computing a colour per cell interns a style per cell and the
    # style table only grows. A ramp answers the same style for the same step
    # every time, so the table stops growing once each step of each look has
    # been asked for.
    RAMP = Widgets::Ramp.new STEPS, TermBuf::Color.rgb(0x10, 0x11, 0x14)

    # Which step of `RAMP` a square with *level* light draws at.
    #
    # A square with no light on it is remembered rather than seen, so it draws
    # at the bottom. Each `LIGHT_PER_STEP` points of light raises it one step,
    # up to the top.
    def self.step(level : Int32) : Int32
      return REMEMBERED if level <= 0

      Math.min REMEMBERED + 1 + (level - 1) // LIGHT_PER_STEP, STEPS - 1
    end

    # *look* drawn at *step* of `RAMP`.
    def self.shaded(look : Look, step : Int32) : Look
      Look.new look.glyph, RAMP[look.style, step]
    end
  end
end
