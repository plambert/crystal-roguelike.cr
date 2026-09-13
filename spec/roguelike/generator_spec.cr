require "../spec_helper"

Spectator.describe Roguelike::Generator do
  alias Generator = Roguelike::Generator
  alias Area = Roguelike::Area
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Rng = Roguelike::Rng
  alias Terrain = Roguelike::Terrain

  # How many floors the examples about every floor dig.
  #
  # The Verify line for this phase asks for a thousand. One floor takes about
  # two milliseconds to dig and a little more to walk, so a thousand is a
  # second or two of the suite.
  RUNS = 1000

  # The first seed they dig from. A failure names a run somebody can start.
  FIRST = 1_u64

  # The floor seed *number* digs.
  def dug(number : UInt64) : Floor
    Generator.floor Rng.new(number)
  end

  # The generators every example about every floor reads.
  #
  # Digging is most of the work, so each floor is dug once and shared.
  # Nothing in this file writes to one. The generator is kept rather than the
  # floor alone, because a spec about the rooms needs the rectangles the
  # generator cut and a floor carries only the squares.
  DUG = (0...RUNS).map do |index|
    Generator.new(Rng.new(FIRST + index), "dungeon",
      Generator::COLUMNS, Generator::ROWS).tap &.dig
  end

  # What the block found wrong with each of `RUNS` floors.
  #
  # The block answers a sentence naming the seed, or `nil` when the floor is
  # sound. A failure then reads as a list of seeds somebody can dig again
  # rather than as one expectation that went red on an unnamed floor.
  def complaints(& : Generator, UInt64 -> String?) : Array(String)
    found = [] of String

    DUG.each_with_index do |generator, index|
      said = yield generator, FIRST + index
      found << said if said
    end

    found
  end

  # Every square of *floor* that can be reached from *from*.
  #
  # A shut door is crossed. Walking into one opens it, so a shut door does
  # not cut a floor in two.
  def reachable(floor : Floor, from : {Int32, Int32}) : Set({Int32, Int32})
    found = Set({Int32, Int32}).new
    queue = [from]

    while spot = queue.pop?
      next if found.includes? spot

      found << spot

      Direction.values.each do |direction|
        where = direction.from spot[0], spot[1]
        next unless floor.contains? where[0], where[1]
        next if floor.terrain(where[0], where[1]).rock?
        next if found.includes? where

        queue << where
      end
    end

    found
  end

  # Every square of *floor* that is not rock.
  def open(floor : Floor) : Set({Int32, Int32})
    found = Set({Int32, Int32}).new
    floor.each do |column, row, tile|
      found << {column, row} unless tile.terrain.rock?
    end

    found
  end

  # Where *terrain* is on *floor*. Empty when it is nowhere.
  def where(floor : Floor, terrain : Terrain) : Array({Int32, Int32})
    found = [] of {Int32, Int32}
    floor.each do |column, row, tile|
      found << {column, row} if tile.terrain == terrain
    end

    found
  end

  describe "one floor" do
    it "is the size it was asked for" do
      floor = dug FIRST

      expect(floor.columns).to eq Generator::COLUMNS
      expect(floor.rows).to eq Generator::ROWS
    end

    it "takes the id it was asked for" do
      expect(Generator.floor(Rng.new(FIRST), "cellar").id).to eq "cellar"
    end

    it "cuts rooms into it" do
      rooms = Generator.new(Rng.new(FIRST), "dungeon", 72, 28).tap(&.dig).rooms

      expect(rooms.size).to be > 4
      expect(rooms.all? { |room| room.columns >= 4 && room.rows >= 3 }).to be_true
    end

    it "leaves a square of rock between two rooms" do
      generator = Generator.new Rng.new(FIRST), "dungeon", 72, 28
      generator.dig

      generator.rooms.each_with_index do |room, index|
        generator.rooms.each_with_index do |other, another|
          next if index == another

          apart = room.x > other.right + 1 || other.x > room.right + 1 ||
                  room.y > other.bottom + 1 || other.y > room.bottom + 1
          expect(apart).to be_true
        end
      end
    end

    it "round-trips through serialization" do
      floor = dug FIRST

      expect(Floor.from_json floor.to_json).to eq floor
    end
  end

  # The Verify line for this phase, one example each.
  describe "every floor" do
    # `--seed N` twice gives the identical floor.
    it "digs the same floor from the same seed" do
      again = (0...200).map { |index| dug(FIRST + index).to_map }

      expect(again).to eq DUG.first(200).map &.floor.to_map
    end

    it "digs a different floor from a different seed" do
      drawn = DUG.first(100).map &.floor.to_map.join

      expect(drawn.uniq.size).to eq drawn.size
    end

    it "reaches every open square from the up staircase" do
      found = complaints do |generator, seed|
        floor = generator.floor
        up = where(floor, Terrain::StairsUp).first?
        next "seed #{seed} has no up staircase" unless up

        missed = open(floor) - reachable(floor, up)
        next if missed.empty?

        "seed #{seed} cannot reach #{missed.size} squares, one at #{missed.to_a.first}"
      end

      expect(found).to be_empty
    end

    it "puts both staircases on it, in different rooms" do
      found = complaints do |generator, seed|
        floor = generator.floor
        up = where floor, Terrain::StairsUp
        down = where floor, Terrain::StairsDown

        next "seed #{seed} has #{up.size} up staircases" unless up.size == 1
        next "seed #{seed} has #{down.size} down staircases" unless down.size == 1
        next unless up.first == down.first

        "seed #{seed} has both staircases on #{up.first}"
      end

      expect(found).to be_empty
    end

    it "leaves no door with a wall on one side of it" do
      found = complaints do |generator, seed|
        floor = generator.floor
        hanging = [Terrain::ClosedDoor, Terrain::OpenDoor].flat_map do |kind|
          where(floor, kind).reject { |spot| hangs? floor, spot }
        end
        next if hanging.empty?

        "seed #{seed} has a door hanging from nothing at #{hanging.first}"
      end

      expect(found).to be_empty
    end

    it "puts nothing inside rock" do
      found = complaints do |generator, seed|
        floor = generator.floor
        buried = [] of String

        floor.each_monster do |column, row, creature|
          next unless floor.terrain(column, row).rock?

          buried << "a #{creature.label} at #{column},#{row}"
        end

        floor.each_pile do |column, row, _pile|
          next unless floor.terrain(column, row).rock?

          buried << "a pile at #{column},#{row}"
        end

        floor.each_fixture do |column, row, _fitting|
          next unless floor.terrain(column, row).rock?

          buried << "a fixture at #{column},#{row}"
        end

        next if buried.empty?

        "seed #{seed} has #{buried.first} in rock"
      end

      expect(found).to be_empty
    end

    it "puts no creature in the room the character arrives in" do
      found = complaints do |generator, seed|
        floor = generator.floor
        up = where(floor, Terrain::StairsUp).first?
        next "seed #{seed} has no up staircase" unless up

        room = generator.rooms.find &.holds?(up[0], up[1])
        next "seed #{seed} has its up staircase outside every room" unless room

        standing = [] of String
        floor.each_monster do |column, row, creature|
          next unless room.holds? column, row

          standing << "#{creature.label} at #{column},#{row}"
        end
        next if standing.empty?

        "seed #{seed} starts beside #{standing.first}"
      end

      expect(found).to be_empty
    end

    it "gives every creature a band of its own" do
      found = complaints do |generator, seed|
        floor = generator.floor
        bands = [] of String
        floor.each_monster { |_column, _row, creature| bands << creature.band }

        next "seed #{seed} shares a band" unless bands.uniq.size == bands.size

        lost = bands.find { |id| floor.band(id).nil? }
        next unless lost

        "seed #{seed} lost band #{lost}"
      end

      expect(found).to be_empty
    end
  end

  # Whether the door on *spot* has a way off it on two opposite sides.
  #
  # A door hangs in a gap in a wall. Floor on two facing sides is what makes
  # it a gap rather than a hole in the middle of a room.
  def hangs?(floor : Floor, spot : {Int32, Int32}) : Bool
    ways = Direction.values.select do |direction|
      next false if direction.diagonal?

      where = direction.from spot[0], spot[1]
      floor.contains?(where[0], where[1]) &&
        !floor.terrain(where[0], where[1]).rock?
    end

    ways.size >= 2 && ways.any? { |one| ways.includes? one.opposite }
  end

  describe "what is on a floor" do
    it "puts sconces on the walls of rooms" do
      lit = 0
      10.times { |index| lit += dug(FIRST + index).fixtures.size }

      expect(lit).to be > 0
    end

    it "lights some of them" do
      burning = 0
      10.times do |index|
        dug(FIRST + index).each_fixture do |_column, _row, fitting|
          burning += 1 if fitting.lit?
        end
      end

      expect(burning).to be > 0
    end

    it "bolts every sconce to a wall" do
      10.times do |index|
        floor = dug FIRST + index

        floor.each_fixture do |column, row, fitting|
          wall = fitting.attached
          expect(wall).not_to be_nil

          next unless wall

          behind = wall.from column, row
          expect(!floor.contains?(behind[0], behind[1]) ||
                 floor.terrain(behind[0], behind[1]).rock?).to be_true
        end
      end
    end

    it "puts creatures on it" do
      creatures = 0
      10.times { |index| creatures += dug(FIRST + index).monsters.size }

      expect(creatures).to be > 0
    end

    it "leaves it dark" do
      expect(dug(FIRST).ambient).to eq 0
    end
  end

  describe "Game.dug" do
    it "plays on a floor the generator dug" do
      game = Roguelike::Game.dug Rng.new(FIRST)

      expect(game.floor.id).to eq "dungeon"
      expect(game.floor.to_map).to eq dug(FIRST).to_map
    end

    it "puts the character on the up staircase" do
      game = Roguelike::Game.dug Rng.new(FIRST)

      expect(game.standing_on).to eq Terrain::StairsUp
    end

    it "scatters loot over it" do
      game = Roguelike::Game.dug Rng.new(FIRST)
      piles = 0
      game.floor.each_pile { |_column, _row, _pile| piles += 1 }

      expect(piles).to be > 0
    end

    it "gives its creatures what they carry" do
      game = Roguelike::Game.dug Rng.new(FIRST)
      carried = 0
      game.floor.each_monster { |_c, _r, creature| carried += creature.carrying.size }

      expect(carried).to be > 0
    end

    it "plays the floor that ships when it is asked to" do
      game = Roguelike::Game.start Rng.new(FIRST)

      expect(game.floor.id).to eq "proving-ground"
    end
  end

  describe "Area" do
    it "answers its far edges" do
      area = Area.new 3, 4, 10, 6

      expect(area.right).to eq 12
      expect(area.bottom).to eq 9
      expect(area.middle).to eq({8, 7})
    end

    it "says what it holds" do
      area = Area.new 3, 4, 10, 6

      expect(area.holds? 3, 4).to be_true
      expect(area.holds? 12, 9).to be_true
      expect(area.holds? 13, 9).to be_false
      expect(area.holds? 2, 4).to be_false
    end

    it "insets by a margin on every side" do
      expect(Area.new(3, 4, 10, 6).inset 1).to eq Area.new(4, 5, 8, 4)
    end

    it "yields every square in reading order" do
      found = [] of {Int32, Int32}
      Area.new(1, 1, 2, 2).each { |column, row| found << {column, row} }

      expect(found).to eq [{1, 1}, {2, 1}, {1, 2}, {2, 2}]
    end
  end

  describe "drawn" do
    # One floor written out, so a change to any of the rules shows as a diff
    # of two maps rather than as a count that moved.
    it "digs what it dug last time" do
      drawn = dug(FIRST).to_map.join "\n"

      expect(drawn).to eq Fixture.expected("floors/dug.txt", drawn)
    end
  end
end
