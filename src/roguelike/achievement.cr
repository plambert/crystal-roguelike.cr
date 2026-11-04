require "json"
require "../roguelike"

module Roguelike
  # Something the character did that a scoreboard counts, and when.
  #
  # It is plain data, so it can go to a web scoreboard or to Steam as it
  # is. The name is a string and not an enum, because those services know
  # an achievement by its name.
  #
  # *turn* is the game turn it was earned on. *earned* is the wall clock
  # time. A replay earns it again at another time, so the streamed
  # fingerprint leaves *earned* out.
  struct Achievement
    include JSON::Serializable

    # What a character earns the first time they eat one of their own
    # species.
    CANNIBAL = "cannibal"

    getter name : String
    getter turn : Int32

    @[JSON::Field(ignore_serialize: Roguelike::Fingerprint.streaming?)]
    getter earned : Time

    def initialize(@name : String, @turn : Int32, @earned : Time)
    end
  end
end
