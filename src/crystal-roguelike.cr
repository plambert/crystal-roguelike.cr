# A terminal roguelike.
#
# The shard is named `crystal-roguelike`. This file is where
# `require "crystal-roguelike"` lands. The namespace is `Roguelike` instead.
# `Crystal` is the compiler's own namespace. Game types do not belong beside
# `Crystal::System`.
module Roguelike
  {% begin %}
  {% command = "shards version '" + __DIR__.gsub(%r{'}, "'\\''") + "'" %}
  VERSION = {{ `#{command.id}`.strip.stringify }}
  {% end %}
end

require "./roguelike/rng"
require "./roguelike/direction"
require "./roguelike/line"
require "./roguelike/attributes"
require "./roguelike/advancement"
require "./roguelike/terrain"
require "./roguelike/tile"
require "./roguelike/species"
require "./roguelike/monster"
require "./roguelike/notice"
require "./roguelike/fixture"
require "./roguelike/floor"
require "./roguelike/field_of_view"
require "./roguelike/apply"
require "./roguelike/lighting"
require "./roguelike/vision"
require "./roguelike/knowledge"
require "./roguelike/descent"
require "./roguelike/pursuit"
require "./roguelike/floors"
require "./roguelike/dice"
require "./roguelike/combat"
require "./roguelike/item_kind"
require "./roguelike/item"
require "./roguelike/items"
require "./roguelike/loot"
require "./roguelike/inventory"
require "./roguelike/slot"
require "./roguelike/equipment"
require "./roguelike/lore"
require "./roguelike/message_log"
require "./roguelike/world"
require "./roguelike/player"
require "./roguelike/game"
require "./roguelike/save"
require "./roguelike/trial"
require "./roguelike/debug/naming"
require "./roguelike/debug/console"
require "./roguelike/ui"
require "./roguelike/session"
require "./roguelike/cli"
