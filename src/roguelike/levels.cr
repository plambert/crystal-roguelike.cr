require "./level"

module Roguelike
  # The levels that ship with the game.
  #
  # The compiler reads each map file at build time. The binary then holds the
  # text. The game runs from any directory. A level file cannot go missing
  # between a build and a run.
  #
  # The files under `data/levels` stay the form a person writes and reviews.
  module Levels
    PROVING_GROUND = {{ read_file("#{__DIR__}/../../data/levels/proving-ground.map") }}

    # The level the game uses until there is a generator.
    def self.proving_ground : Level
      Level.parse "proving-ground", PROVING_GROUND
    end
  end
end
