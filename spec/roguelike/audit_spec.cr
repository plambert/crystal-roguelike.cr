require "../spec_helper"

Spectator.describe Roguelike::Audit do
  alias Area = Roguelike::Area
  alias Audit = Roguelike::Audit
  alias Floor = Roguelike::Floor

  # Two rooms joined by one corridor, with a staircase in each.
  SOUND = <<-MAP
    ###############
    #....##########
    #.<..+.....####
    #....#####.####
    ##########.####
    ####.....'.####
    ####..>..######
    ####.....######
    ###############
    MAP

  # The two rooms of `SOUND`.
  ROOMS = [Area.new(1, 1, 4, 3), Area.new(4, 5, 5, 3)]

  def floor(map : String) : Floor
    Floor.parse "sample", map
  end

  describe ".faults" do
    it "finds nothing wrong with a sound floor" do
      expect(Audit.faults floor(SOUND), ROOMS).to be_empty
    end

    it "finds a staircase missing" do
      found = Audit.faults floor(SOUND.sub('>', '.'))

      expect(found).to contain "0 down staircases"
    end

    it "finds squares out of reach" do
      cut_off = floor(SOUND)
      cut_off.set 13, 7, Roguelike::Terrain::StoneFloor

      found = Audit.faults cut_off

      expect(found.any? &.starts_with?("1 square out of reach")).to be_true
    end

    it "finds a door hanging from nothing" do
      loose = floor SOUND
      loose.set 13, 2, Roguelike::Terrain::ClosedDoor

      expect(Audit.faults(loose).any? &.starts_with?("a door hanging")).to be_true
    end

    it "finds a corridor that ends nowhere" do
      spur = floor SOUND
      spur.set 10, 2, Roguelike::Terrain::StoneFloor
      spur.set 11, 2, Roguelike::Terrain::StoneFloor

      expect(Audit.faults(spur).any? &.starts_with?("a corridor ending nowhere at 11,2")).to be_true
    end

    it "finds a room below the smallest there is" do
      found = Audit.faults floor(SOUND), [Area.new(1, 1, 3, 3), ROOMS[1]]

      expect(found).to contain "a room of 3 by 3 at 1,1"
    end

    it "finds both staircases in one room" do
      found = Audit.faults floor(SOUND), [Area.new(1, 1, 8, 7)]

      expect(found).to contain "both staircases in the room at 1,1"
    end

    it "finds a creature inside rock" do
      buried = floor SOUND
      buried.place Roguelike::Monster.new(Roguelike::Species::Slime, 0, 0, "band-rock")

      expect(Audit.faults(buried)).to contain "a creature in rock at 0,0"
    end
  end

  describe ".loops" do
    it "finds none where the rooms and corridors make a tree" do
      expect(Audit.loops floor(SOUND)).to eq 0
    end

    it "finds one for each body of rock the open squares go round" do
      ring = floor <<-MAP
        #########
        #.......#
        #.##.##.#
        #.......#
        #########
        MAP

      expect(Audit.loops ring).to eq 2
    end

    it "leaves out the bodies smaller than it was asked to count" do
      ring = floor <<-MAP
        ##########
        #........#
        #.#..###.#
        #....###.#
        #........#
        ##########
        MAP

      expect(Audit.loops ring).to eq 2
      expect(Audit.loops ring, 4).to eq 1
    end
  end

  describe ".alongside" do
    it "finds two corridors running side by side" do
      pair = floor <<-MAP
        ############
        #...########
        #...+......#
        #...+......#
        #...########
        ############
        MAP

      expect(Audit.alongside pair).to eq 1
    end

    it "finds none along one corridor" do
      expect(Audit.alongside floor(SOUND)).to eq 0
    end
  end
end
