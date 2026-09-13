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
    # A wall catches the light and a floor does not, so every wall is drawn
    # brighter than the floor beside it. The ramp shades each of these down
    # by how much light is on the square, and a colour that starts dim has
    # nowhere to go.
    GRANITE   = Style::DEFAULT.fg TermBuf::Color.rgb(0xA0, 0xA6, 0xB2)
    SANDSTONE = Style::DEFAULT.fg TermBuf::Color.rgb(0xC2, 0xA0, 0x5A)
    SHALE     = Style::DEFAULT.fg TermBuf::Color.rgb(0x7C, 0x99, 0xBC)
    STONE     = Style::DEFAULT.fg TermBuf::Color.rgb(0x76, 0x7C, 0x8C)
    DIRT      = Style::DEFAULT.fg TermBuf::Color.rgb(0x7A, 0x6E, 0x5E)
    WOOD      = Style::DEFAULT.fg TermBuf::Color.rgb(0xD0, 0x8A, 0x3C)
    STAIRS    = Style::DEFAULT.fg TermBuf::Color.rgb(0xE8, 0xEC, 0xF4)
    IRON      = Style::DEFAULT.fg TermBuf::Color.rgb(0x9A, 0x9E, 0xA8)
    HERO      = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0xFF, 0xFF)).bold

    # What light looks like.
    #
    # `Terrain` and `LightKind` carry no colour of their own. The model says
    # what is burning. This table says what burning looks like.
    FLAME   = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0xB0, 0x50)).bold
    GLIMMER = Style::DEFAULT.fg TermBuf::Color.rgb(0x90, 0xB8, 0xFF)

    # What each sort of light is drawn in.
    LIGHTS = {
      LightKind::Flame   => FLAME,
      LightKind::Glimmer => GLIMMER,
    }

    # How *kind* of light draws.
    def self.[](kind : LightKind) : Style
      LIGHTS[kind]
    end

    # How far a lit square is tinted toward the colour of what lights it.
    #
    # Enough that firelight reads as warm and a magically lit room as cold.
    # Not so far that a stone floor under a torch stops being stone.
    TINT = 0.18

    # One ramp of a single step per sort of light. `Ramp` caches what it makes
    # and answers the same style for the same base, so tinting adds one style
    # per look per step per kind and then stops.
    TINTS = {
      LightKind::Flame   => Widgets::Ramp.new([TINT], LIGHTS[LightKind::Flame].foreground),
      LightKind::Glimmer => Widgets::Ramp.new([TINT], LIGHTS[LightKind::Glimmer].foreground),
    }

    # What a square offered as an answer is drawn on.
    #
    # The square keeps its own glyph and its own colour. Only the background
    # changes. A person choosing a direction has to see which door is which.
    OFFERED = TermBuf::Color.rgb 0x3A, 0x4E, 0x2A

    # What each class of item is drawn as.
    #
    # The glyphs are the roguelike conventions. A person who has played one
    # reads `)` as a weapon and `!` as a potion without being told.
    WEAPON = Style::DEFAULT.fg TermBuf::Color.rgb(0xDC, 0xE2, 0xEC)
    ARMOUR = Style::DEFAULT.fg TermBuf::Color.rgb(0xB4, 0xC2, 0xDC)
    POTION = Style::DEFAULT.fg TermBuf::Color.rgb(0xE8, 0x64, 0xB4)
    SCROLL = Style::DEFAULT.fg TermBuf::Color.rgb(0xF0, 0xEA, 0xD0)
    WAND   = Style::DEFAULT.fg TermBuf::Color.rgb(0x88, 0xE0, 0xCC)
    TOOL   = Style::DEFAULT.fg TermBuf::Color.rgb(0xE4, 0xA8, 0x60)
    COIN   = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0xD8, 0x48)).bold

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

    # What each species is drawn as.
    #
    # The glyph is the letter a floor file writes, which is the roguelike
    # convention: `j` for a jelly, `g` for a goblin, `o` for an orc. The
    # colours are far enough apart to tell the three of them apart at the
    # dimmest step of the ramp.
    SLIME  = Style::DEFAULT.fg TermBuf::Color.rgb(0x7C, 0xD8, 0x6C)
    GOBLIN = Style::DEFAULT.fg TermBuf::Color.rgb(0xB8, 0xE0, 0x40)
    ORC    = Style::DEFAULT.fg TermBuf::Color.rgb(0xE0, 0x60, 0x50)

    MONSTERS = {
      Species::Slime  => SLIME,
      Species::Goblin => GOBLIN,
      Species::Orc    => ORC,
    }

    # How *creature* draws.
    def self.[](creature : Monster) : Look
      Look.new creature.species.mark, MONSTERS[creature.species]
    end

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

    # What each sort of fixture is drawn as.
    #
    # The glyph does not change when it is lit. A burning bracket is the same
    # bracket, and `!` is the potion glyph, which a sconce has no business
    # borrowing. The colour says whether it is alight.
    FIXTURES = {
      FixtureKind::Sconce => '|',
    }

    # How *fitting* draws. An unlit one is cold iron. A lit one is the flame.
    def self.[](fitting : Fixture) : Look
      Look.new FIXTURES[fitting.kind], fitting.lit? ? FLAME : IRON
    end

    # What the map is painted on.
    #
    # The map paints its own background rather than letting the terminal's
    # through. A game about darkness needs a known black. A pale theme would
    # turn the dim end of the ramp into the high-contrast end, and a terminal
    # that lightens a foreground to hold a contrast ratio against its own
    # background undoes the shading altogether.
    #
    # This is the one colour a theme would want to change first.
    GROUND = TermBuf::Color.rgb 0x0C, 0x0E, 0x12

    # The style that paints it.
    GROUND_STYLE = Style::DEFAULT.bg GROUND

    # What a square nobody has ever seen draws as. A blank.
    UNSEEN = Look.new ' ', GROUND_STYLE

    # How far toward `SHADOW` each step of `RAMP` moves.
    #
    # Four lit steps and one below them. The gap between the bottom step and
    # the one above it is wider than any gap inside the lit range, because a
    # square drawn from memory is not a dimly lit square. It is something
    # else, and it has to read as something else at a glance.
    SHADES = [0.66, 0.44, 0.30, 0.15, 0.0]

    # How many steps there are between a remembered square and a brightly lit
    # one.
    STEPS = SHADES.size

    # The step a square draws at when it is remembered rather than seen.
    REMEMBERED = 0

    # How many points of light one step of the ramp is worth.
    #
    # A torch of radius six throws seven points on the square under it and one
    # at the edge of its reach, so two points to a step spreads a torch pool
    # over the whole lit range.
    LIGHT_PER_STEP = 2

    # What a square with no light on it fades toward.
    #
    # A cool near-black rather than black. Shadow on a warm colour then reads
    # as shadow rather than as a darker warm colour.
    SHADOW = TermBuf::Color.rgb 0x14, 0x18, 0x22

    # The ramp every square is drawn through.
    #
    # A blend computing a colour per cell interns a style per cell and the
    # style table only grows. A ramp answers the same style for the same step
    # every time, so the table stops growing once each step of each look has
    # been asked for.
    RAMP = Widgets::Ramp.new SHADES, SHADOW

    # Which step of `RAMP` a square with *level* light draws at.
    #
    # A square with no light on it is remembered rather than seen, so it draws
    # at the bottom. Each `LIGHT_PER_STEP` points of light raises it one step,
    # up to the top.
    #
    # A torch of radius six then reaches the top on the two squares nearest
    # the flame and falls a step every two squares out from there. A square at
    # the top of the ramp is drawn in the colour it would have in daylight,
    # and something has to reach it or the top is a colour nobody ever sees.
    def self.step(level : Int32) : Int32
      return REMEMBERED if level <= 0

      Math.min REMEMBERED + 1 + level // LIGHT_PER_STEP, STEPS - 1
    end

    # *look* drawn at *step* of `RAMP`, tinted by *kind* of light, on the
    # map's own background.
    #
    # The background is put on after the ramp rather than into it. The ground
    # is the same everywhere. Only what stands on it is shaded.
    #
    # A square drawn from memory takes no tint. What lights it now says
    # nothing about what it looked like when it was last seen.
    def self.shaded(look : Look, step : Int32, kind : LightKind? = nil) : Look
      shade = RAMP[look.style, step]
      tint = kind.try { |lit| TINTS[lit] } if step > REMEMBERED
      shade = tint[shade, 0] if tint

      Look.new look.glyph, shade.bg(GROUND)
    end
  end
end
