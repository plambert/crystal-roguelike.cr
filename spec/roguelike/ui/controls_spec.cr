require "../../spec_helper"

Spectator.describe Roguelike::Ui::Controls do
  alias Controls = Roguelike::Ui::Controls
  alias Direction = Roguelike::Direction
  alias ControlScheme = Roguelike::Options::ControlScheme

  it "maps Traditional movement keys to the existing directions" do
    expect(Controls.moves(ControlScheme::Traditional)).to eq({
      "h" => Direction::West,
      "j" => Direction::South,
      "k" => Direction::North,
      "l" => Direction::East,
      "y" => Direction::NorthWest,
      "u" => Direction::NorthEast,
      "b" => Direction::SouthWest,
      "n" => Direction::SouthEast,
    })
  end

  it "maps Modern movement keys spatially without installing them" do
    expect(Controls.moves(ControlScheme::Modern)).to eq({
      "a" => Direction::West,
      "s" => Direction::South,
      "w" => Direction::North,
      "d" => Direction::East,
      "q" => Direction::NorthWest,
      "e" => Direction::NorthEast,
      "z" => Direction::SouthWest,
      "x" => Direction::SouthEast,
    })
  end
end
