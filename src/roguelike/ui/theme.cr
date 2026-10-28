require "json"

module Roguelike::Ui
  # Every color the game draws with, by name.
  #
  # The file is `theme.json` in the state directory. It holds one key per
  # color and writes each color as `#rrggbb`. A key the file leaves out keeps
  # its default, so a file written before a color was added still reads.
  #
  # The theme holds only the colors a person picks. `Palette` builds every
  # style from them, and works out the colors that follow from others, such
  # as the steps of a ramp.
  struct Theme
    include JSON::Serializable

    # What the file is called.
    FILE = "theme.json"

    # One color a person can change.
    #
    # *key* is the property and the JSON key. *group* is the heading it sits
    # under. *label* is what the row says.
    record Entry, key : String, group : String, label : String

    # Reads and writes a color as `#rrggbb`.
    module Hex
      FORM = /\A#[0-9a-fA-F]{6}\z/

      def self.from_json(pull : JSON::PullParser) : TermBuf::Color
        location = pull.location
        text = pull.read_string
        unless FORM.matches? text
          raise JSON::ParseException.new("not a #rrggbb color: #{text}", *location)
        end

        TermBuf::Color.rgb text[1..].to_i(16)
      end

      def self.to_json(color : TermBuf::Color, json : JSON::Builder) : Nil
        json.string to_hex(color)
      end

      # *color* as `#rrggbb`.
      def self.to_hex(color : TermBuf::Color) : String
        red, green, blue = color.channels
        "#%02x%02x%02x" % {red, green, blue}
      end
    end

    # One color property read and written through `Hex`.
    private macro color(name, value)
      @[JSON::Field(converter: Roguelike::Ui::Theme::Hex)]
      getter {{ name.id }} : TermBuf::Color = TermBuf::Color.rgb({{ value }})
    end

    color granite, 0xA0A6B2
    color sandstone, 0xC2A05A
    color shale, 0x7C99BC
    color stone, 0x767C8C
    color dirt, 0x7A6E5E
    color wood, 0xD08A3C
    color spiked, 0xD8DCE4
    color stairs, 0xE8ECF4
    color iron, 0x9A9EA8
    color hero, 0xFFFFFF
    color ground, 0x0C0E12
    color spotlight, 0xF0C840
    color offered, 0x3A4E2A
    color flight, 0x2E3652
    color impact, 0x6A2E2E
    color missile, 0xF2E6C0

    color white_slime, 0xEEEEEE
    color blue_slime, 0x5CB8FF
    color red_slime, 0xFF5C5C
    color green_slime, 0x5CF05C
    color goblin_scout, 0xFFE040
    color goblin_warrior, 0xA8E040
    color goblin_shaman, 0xFF70FF
    color orc, 0xFF6850
    color orc_archer, 0x60E8E8
    color ant, 0xFFA040
    color jelly, 0xC8A0FF
    color rat, 0xC8A8A0
    color giant_rat, 0xF090C8
    color wolf, 0xB4C4DC
    color werewolf, 0xFFC048
    color bear, 0xCC8C5C
    color boar, 0xE89090
    color giant_snake, 0x40D8A8
    color skeleton, 0xF4E0A8
    color zombie, 0x9CD8A0
    color imp, 0xFF50A0
    color gelatinous_cube, 0xE4FF94
    color stone_golem, 0xC0B4A0
    color iron_golem, 0x78B4FF
    color shape, 0x9A9EA8

    color flame, 0xFFB050
    color glimmer, 0x90B8FF
    color shadow, 0x141822

    color weapon, 0xDCE2EC
    color armor, 0xB4C2DC
    color potion, 0xE864B4
    color scroll, 0xF0EAD0
    color wand, 0x88E0CC
    color tool, 0xE4A860
    color coin, 0xFFD848
    color blessed_mark, 0x90B8D8
    color cursed_mark, 0xC08098
    color uncursed_mark, 0x6A707C
    color slot_mark, 0x88A898
    color lit_mark, 0xE4A860

    color plain, 0xDCE2EC
    color faint, 0x6A707C
    color strong, 0xFFFFFF
    color vacant, 0x4A4E58
    color message_new, 0xFFE860
    color blessed_word, 0xFFFFFF

    color header_ground, 0x4A5670
    color header_text, 0xFFFFFF
    color selected_header, 0x2E66C8
    color selected_row, 0x203A70
    color focus_ground, 0x22262E
    color focus_flash, 0x1E2E4C
    color focus_rule, 0x7FB8FF
    color pointer_mark, 0x9AA4B4
    color badge_ground, 0x1F4E9E
    color badge_text, 0xFFFFFF

    color green, 0x4CAF50
    color light_green, 0x8BC34A
    color yellow, 0xD4B106
    color orange, 0xE8833A
    color light_orange, 0xF0A860
    color red, 0xD32F2F
    color empty, 0x33363C
    color empty_text, 0x8A909C

    # Every color in display order, with its heading and its label.
    ENTRIES = [
      Entry.new("granite", "Map", "Granite"),
      Entry.new("sandstone", "Map", "Sandstone"),
      Entry.new("shale", "Map", "Shale"),
      Entry.new("stone", "Map", "Stone floor"),
      Entry.new("dirt", "Map", "Dirt floor"),
      Entry.new("wood", "Map", "Door"),
      Entry.new("spiked", "Map", "Spiked door"),
      Entry.new("stairs", "Map", "Stairs"),
      Entry.new("iron", "Map", "Unlit sconce"),
      Entry.new("hero", "Map", "You"),
      Entry.new("ground", "Map", "Map background"),
      Entry.new("spotlight", "Map", "Creature pointed at"),
      Entry.new("offered", "Map", "Square to choose"),
      Entry.new("flight", "Map", "Path of a shot"),
      Entry.new("impact", "Map", "Where a shot stops"),
      Entry.new("missile", "Map", "Thing in flight"),

      Entry.new("white_slime", "Creatures", "White slime"),
      Entry.new("blue_slime", "Creatures", "Blue slime"),
      Entry.new("red_slime", "Creatures", "Red slime"),
      Entry.new("green_slime", "Creatures", "Green slime"),
      Entry.new("goblin_scout", "Creatures", "Goblin scout"),
      Entry.new("goblin_warrior", "Creatures", "Goblin warrior"),
      Entry.new("goblin_shaman", "Creatures", "Goblin shaman"),
      Entry.new("orc", "Creatures", "Orc"),
      Entry.new("orc_archer", "Creatures", "Orc archer"),
      Entry.new("ant", "Creatures", "Ant"),
      Entry.new("jelly", "Creatures", "Jelly"),
      Entry.new("rat", "Creatures", "Rat"),
      Entry.new("giant_rat", "Creatures", "Giant rat"),
      Entry.new("wolf", "Creatures", "Wolf"),
      Entry.new("werewolf", "Creatures", "Werewolf"),
      Entry.new("bear", "Creatures", "Bear"),
      Entry.new("boar", "Creatures", "Boar"),
      Entry.new("giant_snake", "Creatures", "Giant snake"),
      Entry.new("skeleton", "Creatures", "Skeleton"),
      Entry.new("zombie", "Creatures", "Zombie"),
      Entry.new("imp", "Creatures", "Imp"),
      Entry.new("gelatinous_cube", "Creatures", "Gelatinous cube"),
      Entry.new("stone_golem", "Creatures", "Stone golem"),
      Entry.new("iron_golem", "Creatures", "Iron golem"),
      Entry.new("shape", "Creatures", "Shape you cannot make out"),

      Entry.new("flame", "Light", "Flame"),
      Entry.new("glimmer", "Light", "Glimmer"),
      Entry.new("shadow", "Light", "Shadow"),

      Entry.new("weapon", "Items", "Weapon"),
      Entry.new("armor", "Items", "Armor"),
      Entry.new("potion", "Items", "Potion"),
      Entry.new("scroll", "Items", "Scroll"),
      Entry.new("wand", "Items", "Wand"),
      Entry.new("tool", "Items", "Tool or light"),
      Entry.new("coin", "Items", "Gold or amulet"),
      Entry.new("blessed_mark", "Items", "Blessed mark"),
      Entry.new("cursed_mark", "Items", "Cursed mark"),
      Entry.new("uncursed_mark", "Items", "Uncursed mark"),
      Entry.new("slot_mark", "Items", "Readied mark"),
      Entry.new("lit_mark", "Items", "Burning mark"),

      Entry.new("plain", "Text", "Plain"),
      Entry.new("faint", "Text", "Faint"),
      Entry.new("strong", "Text", "Strong"),
      Entry.new("vacant", "Text", "Empty slot"),
      Entry.new("message_new", "Text", "New message"),
      Entry.new("blessed_word", "Text", "Blessed underline"),

      Entry.new("header_ground", "Panels", "Header"),
      Entry.new("header_text", "Panels", "Header text"),
      Entry.new("selected_header", "Panels", "Selected header"),
      Entry.new("selected_row", "Panels", "Selected row"),
      Entry.new("focus_ground", "Panels", "Focused panel"),
      Entry.new("focus_flash", "Panels", "Focus flash"),
      Entry.new("focus_rule", "Panels", "Focus rule"),
      Entry.new("pointer_mark", "Panels", "Pointer"),
      Entry.new("badge_ground", "Panels", "Newer messages badge"),
      Entry.new("badge_text", "Panels", "Newer messages badge text"),

      Entry.new("green", "Bars", "Green"),
      Entry.new("light_green", "Bars", "Light green"),
      Entry.new("yellow", "Bars", "Yellow"),
      Entry.new("orange", "Bars", "Orange"),
      Entry.new("light_orange", "Bars", "Light orange"),
      Entry.new("red", "Bars", "Red"),
      Entry.new("empty", "Bars", "Empty part"),
      Entry.new("empty_text", "Bars", "Text on the empty part"),
    ]

    # The game's own colors.
    DEFAULT = new

    # The theme the game draws with. `Palette.rebuild` reads it.
    class_property current : Theme = DEFAULT

    def initialize
    end

    # Every color key, in the order the properties are declared.
    def self.keys : Array(String)
      {{ @type.instance_vars.map(&.name.stringify) }}
    end

    # The color under *key*. Raises `KeyError` for a key that is not a color.
    def [](key : String) : TermBuf::Color
      {% begin %}
        case key
        {% for ivar in @type.instance_vars %}
          when {{ ivar.name.stringify }} then @{{ ivar.id }}
        {% end %}
        else raise KeyError.new "no color #{key}"
        end
      {% end %}
    end

    # A copy with *key* set to *color*. Raises `KeyError` for a key that is
    # not a color.
    def with(key : String, color : TermBuf::Color) : Theme
      copy = self
      copy.assign key, color
      copy
    end

    protected def assign(key : String, color : TermBuf::Color) : Nil
      {% begin %}
        case key
        {% for ivar in @type.instance_vars %}
          when {{ ivar.name.stringify }} then @{{ ivar.id }} = color
        {% end %}
        else raise KeyError.new "no color #{key}"
        end
      {% end %}
    end

    # Where the file is under the state directory *root*.
    def self.path(root : Path) : Path
      root / FILE
    end

    # The theme on file under *root*. The default when there is no file or
    # it does not read.
    def self.read(root : Path) : Theme
      from_json File.read(path root)
    rescue File::Error | JSON::ParseException
      DEFAULT
    end

    # Writes the file under *root*.
    def write(root : Path) : Nil
      Dir.mkdir_p root
      File.write Theme.path(root), "#{to_pretty_json}\n"
    end
  end
end
