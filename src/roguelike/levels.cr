require "./level"

module Roguelike
  # The levels that ship with the game.
  #
  # Read into the binary at build time rather than off the disk at run time,
  # so the game works from any directory and a level cannot go missing between
  # building it and playing it. The files under `data/levels` stay the form
  # they are written and reviewed in.
  module Levels
    PROVING_GROUND = {{ read_file("#{__DIR__}/../../data/levels/proving-ground.map") }}

    # The level everything is tried out on until there is a generator.
    def self.proving_ground : Level
      Level.parse "proving-ground", PROVING_GROUND
    end
  end
end
