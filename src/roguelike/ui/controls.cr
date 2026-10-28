require "../../crystal-roguelike"

module Roguelike::Ui
  # The directional keys each control scheme uses, without installing them.
  module Controls
    # Movement keys mapped to their directions for *scheme*.
    def self.moves(scheme : Options::ControlScheme) : Hash(String, Direction)
      case scheme
      in .traditional?
        {
          "h" => Direction::West,
          "j" => Direction::South,
          "k" => Direction::North,
          "l" => Direction::East,
          "y" => Direction::NorthWest,
          "u" => Direction::NorthEast,
          "b" => Direction::SouthWest,
          "n" => Direction::SouthEast,
        }
      in .modern?
        {
          "a" => Direction::West,
          "s" => Direction::South,
          "w" => Direction::North,
          "d" => Direction::East,
          "q" => Direction::NorthWest,
          "e" => Direction::NorthEast,
          "z" => Direction::SouthWest,
          "x" => Direction::SouthEast,
        }
      end
    end
  end
end
