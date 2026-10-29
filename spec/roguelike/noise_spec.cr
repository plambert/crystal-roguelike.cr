require "../spec_helper"

Spectator.describe Roguelike::Noise do
  alias Floor = Roguelike::Floor
  alias Noise = Roguelike::Noise

  # Two rooms with a wall between them and a shut door in it.
  ROOMS = [
    "###########",
    "#....#....#",
    "#....+....#",
    "#....#....#",
    "###########",
  ]

  # The same two rooms with no way between them.
  SEALED = [
    "###########",
    "#....#....#",
    "#....#....#",
    "#....#....#",
    "###########",
  ]

  def spread(rows : Array(String), at : {Int32, Int32}, loudness : Int32)
    Noise.spread Floor.parse("noise", rows), at, loudness
  end

  describe ".spread" do
    it "counts one square of travel a step, diagonals included" do
      reach = spread ROOMS, {1, 1}, 10

      expect(reach[{1, 1}]).to eq 0
      expect(reach[{2, 2}]).to eq 1
      expect(reach[{4, 3}]).to eq 3
    end

    it "goes no further than its loudness" do
      reach = spread ROOMS, {1, 1}, 2

      expect(reach[{3, 3}]).to eq 2
      expect(reach[{4, 1}]).to be_nil
    end

    it "is stopped by a wall" do
      reach = spread SEALED, {4, 2}, 20

      expect(reach[{6, 2}]).to be_nil
      expect(reach[{5, 2}]).to be_nil
    end

    it "loses what a shut door muffles on the way through" do
      reach = spread ROOMS, {4, 2}, 20

      expect(reach[{5, 2}]).to eq 1 + Noise::MUFFLE
      expect(reach[{6, 2}]).to eq 2 + Noise::MUFFLE
    end

    it "carries round through an open doorway as far as the floor goes" do
      open = ROOMS.map &.tr("+", "'")
      reach = spread open, {4, 2}, 20

      expect(reach[{6, 2}]).to eq 2
      expect(reach[{9, 3}]).to eq 5
    end
  end

  describe "the sources" do
    it "gives every source some travel" do
      Noise::Source.values.each do |source|
        expect(source.loudness).to be > 0
      end
    end

    it "makes a door giving way louder than a swing at it" do
      expect(Noise::Source::DoorBroken.loudness).to be > Noise::Source::DoorStruck.loudness
    end

    it "has the loudest source as the top of the bar" do
      expect(Noise::LOUDEST).to eq Noise::Source.values.max_of(&.loudness)
    end
  end

  describe Roguelike::Noise::Echo do
    it "carries as far as its furthest square" do
      reach = spread SEALED, {1, 1}, 20
      echo = Noise::Echo.new({1, 1}, 20, reach)

      expect(echo.carried).to eq 3
    end
  end
end
