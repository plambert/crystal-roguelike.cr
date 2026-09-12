require "../spec_helper"

Spectator.describe Roguelike::Vision do
  alias Floor = Roguelike::Floor
  alias Source = Roguelike::LightSource
  alias Terrain = Roguelike::Terrain
  alias Vision = Roguelike::Vision

  def spot(lines : Array(String)) : Floor
    Floor.parse "vision", lines
  end

  describe "in the dark" do
    # A person in the dark knows where their own feet are and nothing else.
    it "sees the square it stands on and no other" do
      floor = spot ["#####", "#...#", "#...#", "#####"]
      vision = Vision.from floor, 2, 2, [] of Source

      expect(vision.includes? 2, 2).to be_true
      expect(vision.includes? 1, 1).to be_false
      expect(vision.size).to eq 1
    end
  end

  describe "the two rules together" do
    # A square has to be both in the line of sight and lit.
    it "refuses a lit square with no line to it" do
      floor = spot ["#######", "#..#..#", "#######"]
      vision = Vision.from floor, 1, 1, [Source.new(5, 1, 4)]

      expect(vision.includes? 5, 1).to be_false
    end

    it "refuses an unlit square with a line to it" do
      floor = Floor.solid "open", 9, 1, Terrain::StoneFloor
      vision = Vision.from floor, 0, 0, [Source.new(0, 0, 3)]

      expect(vision.includes? 2, 0).to be_true
      expect(vision.includes? 8, 0).to be_false
    end

    # A distant lit room is visible across a dark one. The line runs the whole
    # way and the far end is the part with light on it.
    it "takes a square that is both" do
      floor = Floor.solid "open", 20, 1, Terrain::StoneFloor
      vision = Vision.from floor, 0, 0, [Source.new(17, 0, 3)]

      expect(vision.includes? 10, 0).to be_false
      expect(vision.includes? 17, 0).to be_true
      expect(vision.includes? 19, 0).to be_true
    end
  end

  describe "with no lighting at all" do
    # A spec that is not about light says nothing about light.
    it "lights everything it has a line to" do
      floor = spot ["#####", "#...#", "#...#", "#####"]
      vision = Vision.lit floor, 2, 2

      expect(vision.lighting).to be_nil
      expect(vision.includes? 1, 1).to be_true
      expect(vision.size).to eq 20
    end
  end

  describe "#each" do
    it "yields every square it answers true for, and each once" do
      floor = Floor.solid "open", 9, 1, Terrain::StoneFloor
      vision = Vision.from floor, 0, 0, [Source.new(0, 0, 3)]

      seen = [] of {Int32, Int32}
      vision.each { |square| seen << square }

      expect(seen.size).to eq vision.size
      expect(seen.to_set.size).to eq seen.size
      expect(seen.all? { |square| vision.includes? square }).to be_true
    end
  end

  describe "#light" do
    it "says how much light a square has" do
      floor = Floor.solid "open", 9, 1, Terrain::StoneFloor
      vision = Vision.from floor, 4, 0, [Source.new(4, 0, 3)]

      expect(vision.light 4, 0).to eq 4
      expect(vision.light 8, 0).to eq 0
    end

    it "answers nothing with no lighting" do
      expect(Vision.lit(Floor.solid("open", 3, 1, Terrain::StoneFloor), 1, 0).light(1, 0)).to eq 0
    end
  end
end
