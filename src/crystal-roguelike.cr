# A terminal roguelike.
#
# The shard is named `crystal-roguelike`, so this file is where `require
# "crystal-roguelike"` lands, but the namespace is `Roguelike`: `Crystal` is
# the compiler's own, and game types have no business sitting beside
# `Crystal::System`.
module Roguelike
  {% begin %}
  {% command = "shards version '" + __DIR__.gsub(%r{'}, "'\\''") + "'" %}
  VERSION = {{ `#{command.id}`.strip.stringify }}
  {% end %}
end

require "./roguelike/rng"
require "./roguelike/direction"
require "./roguelike/terrain"
require "./roguelike/tile"
require "./roguelike/level"
require "./roguelike/levels"
require "./roguelike/world"
require "./roguelike/ui"
require "./roguelike/session"
require "./roguelike/cli"
