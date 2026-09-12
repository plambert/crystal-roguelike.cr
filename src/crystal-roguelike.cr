# TODO: Write documentation for `Crystal::Roguelike`
module Crystal::Roguelike
  {% begin %}
  {% command = "shards version '" + __DIR__.gsub(%r{'}, "'\\''") + "'" %}
  VERSION = {{ `#{command.id}`.strip.stringify }}
  {% end %}

  # TODO: Put your code here
end
