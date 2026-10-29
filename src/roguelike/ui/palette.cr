require "../../crystal-roguelike"

module Roguelike::Ui
  # What one thing looks like on the screen.
  record Look, glyph : Char, style : Style

  # What terrain looks like.
  #
  # This table sits apart from `Terrain`. What a square is made of is the
  # model's to say. What it looks like is the screen's. A theme is a different
  # table here rather than a change to the game.
  #
  # Every style is built once per theme and kept in `Table`. The style table
  # interns each one once. A style built inside a draw call would intern one
  # style per cell. One frame bounds that count by the screen size. An
  # animation does not bound it at all.
  #
  # Each reader on this module answers from the table for `Theme.current`.
  # `Palette.rebuild` makes a new table when the theme changes.
  module Palette
    # The styles and colors one theme makes. Each is built the first time it
    # is read.
    class Table
      getter theme : Theme

      def initialize(@theme : Theme)
      end
    end

    @@table : Table? = nil

    # The table for the current theme. The first read builds it.
    def self.table : Table
      @@table ||= Table.new Theme.current
    end

    # Builds the table again from *theme*. It runs whenever the theme changes.
    def self.rebuild(theme : Theme = Theme.current) : Nil
      @@table = Table.new theme
    end

    # One entry of `Table`, with a reader of the same name on this module.
    private macro drawn(declaration)
      class Table
        getter({{ declaration.var }} : {{ declaration.type }}) { {{ declaration.value }} }
      end

      def self.{{ declaration.var }} : {{ declaration.type }}
        table.{{ declaration.var }}
      end
    end

    # A wall catches the light and a floor does not, so every wall is drawn
    # brighter than the floor beside it. The ramp shades each of these down
    # by how much light is on the square, and a color that starts dim has
    # nowhere to go.
    drawn granite : Style = Style::DEFAULT.fg(theme.granite)
    drawn sandstone : Style = Style::DEFAULT.fg(theme.sandstone)
    drawn shale : Style = Style::DEFAULT.fg(theme.shale)
    drawn stone : Style = Style::DEFAULT.fg(theme.stone)
    drawn dirt : Style = Style::DEFAULT.fg(theme.dirt)
    drawn wood : Style = Style::DEFAULT.fg(theme.wood)
    drawn stairs : Style = Style::DEFAULT.fg(theme.stairs)
    drawn iron : Style = Style::DEFAULT.fg(theme.iron)
    drawn hero : Style = Style::DEFAULT.fg(theme.hero).bold

    # What light looks like.
    #
    # `Terrain` and `LightKind` carry no color of their own. The model says
    # what is burning. This table says what burning looks like.
    drawn flame : Style = Style::DEFAULT.fg(theme.flame).bold
    drawn glimmer : Style = Style::DEFAULT.fg(theme.glimmer)

    # What each sort of light is drawn in.
    drawn lights : Hash(LightKind, Style) = {
      LightKind::Flame   => flame,
      LightKind::Glimmer => glimmer,
    }

    # How *kind* of light draws.
    def self.[](kind : LightKind) : Style
      lights[kind]
    end

    # How far a lit square is tinted toward the color of what lights it.
    #
    # Enough that firelight reads as warm and a magically lit room as cold.
    # Not so far that a stone floor under a torch stops being stone.
    TINT = 0.18

    # One ramp of a single step per sort of light. `Ramp` caches what it makes
    # and answers the same style for the same base, so tinting adds one style
    # per look per step per kind and then stops.
    drawn tints : Hash(LightKind, Widgets::Ramp) = {
      LightKind::Flame   => Widgets::Ramp.new([TINT], lights[LightKind::Flame].foreground),
      LightKind::Glimmer => Widgets::Ramp.new([TINT], lights[LightKind::Glimmer].foreground),
    }

    # What a square offered as an answer is drawn on.
    #
    # The square keeps its own glyph and its own color. Only the background
    # changes. A person choosing a direction has to see which door is which.
    drawn offered : TermBuf::Color = theme.offered

    # What the square of a creature pointed at in the Seen list is drawn in.
    #
    # The map's own ground on bright amber. The map always draws on
    # `ground`, so the pair stands out whatever the terminal's own colors
    # are.
    drawn spotlit : Style = Style::DEFAULT.fg(theme.ground).bg(theme.spotlight).bold

    # What a square a shot would cross is drawn on.
    drawn flight : TermBuf::Color = theme.flight

    # What the square a shot would stop on is drawn on.
    #
    # A different color from the rest of the line. The line says where the
    # shot goes and this says how far it gets. Somebody aiming past a wall
    # has to see where the two stop agreeing.
    drawn impact : TermBuf::Color = theme.impact

    # What the messages of the current round are drawn in.
    #
    # Bright and bold against the pane, so what just happened stands apart
    # from the history above it.
    drawn message_new : Style = Style::DEFAULT.fg(theme.message_new).bold

    # What each class of item is drawn as.
    #
    # The glyphs are the roguelike conventions. A person who has played one
    # reads `)` as a weapon and `!` as a potion without being told.
    drawn weapon : Style = Style::DEFAULT.fg(theme.weapon)
    drawn armor : Style = Style::DEFAULT.fg(theme.armor)
    drawn potion : Style = Style::DEFAULT.fg(theme.potion)
    drawn scroll : Style = Style::DEFAULT.fg(theme.scroll)
    drawn wand : Style = Style::DEFAULT.fg(theme.wand)
    drawn tool : Style = Style::DEFAULT.fg(theme.tool)
    drawn coin : Style = Style::DEFAULT.fg(theme.coin).bold

    # The underline under "blessed" where a message names it.
    drawn blessed_word : Style = Style::DEFAULT.underlined(color: theme.blessed_word)

    # The underline under "cursed", in the red the meters use for danger.
    drawn cursed_word : Style = Style::DEFAULT.underlined(color: theme.red)

    # ------------------------------------------------------------- readouts

    # What a label beside a number is drawn in.
    drawn faint : Style = Style::DEFAULT.fg(theme.faint)

    # What an ordinary number is drawn in.
    drawn plain : Style = Style::DEFAULT.fg(theme.plain)

    # What a number worth reading first is drawn in.
    drawn strong : Style = Style::DEFAULT.fg(theme.strong).bold

    # What an empty equipment slot is drawn in.
    drawn vacant : Style = Style::DEFAULT.fg(theme.vacant)

    # ------------------------------------------------------------- focus

    # The ground of a focused info or log panel once its fade has settled.
    #
    # It is a gray a little above the terminal's black, dark enough that
    # every light text color keeps its contrast. `plain` on it is about 11.6
    # to 1, `strong` about 15 to 1, and `faint` about 3 to 1.
    drawn focus_ground : TermBuf::Color = theme.focus_ground

    # The ground a focused panel's fade starts at. A blue of the same depth
    # as `focus_ground`, so it draws the eye without washing the text out.
    # `plain` on it is about 10.4 to 1.
    drawn focus_flash : TermBuf::Color = theme.focus_flash

    # What the rule beside the focused panel is drawn in. It is about 9.4
    # to 1 against the ground.
    drawn focus_rule : Style = Style::DEFAULT.fg(theme.focus_rule)

    # The badge on the log's last row that counts the messages below it.
    #
    # White on a dark blue, about 8 to 1, so it stands out from the text
    # beside it on any ground the log has.
    drawn newer_badge : Style = Style::DEFAULT.fg(theme.badge_text).bg(theme.badge_ground).bold
    # ------------------------------------------------------------- sections

    # The ground of a section header in the info panel.
    #
    # A slate blue that stands apart from both grounds the panel is drawn
    # on. It is about 2.9 to 1 against black, 2.6 to 1 against `ground` and
    # 2.1 to 1 against `focus_ground`, so the band reads as a separator on
    # either. White on it is about 7.4 to 1.
    drawn header_ground : TermBuf::Color = theme.header_ground

    # What a section header is drawn in. The text is white on `header_ground`
    # by default.
    drawn header : Style = Style::DEFAULT.fg(theme.header_text).bg(header_ground)

    # A section header's title.
    drawn header_title : Style = header.bold

    # The ground of the selected section header in a focused info panel.
    #
    # A brighter, bluer band than `header_ground`. White on it is about 5.5
    # to 1. It is about 1.4 to 1 against `header_ground` and 2.8 to 1
    # against `focus_ground`, and its hue sets it apart from both.
    drawn selected_header : TermBuf::Color = theme.selected_header

    # The ground of the selected row in a focused info panel.
    #
    # A deep blue under the row's own text colors. `plain` on it is about
    # 8.5 to 1, white about 11 to 1, and `faint` about 2.2 to 1.
    drawn selected_row : TermBuf::Color = theme.selected_row

    # ------------------------------------------------------------- meters

    # The colors a bar passes through as it empties.
    drawn green : TermBuf::Color = theme.green
    drawn light_green : TermBuf::Color = theme.light_green
    drawn yellow : TermBuf::Color = theme.yellow
    drawn orange : TermBuf::Color = theme.orange
    drawn light_orange : TermBuf::Color = theme.light_orange
    drawn red : TermBuf::Color = theme.red

    # What the empty part of a bar is drawn on.
    drawn empty : TermBuf::Color = theme.empty

    # What text over the empty part is drawn in.
    drawn empty_text : TermBuf::Color = theme.empty_text

    # What the hit point bar is at each level, as a percentage and a color.
    #
    # Between two levels the color is mixed from the two, so the bar shades
    # as it empties rather than stepping at a boundary. Below the last level
    # it stays at the last color.
    #
    # Whether a bar shades or steps is the `bar_color` option. See
    # `.meter`.
    drawn health : Array({Int32, TermBuf::Color}) = [
      {100, green},
      {80, light_green},
      {60, yellow},
      {40, orange},
      {20, red},
    ]

    # The same for magic.
    #
    # Light orange at the bottom rather than red. Running out of magic is not
    # the same as running out of blood, and the red is worth keeping for the
    # one bar that means the run is about to end.
    drawn magic : Array({Int32, TermBuf::Color}) = [
      {100, green},
      {80, light_green},
      {60, yellow},
      {40, orange},
      {20, light_orange},
    ]

    # What the bar for the creature being fought is at each level.
    #
    # It runs the other way from `health`. Red is a creature at full strength
    # and yellow is one about to fall, because this bar is about a threat
    # going away rather than about the character's own safety. A person who
    # reads the two side by side reads both as "green and yellow are good,
    # red is trouble".
    #
    # Three levels rather than five. The bar is one row about one creature
    # and the question it answers is how much is left, so the color has to
    # move far enough to be read at a glance rather than in small steps.
    drawn threat : Array({Int32, TermBuf::Color}) = [
      {100, red},
      {50, orange},
      {0, yellow},
    ]

    # The experience bar, which is one color however full it is.
    #
    # A bar that changes color says something is wrong. Nothing is wrong
    # with being early in a level.
    drawn learning : Array({Int32, TermBuf::Color}) = [{100, light_green}, {0, light_green}]

    # The bars for a haste, a slow and a blindness, each one color.
    #
    # The bar runs down as the effect wears off, and its color says which
    # effect it is. Each is light enough that dark text reads on it, and far
    # from `empty` so the end of the fill is plain to see.
    drawn haste : Array({Int32, TermBuf::Color}) = [{100, theme.haste_bar}, {0, theme.haste_bar}]
    drawn slow : Array({Int32, TermBuf::Color}) = [{100, theme.slow_bar}, {0, theme.slow_bar}]
    drawn blindness : Array({Int32, TermBuf::Color}) = [{100, theme.blind_bar}, {0, theme.blind_bar}]

    # The bar colors for each temporary effect.
    def self.lasting(status : Event::Status) : Array({Int32, TermBuf::Color})
      case status
      in .hurried?  then haste
      in .dragging? then slow
      in .blind?    then blindness
      end
    end

    # The noise bar, which is one color however full it is. Dark text on it
    # is about 7 to 1, and it is about 4.5 to 1 against the empty part.
    drawn noise : Array({Int32, TermBuf::Color}) = [{100, theme.noise_bar}, {0, theme.noise_bar}]

    # What a bar of *levels* is drawn in at *percent* full.
    #
    # At or above the first level it is the first color. Between two levels
    # it is mixed from the two by how far between them it is. Below the last
    # level it is the last color.
    #
    # A *banded* bar is not mixed. It takes the color of whichever of the two
    # levels is nearer.
    def self.meter(levels : Array({Int32, TermBuf::Color}), percent : Int32,
                   banded : Bool = false) : TermBuf::Color
      held = percent.clamp 0, 100
      return levels.first[1] if held >= levels.first[0]

      (1...levels.size).each do |index|
        above = levels[index - 1]
        below = levels[index]
        next if held < below[0]

        span = above[0] - below[0]
        return below[1] if span <= 0

        part = (held - below[0]) / span.to_f
        return part >= 0.5 ? above[1] : below[1] if banded

        return mix below[1], above[1], part
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

    # How bright *color* looks, from 0 for black to 1 for white, the way
    # WCAG measures it. A color the terminal picks counts as black.
    def self.luminance(color : TermBuf::Color) : Float64
      return 0.0 unless color.rgb?

      red, green, blue = color.channels.map do |channel|
        part = channel / 255.0
        part <= 0.03928 ? part / 12.92 : ((part + 0.055) / 1.055) ** 2.4
      end

      0.2126 * red + 0.7152 * green + 0.0722 * blue
    end

    # How far apart *one* and *other* are in brightness, as WCAG gives it.
    # 1 is no contrast and 21 is black on white.
    def self.contrast(one : TermBuf::Color, other : TermBuf::Color) : Float64
      first = luminance one
      second = luminance other
      (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
    end

    # Black or white, whichever reads better on *color*.
    def self.readable_on(color : TermBuf::Color) : TermBuf::Color
      return TermBuf::Color.rgb(0xFF, 0xFF, 0xFF) unless color.rgb?

      red, green, blue = color.channels
      bright = 0.299 * red + 0.587 * green + 0.114 * blue

      bright > 140 ? TermBuf::Color.rgb(0x10, 0x12, 0x16) : TermBuf::Color.rgb(0xFF, 0xFF, 0xFF)
    end

    drawn items : Hash(ItemClass, Look) = {
      ItemClass::Melee        => Look.new(')', weapon),
      ItemClass::RangedWeapon => Look.new(')', weapon),
      ItemClass::Ammunition   => Look.new(')', weapon),
      ItemClass::Thrown       => Look.new(')', weapon),
      ItemClass::Armor        => Look.new('[', armor),
      ItemClass::Potion       => Look.new('!', potion),
      ItemClass::Scroll       => Look.new('?', scroll),
      ItemClass::Wand         => Look.new('/', wand),
      ItemClass::Light        => Look.new('(', tool),
      ItemClass::Tool         => Look.new('(', tool),
      ItemClass::Treasure     => Look.new('$', coin),
      ItemClass::Amulet       => Look.new('"', coin),
    }

    # How *item* is drawn where it lies.
    def self.[](item : Item) : Look
      items[item.kind.item_class]
    end

    # What something crossing the floor is drawn in.
    #
    # It is brighter than the same thing lying on the ground. A missile is
    # on the screen for a few frames. It is the thing to look at for those
    # frames.
    drawn missile : Style = Style::DEFAULT.fg(theme.missile)

    # What a bolt from a wand is drawn as.
    #
    # Nothing lands on the floor afterwards, so there is no item to take a
    # glyph from.
    BOLT = '*'

    # How *item* is drawn while it is crossing the floor.
    #
    # An arrow keeps its own glyph. A person then sees what they let go of.
    # A bolt has no item.
    def self.flying(item : Item?) : Look
      Look.new item ? self[item].glyph : BOLT, missile
    end

    # ---------------------------------------------------------------- marks

    # The mark against an item whose blessing the character has worked out.
    #
    # An item they have not worked out has no mark. Every item whose blessing
    # is settled has one of these three marks.
    BLESSED  = '\u2726'
    CURSED   = '\u2718'
    UNCURSED = '\u2713'

    # The word for an item whose blessing is not worked out.
    #
    # Such an item has no mark. A readout that writes a mark and a word
    # writes this word with no mark.
    UNKNOWN_WORD = "unknown"

    # What each blessing mark is drawn in.
    #
    # None of the three is at full brightness. They sit in a column of their
    # own. They are designed to be distinctive from each other. Uncursed is
    # the faintest, because most items are uncursed.
    drawn blessed_mark : Style = Style::DEFAULT.fg(theme.blessed_mark)
    drawn cursed_mark : Style = Style::DEFAULT.fg(theme.cursed_mark)
    drawn uncursed_mark : Style = Style::DEFAULT.fg(theme.uncursed_mark)

    # How the blessing of *item* is marked.
    #
    # It is `nil` for an item the character has not worked out. Such an item
    # has no mark.
    def self.blessing(item : Item) : Look?
      return unless item.blessing_known?

      case item.blessing
      in .blessed?  then Look.new BLESSED, blessed_mark
      in .cursed?   then Look.new CURSED, cursed_mark
      in .uncursed? then Look.new UNCURSED, uncursed_mark
      end
    end

    # The word for the blessing of *item*. A readout writes it beside the
    # mark.
    def self.blessing_word(item : Item) : String
      item.blessing_known? ? item.blessing.label : UNKNOWN_WORD
    end

    # The mark against an item the character has readied.
    #
    # One mark is used for all five worn slots. The piece of armor is in the
    # name beside the mark.
    MELEE  = '\u2694'
    RANGED = '\u27B6'
    QUIVER = '\u27B7'
    WORN   = '\u26CA'

    # The mark against a light source that is burning.
    LIT = '\u2055'

    # The word for a burning light source. A readout writes it beside the
    # mark.
    LIT_WORD = "burning"

    # What a slot mark is drawn in.
    #
    # One color is used for the whole column. The marks differ by shape.
    # The color is what separates the column from the names beside it.
    drawn slot_mark : Style = Style::DEFAULT.fg(theme.slot_mark)

    # What the mark on a burning light source is drawn in.
    drawn lit_mark : Style = Style::DEFAULT.fg(theme.lit_mark)

    # How *slot* is marked in a list.
    def self.slot(slot : Slot) : Look
      glyph = case slot
              in .melee?                                   then MELEE
              in .ranged?                                  then RANGED
              in .quiver?                                  then QUIVER
              in .head?, .body?, .hands?, .feet?, .shield? then WORN
              end

      Look.new glyph, slot_mark
    end

    # How a burning light source is marked in a list.
    def self.burning : Look
      Look.new LIT, lit_mark
    end

    # The two marks on the row under the pointer. One is at the near edge
    # and one is at the far edge.
    POINTER = '\u27EA'
    POINTED = '\u27EB'

    # What both are drawn in.
    drawn pointer_mark : Style = Style::DEFAULT.fg(theme.pointer_mark)

    # What a creature nobody can see properly is drawn in.
    #
    # One color for every species. A color is as much a name as a letter
    # is, and somebody who can only make out a shape has been told neither.
    drawn shape : Style = Style::DEFAULT.fg(theme.shape)

    # How a creature of *size* is drawn when it is only a shape.
    def self.shape(size : Size) : Look
      Look.new size.glyph, shape
    end

    # The character. Roguelikes have drawn the player as `@` since 1980. A
    # person who has played one looks for it first.
    drawn player : Look = Look.new('@', hero)

    # What each kind is drawn as.
    #
    # The glyph is the letter of its species, which is the roguelike
    # convention: `j` for a slime, `g` for a goblin, `o` for an orc. The
    # colour names the kind. Each is bright enough to read against the
    # dark ground at a contrast of well over three to one, and the kinds of
    # one species sit far apart in hue so no two share a look.
    drawn white_slime : Style = Style::DEFAULT.fg(theme.white_slime)
    drawn blue_slime : Style = Style::DEFAULT.fg(theme.blue_slime)
    drawn red_slime : Style = Style::DEFAULT.fg(theme.red_slime)
    drawn green_slime : Style = Style::DEFAULT.fg(theme.green_slime)
    drawn goblin_scout : Style = Style::DEFAULT.fg(theme.goblin_scout)
    drawn goblin_warrior : Style = Style::DEFAULT.fg(theme.goblin_warrior)
    drawn goblin_shaman : Style = Style::DEFAULT.fg(theme.goblin_shaman)
    drawn orc : Style = Style::DEFAULT.fg(theme.orc)
    drawn orc_archer : Style = Style::DEFAULT.fg(theme.orc_archer)
    drawn ant : Style = Style::DEFAULT.fg(theme.ant)
    drawn jelly : Style = Style::DEFAULT.fg(theme.jelly)
    drawn rat : Style = Style::DEFAULT.fg(theme.rat)
    drawn giant_rat : Style = Style::DEFAULT.fg(theme.giant_rat)
    drawn wolf : Style = Style::DEFAULT.fg(theme.wolf)
    drawn werewolf : Style = Style::DEFAULT.fg(theme.werewolf)
    drawn bear : Style = Style::DEFAULT.fg(theme.bear)
    drawn boar : Style = Style::DEFAULT.fg(theme.boar)
    drawn giant_snake : Style = Style::DEFAULT.fg(theme.giant_snake)
    drawn skeleton : Style = Style::DEFAULT.fg(theme.skeleton)
    drawn zombie : Style = Style::DEFAULT.fg(theme.zombie)
    drawn imp : Style = Style::DEFAULT.fg(theme.imp)
    drawn gelatinous_cube : Style = Style::DEFAULT.fg(theme.gelatinous_cube)
    drawn stone_golem : Style = Style::DEFAULT.fg(theme.stone_golem)
    drawn iron_golem : Style = Style::DEFAULT.fg(theme.iron_golem)
    drawn orc_warlord : Style = Style::DEFAULT.fg(theme.orc_warlord)
    drawn goblin_skirmisher : Style = Style::DEFAULT.fg(theme.goblin_skirmisher)

    drawn monsters : Hash(Kind, Style) = {
      Kind::WhiteSlime       => white_slime,
      Kind::BlueSlime        => blue_slime,
      Kind::RedSlime         => red_slime,
      Kind::GreenSlime       => green_slime,
      Kind::GoblinScout      => goblin_scout,
      Kind::GoblinWarrior    => goblin_warrior,
      Kind::GoblinShaman     => goblin_shaman,
      Kind::Orc              => orc,
      Kind::OrcArcher        => orc_archer,
      Kind::Ant              => ant,
      Kind::Jelly            => jelly,
      Kind::Rat              => rat,
      Kind::GiantRat         => giant_rat,
      Kind::Wolf             => wolf,
      Kind::Werewolf         => werewolf,
      Kind::Bear             => bear,
      Kind::Boar             => boar,
      Kind::GiantSnake       => giant_snake,
      Kind::Skeleton         => skeleton,
      Kind::Zombie           => zombie,
      Kind::Imp              => imp,
      Kind::GelatinousCube   => gelatinous_cube,
      Kind::StoneGolem       => stone_golem,
      Kind::IronGolem        => iron_golem,
      Kind::OrcWarlord       => orc_warlord,
      Kind::GoblinSkirmisher => goblin_skirmisher,
    }

    # How *kind* draws.
    def self.[](kind : Kind) : Look
      Look.new kind.mark, monsters[kind]
    end

    # How *creature* draws.
    def self.[](creature : Monster) : Look
      self[creature.kind]
    end

    # All three rocks draw as `#`. Their colors differ. That is the roguelike
    # convention. It is also why the three are separate `Terrain` members
    # rather than one wall with a color field.
    drawn looks : Hash(Terrain, Look) = {
      Terrain::Granite    => Look.new('#', granite),
      Terrain::Sandstone  => Look.new('#', sandstone),
      Terrain::Shale      => Look.new('#', shale),
      Terrain::StoneFloor => Look.new('.', stone),
      Terrain::DirtFloor  => Look.new('.', dirt),
      Terrain::ClosedDoor => Look.new('+', wood),
      Terrain::OpenDoor   => Look.new('\'', wood),
      Terrain::BrokenDoor => Look.new('/', wood),
      Terrain::StairsUp   => Look.new('<', stairs),
      Terrain::StairsDown => Look.new('>', stairs),
    }

    # How *terrain* draws.
    def self.[](terrain : Terrain) : Look
      looks[terrain]
    end

    # A shut door with an iron spike in it. The glyph differs from a plain
    # shut door's, so it reads without the color.
    drawn spiked : Look = Look.new('ǂ', Style::DEFAULT.fg(theme.spiked).bold)

    # What each sort of fixture is drawn as.
    #
    # The glyph does not change when it is lit. A burning bracket is the same
    # bracket, and `!` is already the potion glyph. The color says whether
    # it is alight.
    FIXTURES = {
      FixtureKind::Sconce => '|',
    }

    # How *fitting* draws. An unlit one is cold iron. A lit one is the flame.
    def self.[](fitting : Fixture) : Look
      Look.new FIXTURES[fitting.kind], fitting.lit? ? flame : iron
    end

    # What the map is painted on.
    #
    # The map paints its own background rather than letting the terminal's
    # through. A game about darkness needs a known black. A pale theme would
    # turn the dim end of the ramp into the high-contrast end, and a terminal
    # that lightens a foreground to hold a contrast ratio against its own
    # background undoes the shading altogether.
    drawn ground : TermBuf::Color = theme.ground

    # The style that paints it.
    drawn ground_style : Style = Style::DEFAULT.bg(ground)

    # What a square nobody has ever seen draws as. A blank.
    drawn unseen : Look = Look.new(' ', ground_style)

    # How far toward `shadow` each step of `ramp` moves.
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

    # The step of `ramp` a shape draws at while the light behind it holds
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
    # A cool near-black rather than black. Shadow on a warm color then reads
    # as shadow rather than as a darker warm color.
    drawn shadow : TermBuf::Color = theme.shadow

    # The ramp every square is drawn through.
    #
    # A blend computing a color per cell interns a style per cell and the
    # style table only grows. A ramp answers the same style for the same step
    # every time, so the table stops growing once each step of each look has
    # been asked for.
    drawn ramp : Widgets::Ramp = Widgets::Ramp.new(SHADES, shadow)

    # Which step of `ramp` a square with *level* light draws at.
    #
    # A square with no light on it is remembered rather than seen, so it draws
    # at the bottom. Each `LIGHT_PER_STEP` points of light raises it one step,
    # up to the top.
    #
    # A torch of radius six then reaches the top on the two squares nearest
    # the flame and falls a step every two squares out from there. A square at
    # the top of the ramp is drawn in the color it would have in daylight,
    # and something has to reach it or the top is a color nobody ever sees.
    def self.step(level : Int32) : Int32
      return REMEMBERED if level <= 0

      Math.min REMEMBERED + 1 + level // LIGHT_PER_STEP, STEPS - 1
    end

    # *look* drawn at *step* of `ramp`, tinted by *kind* of light, on the
    # map's own background.
    #
    # The background is put on after the ramp rather than into it. The ground
    # is the same everywhere. Only what stands on it is shaded.
    #
    # A square drawn from memory takes no tint. What lights it now says
    # nothing about what it looked like when it was last seen.
    def self.shaded(look : Look, step : Int32, kind : LightKind? = nil) : Look
      shade = ramp[look.style, step]
      tint = kind.try { |lit| tints[lit] } if step > REMEMBERED
      shade = tint[shade, 0] if tint

      Look.new look.glyph, shade.bg(ground)
    end

    # ---------------------------------------------------------------- noise

    # How many shades the tint of the character's noise has, from the edge
    # of where it reached to the square it came from.
    NOISE_STEPS = 4

    # The least contrast a glyph keeps on the tint. A glyph that would have
    # less is lifted toward `noise_text` until it has this much.
    NOISE_CONTRAST = 4.5

    # The tint at each step, the edge first.
    drawn noise_tints : Array(TermBuf::Color) = Palette.noise_ramp(theme)

    # The tint at each step for *theme*, mixed from its edge color to its
    # near color.
    def self.noise_ramp(theme : Theme) : Array(TermBuf::Color)
      (0...NOISE_STEPS).map do |step|
        mix theme.noise_far, theme.noise_near, step / (NOISE_STEPS - 1).to_f
      end
    end

    # The step `.heard` takes for the front of a spreading tint.
    NOISE_WAVE = NOISE_STEPS

    # What the front of a spreading tint is drawn on. Brighter than any step
    # of the tint, so the ring reads as moving out over it.
    drawn noise_wave : TermBuf::Color = theme.noise_wave

    # What a glyph is lifted toward on the tint.
    drawn noise_text : TermBuf::Color = theme.noise_text

    # The tinted styles worked out so far, by base style and step.
    drawn noise_styles : Hash({Style, Int32}, Style) = {} of {Style, Int32} => Style

    # Which step of the tint a square *away* squares along a sound of
    # *loudness* draws at. The source is the top step.
    def self.noise_step(away : Int32, loudness : Int32) : Int32
      return NOISE_STEPS - 1 if loudness <= 0

      ((loudness - away) * NOISE_STEPS // (loudness + 1)).clamp 0, NOISE_STEPS - 1
    end

    # What marks a sound heard from out of sight, on the last square in
    # sight toward it. The same note the noise bar is labeled with.
    HEARD = '♪'

    # How that mark is drawn.
    drawn heard_mark : Look = Look.new(HEARD, Style::DEFAULT.fg(theme.heard_mark).bold)

    # *style* on the tint at *step*, or on the front of a spreading tint at
    # `NOISE_WAVE`.
    #
    # The glyph keeps its own color where that reads on the tint. Where it
    # does not, it moves toward `noise_text` in quarters until it does.
    def self.heard(style : Style, step : Int32) : Style
      wanted = step.clamp 0, NOISE_WAVE
      noise_styles[{style, wanted}] ||= begin
        ground = wanted == NOISE_WAVE ? noise_wave : noise_tints[wanted]
        color = style.foreground
        lifted = color.rgb? ? color : noise_text
        4.times do |quarter|
          break if contrast(lifted, ground) >= NOISE_CONTRAST

          lifted = mix color.rgb? ? color : noise_text, noise_text, (quarter + 1) / 4.0
        end

        style.fg(lifted).bg(ground)
      end
    end
  end
end
