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
require "./roguelike/attributes"
require "./roguelike/advancement"
require "./roguelike/terrain"
require "./roguelike/tile"
require "./roguelike/level"
require "./roguelike/levels"
require "./roguelike/dice"
require "./roguelike/item_kind"
require "./roguelike/item"
require "./roguelike/items"
require "./roguelike/inventory"
require "./roguelike/lore"
require "./roguelike/message_log"
require "./roguelike/world"
require "./roguelike/player"
require "./roguelike/game"
require "./roguelike/ui"
require "./roguelike/session"
require "./roguelike/cli"
