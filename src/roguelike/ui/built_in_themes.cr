require "./theme"

module Roguelike::Ui
  struct Theme
    # A theme with every color given in *colors*, by key. Raises
    # `ArgumentError` when *colors* leaves out a key or has one that is not a
    # color, so a built-in theme cannot fall back to a default by accident.
    def self.built(colors : Hash(String, Int32)) : Theme
      missing = keys - colors.keys
      extra = colors.keys - keys
      unless missing.empty? && extra.empty?
        raise ArgumentError.new "a built-in theme lists every color: missing #{missing}, extra #{extra}"
      end

      colors.reduce(DEFAULT) { |theme, (key, value)| theme.with key, TermBuf::Color.rgb(value) }
    end

    # The colors drawn as text or as a glyph on the map's ground.
    ON_GROUND = %w[
      granite sandstone shale stone dirt wood spiked stairs iron hero missile heard_mark
      white_slime blue_slime red_slime green_slime goblin_scout goblin_warrior goblin_shaman
      orc orc_archer ant jelly rat giant_rat wolf werewolf bear boar giant_snake skeleton
      zombie imp gelatinous_cube stone_golem iron_golem orc_warlord goblin_skirmisher shape
      flame glimmer weapon armor potion scroll wand tool coin blessed_mark cursed_mark
      uncursed_mark slot_mark lit_mark plain faint strong vacant message_new pointer_mark
      focus_rule
    ]

    # Each other color drawn as text, with the color it is drawn on.
    ON_OTHERS = [
      {"plain", "focus_ground"}, {"faint", "focus_ground"}, {"strong", "focus_ground"},
      {"plain", "selected_row"}, {"faint", "selected_row"},
      {"header_text", "header_ground"}, {"header_text", "selected_header"},
      {"badge_text", "badge_ground"}, {"empty_text", "empty"}, {"ground", "spotlight"},
      {"noise_text", "noise_near"}, {"noise_text", "noise_far"},
      {"plain", "offered"}, {"plain", "flight"}, {"plain", "impact"},
    ]

    # The contrast of each text color on its background, as WCAG gives it,
    # with the two keys.
    def readings : Array({String, String, Float64})
      pairs = ON_GROUND.map { |key| {key, "ground"} } + ON_OTHERS
      pairs.map { |text, ground| {text, ground, Palette.contrast(self[text], self[ground])} }
    end

    # Black ground and bright colors. Every text color and every glyph is at
    # least 6 to 1 on its background, and a remembered floor about 4.9 to 1.
    HIGH_CONTRAST = built({
      "granite"           => 0xC4CAD6,
      "sandstone"         => 0xE8C470,
      "shale"             => 0x9CC0F0,
      "stone"             => 0xB0B4C0,
      "dirt"              => 0xC8B090,
      "wood"              => 0xFFA850,
      "spiked"            => 0xE0E4EC,
      "stairs"            => 0xFFFFFF,
      "iron"              => 0xB8BCC8,
      "hero"              => 0xFFFFFF,
      "ground"            => 0x000000,
      "spotlight"         => 0xFFE000,
      "offered"           => 0x1E4A10,
      "flight"            => 0x1C2E6C,
      "impact"            => 0x701818,
      "missile"           => 0xFFF0C0,
      "noise_near"        => 0x4A2090,
      "noise_far"         => 0x26104C,
      "noise_text"        => 0xFFFFFF,
      "noise_wave"        => 0x9060FF,
      "heard_mark"        => 0x60F8FF,
      "white_slime"       => 0xFFFFFF,
      "blue_slime"        => 0x6CC4FF,
      "red_slime"         => 0xFF6A6A,
      "green_slime"       => 0x60FF60,
      "goblin_scout"      => 0xFFE840,
      "goblin_warrior"    => 0xB4F040,
      "goblin_shaman"     => 0xFF80FF,
      "orc"               => 0xFF7A5C,
      "orc_archer"        => 0x60F0F0,
      "ant"               => 0xFFA848,
      "jelly"             => 0xD0B0FF,
      "rat"               => 0xD8BCB4,
      "giant_rat"         => 0xFFA0D8,
      "wolf"              => 0xC4D4EC,
      "werewolf"          => 0xFFC850,
      "bear"              => 0xE09C6C,
      "boar"              => 0xF8A0A0,
      "giant_snake"       => 0x48E8B4,
      "skeleton"          => 0xFFF0B8,
      "zombie"            => 0xA8E8AC,
      "imp"               => 0xFF64B0,
      "gelatinous_cube"   => 0xEEFFA0,
      "stone_golem"       => 0xD4C8B4,
      "iron_golem"        => 0x8CC0FF,
      "orc_warlord"       => 0xFFCC90,
      "goblin_skirmisher" => 0x98A4FF,
      "shape"             => 0xB8BCC8,
      "flame"             => 0xFFB850,
      "glimmer"           => 0xA0C4FF,
      "shadow"            => 0x545C6E,
      "weapon"            => 0xE8EEF8,
      "armor"             => 0xC4D2EC,
      "potion"            => 0xFF78C4,
      "scroll"            => 0xFFF6DC,
      "wand"              => 0x90F0DC,
      "tool"              => 0xF0B870,
      "coin"              => 0xFFE050,
      "blessed_mark"      => 0xA0CCF0,
      "cursed_mark"       => 0xF090B0,
      "uncursed_mark"     => 0xB4B4BC,
      "slot_mark"         => 0xA0C8B4,
      "lit_mark"          => 0xF0B870,
      "plain"             => 0xF2F2F2,
      "faint"             => 0xB4B4BC,
      "strong"            => 0xFFFFFF,
      "vacant"            => 0x9C9CA4,
      "message_new"       => 0xFFF040,
      "blessed_word"      => 0xFFFFFF,
      "header_ground"     => 0x2C3444,
      "header_text"       => 0xFFFFFF,
      "selected_header"   => 0x1F56B8,
      "selected_row"      => 0x10306C,
      "focus_ground"      => 0x181A20,
      "focus_flash"       => 0x1A2C50,
      "focus_rule"        => 0x80C0FF,
      "pointer_mark"      => 0xC0C8D4,
      "badge_ground"      => 0x1A48A0,
      "badge_text"        => 0xFFFFFF,
      "green"             => 0x4CC050,
      "light_green"       => 0x9CD458,
      "yellow"            => 0xE0C020,
      "orange"            => 0xF08C40,
      "light_orange"      => 0xF4B070,
      "red"               => 0xE83838,
      "empty"             => 0x2A2C30,
      "empty_text"        => 0xD4D8E0,
      "haste_bar"         => 0x40C8FF,
      "slow_bar"          => 0xC0A8F0,
      "blind_bar"         => 0xC8C8C8,
      "noise_bar"         => 0xC890FF,
      "hunger_bar"        => 0xF0B870,
      "thirst_bar"        => 0xA0C4FF,
    })

    # A light ground with dark ink, for a terminal with a light background.
    # Panels draw on the terminal's own background, so this theme reads only
    # on a light one. Every text color and every glyph is at least 5 to 1 on
    # its background.
    PAPER = built({
      "granite"           => 0x4A5060,
      "sandstone"         => 0x7A5810,
      "shale"             => 0x2E5488,
      "stone"             => 0x5A5E68,
      "dirt"              => 0x6A5030,
      "wood"              => 0x8A4A10,
      "spiked"            => 0x303440,
      "stairs"            => 0x000000,
      "iron"              => 0x505560,
      "hero"              => 0x000000,
      "ground"            => 0xFAF6EE,
      "spotlight"         => 0x1A3A8A,
      "offered"           => 0xC8E4B0,
      "flight"            => 0xC4D0F0,
      "impact"            => 0xF0C0C0,
      "missile"           => 0x6A3000,
      "noise_near"        => 0xD8C8F4,
      "noise_far"         => 0xEEE8FA,
      "noise_text"        => 0x000000,
      "noise_wave"        => 0x6A40B0,
      "heard_mark"        => 0x006A80,
      "white_slime"       => 0x60606A,
      "blue_slime"        => 0x0050B0,
      "red_slime"         => 0xB01010,
      "green_slime"       => 0x107010,
      "goblin_scout"      => 0x6E5600,
      "goblin_warrior"    => 0x4A6A00,
      "goblin_shaman"     => 0x900090,
      "orc"               => 0xA02810,
      "orc_archer"        => 0x00707A,
      "ant"               => 0x9A4A00,
      "jelly"             => 0x6030A0,
      "rat"               => 0x6A4A40,
      "giant_rat"         => 0xA0306A,
      "wolf"              => 0x3A4A6A,
      "werewolf"          => 0x805400,
      "bear"              => 0x6A3A10,
      "boar"              => 0xA04040,
      "giant_snake"       => 0x006A4A,
      "skeleton"          => 0x6A5A30,
      "zombie"            => 0x3A6A3A,
      "imp"               => 0xB0105A,
      "gelatinous_cube"   => 0x546200,
      "stone_golem"       => 0x5A5040,
      "iron_golem"        => 0x1A4AA0,
      "orc_warlord"       => 0x904010,
      "goblin_skirmisher" => 0x3A3AB0,
      "shape"             => 0x505560,
      "flame"             => 0xA05200,
      "glimmer"           => 0x2A4AA0,
      "shadow"            => 0x8A8A92,
      "weapon"            => 0x2A3040,
      "armor"             => 0x2A4A7A,
      "potion"            => 0xA0206A,
      "scroll"            => 0x5A4A20,
      "wand"              => 0x006A60,
      "tool"              => 0x8A5010,
      "coin"              => 0x7A5E00,
      "blessed_mark"      => 0x1A5A90,
      "cursed_mark"       => 0x9A2050,
      "uncursed_mark"     => 0x5A5E68,
      "slot_mark"         => 0x2A6A50,
      "lit_mark"          => 0x8A5010,
      "plain"             => 0x1C1C20,
      "faint"             => 0x505460,
      "strong"            => 0x000000,
      "vacant"            => 0x646872,
      "message_new"       => 0xA03000,
      "blessed_word"      => 0x000000,
      "header_ground"     => 0xD4DAE6,
      "header_text"       => 0x101418,
      "selected_header"   => 0xA8C4F0,
      "selected_row"      => 0xC8DAF8,
      "focus_ground"      => 0xEEEAE0,
      "focus_flash"       => 0xD8E4F8,
      "focus_rule"        => 0x1A5AC0,
      "pointer_mark"      => 0x3A4050,
      "badge_ground"      => 0x1A4AA0,
      "badge_text"        => 0xFFFFFF,
      "green"             => 0x3A9A40,
      "light_green"       => 0x7AB040,
      "yellow"            => 0xC8A000,
      "orange"            => 0xD87020,
      "light_orange"      => 0xE8A060,
      "red"               => 0xC02020,
      "empty"             => 0xD8D8DC,
      "empty_text"        => 0x2A2A30,
      "haste_bar"         => 0x0090D0,
      "slow_bar"          => 0x8060C0,
      "blind_bar"         => 0x909090,
      "noise_bar"         => 0x9050E0,
      "hunger_bar"        => 0x8A5010,
      "thirst_bar"        => 0x2A4AA0,
    })
  end
end
