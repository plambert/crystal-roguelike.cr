require "../spec_helper"

Spectator.describe Roguelike::Generator do
  alias Generator = Roguelike::Generator
  alias Area = Roguelike::Area
  alias Direction = Roguelike::Direction
  alias Floor = Roguelike::Floor
  alias Layout = Roguelike::Layout
  alias Audit = Roguelike::Audit
  alias Rng = Roguelike::Rng
  alias Terrain = Roguelike::Terrain

  # How many floors the examples about every floor dig.
  #
  # `script/floor-stats.cr` digs a thousand and prints what they come to.
  # This many covers every layout several times over in a spec run.
  RUNS = 120

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
    Generator.dug Rng.new(FIRST + index), Roguelike::World.id(1)
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
      floor = Generator.floor Rng.new(FIRST), columns: 100, rows: 40

      expect(floor.columns).to eq 100
      expect(floor.rows).to eq 40
    end

    it "takes the id it was asked for" do
      expect(Generator.floor(Rng.new(FIRST), "cellar").id).to eq "cellar"
    end

    it "cuts rooms into it" do
      rooms = Generator.new(Rng.new(FIRST), "dungeon", 72, 28, layout: Layout::Tree).tap(&.dig).rooms

      expect(rooms.size).to be > 4
      expect(rooms.all? { |room| room.columns >= 4 && room.rows >= 3 }).to be_true
    end

    it "leaves a square of rock between two rooms" do
      generator = Generator.new Rng.new(FIRST), "dungeon", 72, 28, layout: Layout::Tree
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
    # How many floors the two examples about the seed dig again.
    #
    # Fewer than `RUNS`. Both of these dig every floor a second time, and one
    # of them holds every map in memory at once.
    TWICE = 40

    # `--seed N` twice gives the identical floor.
    it "digs the same floor from the same seed" do
      again = (0...TWICE).map { |index| dug(FIRST + index).to_map }

      expect(again).to eq DUG.first(TWICE).map &.floor.to_map
    end

    it "digs a different floor from a different seed" do
      drawn = DUG.first(TWICE).map &.floor.to_map.join

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

        room = generator.zones.find &.holds?(up[0], up[1])
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

    it "gives every creature a band the floor knows" do
      found = complaints do |generator, seed|
        floor = generator.floor
        bands = [] of String
        floor.each_monster { |_column, _row, creature| bands << creature.band }

        lost = bands.find { |id| floor.band(id).nil? }
        "seed #{seed} lost band #{lost}" if lost
      end

      expect(found).to be_empty
    end
  end

  describe "who lives on a floor" do
    # The floors deeper than the first that these examples dig, by depth.
    DEEP = (1..5).to_h do |depth|
      {depth, (0...12).map { |index| Generator.floor Rng.new(FIRST + index), depth: depth }}
    end

    # Every band on *floor*, and the kinds of its members.
    def bands(floor : Floor) : Hash(String, Array(Roguelike::Kind))
      found = {} of String => Array(Roguelike::Kind)
      floor.each_monster do |_column, _row, creature|
        (found[creature.band] ||= [] of Roguelike::Kind) << creature.kind
      end
      found
    end

    it "places only kinds that appear at the floor's depth" do
      DEEP.each do |depth, floors|
        floors.each do |floor|
          floor.each_monster do |_column, _row, creature|
            expect(creature.kind.appears_at? depth).to be_true
          end
        end
      end
    end

    it "places every kind somewhere on the five floors" do
      found = Set(Roguelike::Kind).new
      DEEP.each_value do |floors|
        floors.each { |floor| floor.each_monster { |_column, _row, creature| found << creature.kind } }
      end

      expect(found).to eq Roguelike::Kind.values.to_set
    end

    it "puts a scout in a room by itself" do
      scouts = 0

      DEEP.each_value do |floors|
        floors.each do |floor|
          bands(floor).each_value do |kinds|
            next unless kinds.any? &.alone?

            scouts += 1
            expect(kinds.size).to eq 1
          end
        end
      end

      expect(scouts).to be > 0
    end

    it "keeps each band to one species" do
      DEEP.each_value do |floors|
        floors.each do |floor|
          bands(floor).each_value do |kinds|
            expect(kinds.map(&.species).uniq!.size).to eq 1
          end
        end
      end
    end

    it "puts more than one creature in some bands" do
      shared = DEEP.values.flatten.sum { |floor| bands(floor).count &.[1].size.>(1) }

      expect(shared).to be > 0
    end

    it "rolls hit points within each kind's hit dice" do
      DEEP.each_value do |floors|
        floors.each do |floor|
          floor.each_monster do |_column, _row, creature|
            dice = creature.kind.hit_dice

            expect(creature.max_hit_points).to be_between(dice.minimum, dice.maximum)
            expect(creature.hit_points).to eq creature.max_hit_points
          end
        end
      end
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

  describe ".size" do
    # How many sizes the examples draw. Drawing one rolls five numbers.
    SIZES = (0...1000).map { |index| Generator.size Rng.new(FIRST + index), "floor-1" }

    it "draws an area from a quarter of the average to four times it" do
      areas = SIZES.map { |size| size[0] * size[1] / Generator::AREA.to_f }

      expect(areas.min).to be >= 0.24
      expect(areas.max).to be <= 4.1
    end

    it "centres the area on the average" do
      areas = SIZES.map { |size| size[0] * size[1] / Generator::AREA.to_f }.sort!

      expect(areas[areas.size // 2]).to be_within(0.1).of(1.0)
    end

    it "draws a bell rather than a flat spread" do
      areas = SIZES.map { |size| size[0] * size[1] / Generator::AREA.to_f }
      middle = areas.count { |area| area >= 0.7 && area <= 1.4 }

      expect(middle).to be > SIZES.size // 2
    end

    it "favors the squarer shapes" do
      square = SIZES.count { |size| (size[0] - size[1]).abs * 4 < size[1] }
      long = SIZES.count { |size| size[0] > size[1] * 5 // 2 }

      expect(square).to be > long
    end

    it "keeps a floor's size when it is dug again" do
      first = Generator.new(Rng.new(FIRST), "floor-3", depth: 3).floor
      retried = Generator.new(Rng.new(FIRST), "floor-3", depth: 3, attempt: 2).floor

      expect({retried.columns, retried.rows}).to eq({first.columns, first.rows})
    end

    it "draws each floor's size on its own" do
      sizes = (1..5).map { |depth| Generator.size Rng.new(FIRST), Roguelike::World.id(depth) }

      expect(sizes.uniq.size).to be > 1
    end
  end

  describe "layouts" do
    it "digs every layout, the tree most often" do
      counted = DUG.map(&.layout).tally

      expect(counted.keys.to_set).to eq Layout.values.to_set
      expect(counted[Layout::Tree]).to be > counted[Layout::Grid]
      expect(counted[Layout::Tree]).to be > counted[Layout::Cave]
    end

    it "fills part of some trees another way" do
      expect(DUG.count { |generator| generator.layout.tree? && !generator.mixed.empty? }).to be > 0
    end

    # A walk with one hand on the wall goes round a body of rock that no edge
    # touches and never sees the far side of it.
    it "digs some floors with loops a walk along one wall cannot cover" do
      looped = DUG.count { |generator| Audit.loops(generator.floor, 40) >= 5 }

      expect(looped).to be > RUNS // 5
    end

    # The first room a tree cuts is in its top left corner, until the floor
    # is mirrored.
    it "mirrors trees across, down, both ways and neither" do
      corners = DUG.select(&.layout.tree?).map do |generator|
        first = generator.rooms.first
        {first.x * 2 < generator.floor.columns, first.y * 2 < generator.floor.rows}
      end

      expect(corners.uniq.size).to eq 4
    end
  end

  describe "the audit" do
    it "finds nothing wrong with any floor" do
      found = complaints do |generator, seed|
        faults = Audit.faults generator.floor, generator.rooms
        "seed #{seed}: #{faults.join(", ")}" unless faults.empty?
      end

      expect(found).to be_empty
    end

    it "finds two corridors side by side on few floors" do
      pairs = DUG.sum { |generator| Audit.alongside generator.floor }

      expect(pairs).to be < RUNS // 10
    end

    it "digs again when a try is faulted, and stops after the last" do
      generator = Generator.dug Rng.new(FIRST), "cramped", columns: 12, rows: 8

      expect(generator.attempt).to eq Generator::TRIES - 1
      expect(generator.rejected).not_to be_empty
    end

    it "digs again the same way from the same seed" do
      first = Generator.dug Rng.new(FIRST), "cramped", columns: 12, rows: 8
      again = Generator.dug Rng.new(FIRST), "cramped", columns: 12, rows: 8

      expect(again.floor.to_map).to eq first.floor.to_map
      expect(again.rejected).to eq first.rejected
    end
  end

  describe "the staircases of two floors" do
    # Nothing places a staircase from the floor above or below it, so the
    # down staircase of one floor and the up staircase of the next fall
    # where they fall.
    it "do not line up" do
      lined = (0...40).count do |index|
        above = Generator.floor Rng.new(FIRST + index), Roguelike::World.id(1), 1
        below = Generator.floor Rng.new(FIRST + index), Roguelike::World.id(2), 2

        above.find(Terrain::StairsDown) == below.find(Terrain::StairsUp)
      end

      expect(lined).to eq 0
    end
  end

  describe "what lives on a floor of any size" do
    # Creatures per thousand open squares, over a few floors of *columns* by
    # *rows*.
    def crowding(columns : Int32, rows : Int32) : Float64
      creatures = 0
      open = 0

      4.times do |index|
        floor = Generator.floor Rng.new(FIRST + index), "floor-1", 1, columns, rows
        floor.each { |_column, _row, tile| open += 1 if tile.terrain.passable? }
        floor.each_monster { creatures += 1 }
      end

      creatures * 1000.0 / open
    end

    it "is as crowded on a floor a quarter the size as on one four times it" do
      small = crowding 108, 42
      large = crowding 432, 168

      expect(small).to be_within(small / 2).of(large)
    end
  end

  describe "Game.dug" do
    it "plays on a floor the generator dug" do
      game = Roguelike::Game.dug Rng.new(FIRST)

      expect(game.floor.id).to eq "floor-1"
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
