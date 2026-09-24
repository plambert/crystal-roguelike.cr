# A terminal roguelike.
#
# The shard is named `crystal-roguelike`. The namespace is `Roguelike`
# instead. `Crystal` is the compiler's own namespace, and game types do not
# belong beside `Crystal::System`.
#
# This file holds what this build is, as two strings. It requires nothing, so
# a program that wants the version and not the game requires it on its own.
# `src/crystal-roguelike.cr` requires it too, and both names are where they
# have always been.
module Roguelike
  # The version in `shard.yml`. The compiler reads it at build time.
  {% begin %}
  {% command = "shards version '" + __DIR__.gsub(%r{'}, "'\\''") + "'" %}
  VERSION = {{ `#{command.id}`.strip.stringify }}
  {% end %}

  # The commit this binary was built from.
  #
  # `script/build-id` answers it: the short hash, with a "+" after it when a
  # tracked file differed from that commit, and "unknown" when there was no
  # repository to ask. The debug console prints it beside `VERSION`, so a
  # screenshot of a failure says which build it came from.
  {% begin %}
  {% root = __DIR__.gsub(%r{'}, "'\\''") %}
  {% command = "sh '" + root + "/../../script/build-id' '" + root + "'" %}
  BUILD = {{ `#{command.id}`.strip.stringify }}
  {% end %}
end
