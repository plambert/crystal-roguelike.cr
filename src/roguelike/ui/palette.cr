module Roguelike::Ui
  # What one thing looks like on the screen.
  record Look, glyph : Char, style : Style

  # What terrain looks like.
  #
  # This table sits apart from `Terrain`. What a square is made of is the
  # model's to say. What it looks like is the screen's. A theme is a different
  # table here rather than a change to the game.
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

    # What a square a shot would cross is drawn on.
    FLIGHT = TermBuf::Color.rgb 0x2E, 0x36, 0x52

    # What the square a shot would stop on is drawn on.
    #
    # A different colour from the rest of the line. The line says where the
    # shot goes and this says how far it gets. Somebody aiming past a wall
    # has to see where the two stop agreeing.
    IMPACT = TermBuf::Color.rgb 0x6A, 0x2E, 0x2E

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

    # ------------------------------------------------------------- readouts

    # What a label beside a number is drawn in.
    FAINT = Style::DEFAULT.fg TermBuf::Color.rgb(0x6A, 0x70, 0x7C)

    # What an ordinary number is drawn in.
    PLAIN = Style::DEFAULT.fg TermBuf::Color.rgb(0xDC, 0xE2, 0xEC)

    # What a number worth reading first is drawn in.
    STRONG = Style::DEFAULT.fg(TermBuf::Color.rgb(0xFF, 0xFF, 0xFF)).bold

    # What an empty equipment slot is drawn in.
    VACANT = Style::DEFAULT.fg TermBuf::Color.rgb(0x4A, 0x4E, 0x58)

    # ------------------------------------------------------------- meters

    # The colours a bar passes through as it empties.
    GREEN        = TermBuf::Color.rgb 0x4C, 0xAF, 0x50
    LIGHT_GREEN  = TermBuf::Color.rgb 0x8B, 0xC3, 0x4A
    YELLOW       = TermBuf::Color.rgb 0xD4, 0xB1, 0x06
    ORANGE       = TermBuf::Color.rgb 0xE8, 0x83, 0x3A
    LIGHT_ORANGE = TermBuf::Color.rgb 0xF0, 0xA8, 0x60
    RED          = TermBuf::Color.rgb 0xD3, 0x2F, 0x2F

    # What the empty part of a bar is drawn on.
    EMPTY = TermBuf::Color.rgb 0x33, 0x36, 0x3C

    # What text over the empty part is drawn in.
    EMPTY_TEXT = TermBuf::Color.rgb 0x8A, 0x90, 0x9C

    # What the hit point bar is at each level, as a percentage and a colour.
    #
    # Between two levels the colour is mixed from the two, so the bar shades
    # as it empties rather than stepping at a boundary. Below the last level
    # it stays at the last colour.
    #
    # Whether a bar shades or steps should be a person's own choice. It
    # shades for now, and the levels are here either way.
    HEALTH = [
      {100, GREEN},
      {80, LIGHT_GREEN},
      {60, YELLOW},
      {40, ORANGE},
      {20, RED},
    ]

    # The same for magic.
    #
    # Light orange at the bottom rather than red. Running out of magic is not
    # the same as running out of blood, and the red is worth keeping for the
    # one bar that means the run is about to end.
    MAGIC = [
      {100, GREEN},
      {80, LIGHT_GREEN},
      {60, YELLOW},
      {40, ORANGE},
      {20, LIGHT_ORANGE},
    ]

    # What the bar for the creature being fought is at each level.
    #
    # It runs the other way from `HEALTH`. Red is a creature at full strength
    # and yellow is one about to fall, because this bar is about a threat
    # going away rather than about the character's own safety. A person who
    # reads the two side by side reads both as "green and yellow are good,
    # red is trouble".
    #
    # Three levels rather than five. The bar is one row about one creature
    # and the question it answers is how much is left, so the colour has to
    # move far enough to be read at a glance rather than in small steps.
    THREAT = [
      {100, RED},
      {50, ORANGE},
      {0, YELLOW},
    ]

    # The experience bar, which is one colour however full it is.
    #
    # A bar that changes colour says something is wrong. Nothing is wrong
    # with being early in a level.
    LEARNING = [{100, LIGHT_GREEN}, {0, LIGHT_GREEN}]

    # What a bar of *levels* is drawn in at *percent* full.
    #
    # At or above the first level it is the first colour. Between two levels
    # it is mixed from the two by how far between them it is. Below the last
    # level it is the last colour.
    def self.meter(levels : Array({Int32, TermBuf::Color}), percent : Int32) : TermBuf::Color
      held = percent.clamp 0, 100
      return levels.first[1] if held >= levels.first[0]

      (1...levels.size).each do |index|
        above = levels[index - 1]
        below = levels[index]
        next if held < below[0]

        span = above[0] - below[0]
        return below[1] if span <= 0

        return mix below[1], above[1], (held - below[0]) / span.to_f
      end

      levels.last[1]
    end

    # *first* moved *part* of the way toward *second*.
    def self.mix(first : TermBuf::Color, second : TermBuf::Color,
                 part : Float64) : TermBuf::Color
      return first unless first.rgb? && second.rgb?

      held = part.clamp 0.0, 1.0
      one = first.channels
      other = second.channels

      TermBuf::Color.rgb(
        (one[0] + (other[0] - one[0]) * held).round.to_i,
        (one[1] + (other[1] - one[1]) * held).round.to_i,
        (one[2] + (other[2] - one[2]) * held).round.to_i)
    end

    # Black or white, whichever reads better on *colour*.
    def self.readable_on(colour : TermBuf::Color) : TermBuf::Color
      return TermBuf::Color.rgb(0xFF, 0xFF, 0xFF) unless colour.rgb?

      red, green, blue = colour.channels
      bright = 0.299 * red + 0.587 * green + 0.114 * blue

      bright > 140 ? TermBuf::Color.rgb(0x10, 0x12, 0x16) : TermBuf::Color.rgb(0xFF, 0xFF, 0xFF)
    end

    ITEMS = {
      ItemClass::Melee        => Look.new(')', WEAPON),
      ItemClass::RangedWeapon => Look.new(')', WEAPON),
      ItemClass::Ammunition   => Look.new(')', WEAPON),
      ItemClass::Thrown       => Look.new(')', WEAPON),
      ItemClass::Armour       => Look.new('[', ARMOUR),
      ItemClass::Potion       => Look.new('!', POTION),
      ItemClass::Scroll       => Look.new('?', SCROLL),
      ItemClass::Wand         => Look.new('/', WAND),
      ItemClass::Light        => Look.new('(', TOOL),
      ItemClass::Tool         => Look.new('(', TOOL),
      ItemClass::Treasure     => Look.new('$', COIN),
    }

    # How *item* is drawn where it lies.
    def self.[](item : Item) : Look
      ITEMS[item.kind.item_class]
    end

    # What something crossing the floor is drawn in.
    #
    # Brighter than the same thing lying on the ground. A missile is on the
    # screen for a few frames, and it is what the eye should be on for those
    # frames.
    MISSILE = Style::DEFAULT.fg TermBuf::Color.rgb(0xF2, 0xE6, 0xC0)

    # What a bolt from a wand is drawn as.
    #
    # Nothing lands on the floor afterwards, so there is no item to take a
    # glyph from.
    BOLT = '*'

    # How *item* is drawn while it is crossing the floor.
    #
    # An arrow keeps its own glyph, so a person sees what they let go of. A
    # bolt has no item behind it.
    def self.flying(item : Item?) : Look
      Look.new item ? self[item].glyph : BOLT, MISSILE
    end

    # What a creature nobody can see properly is drawn in.
    #
    # One colour for every species. A colour is as much a name as a letter
    # is, and somebody who can only make out a shape has been told neither.
    SHAPE = Style::DEFAULT.fg TermBuf::Color.rgb(0x9A, 0x9E, 0xA8)

    # How a creature of *size* is drawn when it is only a shape.
    def self.shape(size : Size) : Look
      Look.new size.glyph, SHAPE
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
    # bracket, and `!` is already the potion glyph. The colour says whether
    # it is alight.
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
    GROUND = TermBuf::Color.rgb 0x0C, 0x0E, 0x12

    # The style that paints it.
    GROUND_STYLE = Style::DEFAULT.bg GROUND

    # What a square nobody has ever seen draws as. A blank.
    UNSEEN = Look.new ' ', GROUND_STYLE

    # How far toward `SHADOW` each step of `RAMP` moves.
    #
    # Four lit steps and one below them. The gap between the bottom step and
    # the one above it is wider than any gap inside the lit range, because a
    # square drawn from memory has to be told from a dimly lit one at a
    # glance.
    SHADES = [0.66, 0.44, 0.30, 0.15, 0.0]

    # How many steps there are between a remembered square and a brightly lit
    # one.
    STEPS = SHADES.size

    # The step a square draws at when it is remembered rather than seen.
    REMEMBERED = 0

    # The step of `RAMP` a shape draws at while the light behind it holds
    # still.
    #
    # The dimmest lit step. A shape is a dark creature in front of a light,
    # so it is drawn darker than the light behind it.
    SHAPE_STEP = REMEMBERED + 1

    # How far a flame behind a shape may lift it above `SHAPE_STEP`.
    #
    # One step. A flame that flares lifts the shape and the shape drops back
    # when the flame settles. It never goes below `SHAPE_STEP`, because the
    # step under that one is the step a remembered square draws at.
    SHAPE_WAVER = 1

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
