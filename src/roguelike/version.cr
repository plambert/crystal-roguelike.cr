require "../roguelike"

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
  #
  # Windows runs a macro's command with no shell, and its command line quotes
  # only with double quotes. A Windows path cannot hold a double quote, so
  # none needs escaping there.
  {% begin %}
  {% if flag?(:win32) %}
    {% command = "shards version \"" + __DIR__ + "\"" %}
  {% else %}
    {% command = "shards version '" + __DIR__.gsub(%r{'}, "'\\''") + "'" %}
  {% end %}
  VERSION = {{ `#{command.id}`.strip.stringify }}
  {% end %}

  # The commit this binary was built from.
  #
  # `script/build_id.cr` answers it: the short hash, with a "+" after it when a
  # tracked file differed from that commit, and "unknown" when there was no
  # repository to ask. Built as another shard's dependency, it is the commit
  # `shards install` checked out. The debug console prints it beside `VERSION`, so a
  # screenshot of a failure says which build it came from.
  #
  # The `run` macro compiles and runs it, which needs no shell on any platform.
  BUILD = {{ run("../../script/build_id", __DIR__).stringify.strip }}

  # Whether this is a test build, compiled with `-Dtest_build`.
  #
  # A test build records every run it plays. See `Replay::Log.always`.
  TEST_BUILD = {{ flag?(:test_build) }}

  # The version as a person reads it, which says when this is a test build.
  EDITION = TEST_BUILD ? "#{VERSION} (test build)" : VERSION
end
