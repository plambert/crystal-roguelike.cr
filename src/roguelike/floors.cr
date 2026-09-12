require "./floor"

module Roguelike
  # The floors that ship with the game.
  #
  # The compiler reads each map file at build time. The binary then holds the
  # text. The game runs from any directory. A floor file cannot go missing
  # between a build and a run.
  #
  # The files under `data/floors` stay the form a person writes and reviews.
  module Floors
    PROVING_GROUND = {{ read_file("#{__DIR__}/../../data/floors/proving-ground.map") }}

    # The floor the game uses until there is a generator.
    def self.proving_ground : Floor
      Floor.parse "proving-ground", PROVING_GROUND
    end
  end
end
