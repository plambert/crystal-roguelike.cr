require "../spec_helper"

Spectator.describe Roguelike::Chambers do
  alias Chambers = Roguelike::Chambers
  alias Floor = Roguelike::Floor
  alias Generator = Roguelike::Generator
  alias Knowledge = Roguelike::Knowledge
  alias Layout = Roguelike::Layout
  alias Rng = Roguelike::Rng
  alias World = Roguelike::World

  # The seed every example here runs on. A failure names a run somebody can
  # start.
  SEED = 20261004_u64

  # Two rooms joined by a corridor with a door at each end, and a dead end
  # off the corridor going south.
  TWO_ROOMS = [
    "##################",
    "#.....######.....#",
    "#.....######.....#",
    "#.....'....'.....#",
    "#.....####.#.....#",
    "#.....####.#.....#",
    "##########.#######",
    "##########.#######",
    "##################",
  ]

  # Knowledge of every square of *floor*.
  def knowing(floor : Floor) : Knowledge
    known = Knowledge.new floor.id
    floor.rows.times do |row|
      floor.columns.times { |column| known.see floor, column, row }
    end
    known
  end

  # The cut of everything on *lines*.
  def cut(lines : Array(String)) : Chambers
    floor = Floor.parse "rooms", lines
    knowing(floor).chambers floor.columns, floor.rows
  end

  # Every square of *floor* a chamber may hold: walkable, not a door.
  def ground?(floor : Floor, x : Int32, y : Int32) : Bool
    terrain = floor.terrain x, y
    terrain.passable? && !terrain.door?
  end

  # Whether the nine squares around *x*, *y* are all ground.
  def open?(floor : Floor, x : Int32, y : Int32) : Bool
    (-1..1).all? do |down|
      (-1..1).all? do |across|
        floor.contains?(x + across, y + down) && ground?(floor, x + across, y + down)
      end
    end
  end

  describe "two rooms and a corridor" do
    it "holds each room as one chamber, ring and all" do
      found = cut TWO_ROOMS

      expect(found.chambers.map &.anchor).to eq [{2, 2}, {13, 2}]
      expect(found.chambers.map &.squares.size).to eq [25, 25]
      expect(found.at(1, 1).try &.anchor).to eq({2, 2})
      expect(found.at(16, 5).try &.anchor).to eq({13, 2})
    end

    it "keeps the doors and the corridor out of both" do
      found = cut TWO_ROOMS

      expect(found.at 6, 3).to be_nil
      expect(found.at 8, 3).to be_nil
      expect(found.at 10, 7).to be_nil
      expect(found.passages.size).to eq 1
      expect(found.passages.first.chambers).to eq [{2, 2}, {13, 2}]
    end

    it "names the doors as the ways out" do
      found = cut TWO_ROOMS

      expect(found.chambers.first.exits).to eq [{6, 3}]
      expect(found.chambers.last.exits).to eq [{11, 3}]
    end

    it "finds the junction and the dead end" do
      passage = cut(TWO_ROOMS).passages.first

      expect(passage.junctions).to eq [{10, 3}]
      expect(passage.dead_ends).to eq [{10, 7}]
    end

    it "names the items remembered in a chamber" do
      floor = Floor.parse "rooms", TWO_ROOMS
      floor.drop 3, 4, Roguelike::Item.new(Roguelike::ItemKind::Dagger)
      found = knowing(floor).chambers floor.columns, floor.rows

      expect(found.chambers.first.items.map &.at).to eq [{3, 4}]
      expect(found.chambers.last.items).to be_empty
    end

    it "says a room is seen once every square beside it is" do
      floor = Floor.parse "rooms", TWO_ROOMS
      known = knowing floor
      found = known.chambers floor.columns, floor.rows

      expect(found.chambers.all? &.seen?).to be_true
      expect(found.frontier?).to be_false
    end

    it "says a room is not seen while a square beside it is not" do
      floor = Floor.parse "rooms", TWO_ROOMS
      known = Knowledge.new floor.id
      floor.rows.times do |row|
        (0..3).each { |column| known.see floor, column, row }
      end
      found = known.chambers floor.columns, floor.rows

      expect(found.chambers.size).to eq 1
      expect(found.chambers.first.seen?).to be_false
      expect(found.frontier?(3, 3)).to be_true
    end

    it "marks the corridor beyond a seen room as the frontier" do
      floor = Floor.parse "rooms", TWO_ROOMS
      known = Knowledge.new floor.id
      floor.rows.times do |row|
        (0..7).each { |column| known.see floor, column, row }
      end
      found = known.chambers floor.columns, floor.rows

      expect(found.chambers.first.seen?).to be_true
      expect(found.frontier).to eq [{7, 3}]
    end
  end

  describe "a room larger than a cell" do
    # A room 40 by 30, which crosses one line of the grid each way.
    def big : Array(String)
      lines = ["#" * 42]
      30.times { lines << "#" + "." * 40 + "#" }
      lines << "#" * 42
      lines
    end

    it "splits along the grid" do
      found = cut big

      expect(found.chambers.map &.anchor).to eq [{2, 2}, {24, 2}, {2, 24}, {24, 24}]
    end

    it "keeps each chamber's open squares inside one cell" do
      floor = Floor.parse "rooms", big
      found = knowing(floor).chambers floor.columns, floor.rows

      found.chambers.each do |chamber|
        cells = chamber.squares.select { |spot| open? floor, spot[0], spot[1] }
          .map { |spot| {spot[0] // Chambers::CELL, spot[1] // Chambers::CELL} }.uniq!

        expect(cells.size).to eq 1
      end
    end

    it "names the chambers beside each other as neighbors" do
      found = cut big

      expect(found.chambers.first.neighbors).to eq [{24, 2}, {2, 24}, {24, 24}]
    end
  end

  describe "the three layouts" do
    # A floor of *layout*, every square of it known.
    def dug(layout : Layout) : {Floor, Knowledge}
      floor = Generator.dug(Rng.new(SEED), World.id(1), 1, layout: layout).floor
      {floor, knowing(floor)}
    end

    {% for layout in %w[Tree Cave Grid] %}
      describe "a {{ layout.downcase.id }} floor" do
        it "puts every open square in a chamber and no door in any" do
          floor, known = dug Layout::{{ layout.id }}
          found = known.chambers floor.columns, floor.rows

          floor.rows.times do |row|
            floor.columns.times do |column|
              chamber = found.at column, row
              expect(chamber).not_to be_nil if open? floor, column, row
              expect(chamber).to be_nil if floor.terrain(column, row).door?
            end
          end
        end

        it "puts every walkable square in one chamber or one passage" do
          floor, known = dug Layout::{{ layout.id }}
          found = known.chambers floor.columns, floor.rows
          counted = Hash({Int32, Int32}, Int32).new 0

          found.chambers.each { |chamber| chamber.squares.each { |spot| counted[spot] += 1 } }
          found.passages.each { |passage| passage.squares.each { |spot| counted[spot] += 1 } }

          floor.rows.times do |row|
            floor.columns.times do |column|
              wanted = floor.terrain(column, row).passable? || floor.terrain(column, row).door? ? 1 : 0
              expect(counted[{column, row}]).to eq(wanted), "#{column},#{row}"
            end
          end
        end

        it "anchors each chamber on its first open square" do
          floor, known = dug Layout::{{ layout.id }}

          known.chambers(floor.columns, floor.rows).chambers.each do |chamber|
            first = chamber.squares.find! { |spot| open? floor, spot[0], spot[1] }
            expect(chamber.anchor).to eq first
          end
        end

        it "cuts the same whatever order the squares were learned in" do
          floor, known = dug Layout::{{ layout.id }}
          backward = Knowledge.new floor.id
          (floor.rows - 1).downto(0) do |row|
            (floor.columns - 1).downto(0) { |column| backward.see floor, column, row }
          end

          expect(backward.chambers(floor.columns, floor.rows).to_map)
            .to eq known.chambers(floor.columns, floor.rows).to_map
        end
      end
    {% end %}
  end

  describe "ids as knowledge grows" do
    it "keeps the anchor and the squares of a chamber once it is seen" do
      game = Roguelike::Game.dug Rng.new(SEED)
      game.floor.monsters.clear
      ground = game.floor
      settled = {} of {Int32, Int32} => Array({Int32, Int32})

      # Each walk stops when an item comes into sight or a line is written,
      # and a cave strewn with items stops one every few steps, so many are
      # taken.
      game.look
      200.times do
        walk = game.exploring
        loop do
          game.knowledge.chambers(ground.columns, ground.rows).chambers.each do |chamber|
            settled[chamber.anchor] ||= chamber.squares if chamber.seen?
          end
          break unless game.stride walk
        end
        break if walk.halt.try(&.explored?) || settled.size > 12
      end

      later = game.knowledge.chambers ground.columns, ground.rows
      expect(settled.size).to be > 10
      settled.each do |anchor, squares|
        expect(later[anchor].try &.squares).to eq(squares), "#{anchor}"
      end
    end
  end

  describe "the cache" do
    it "gives the same cut back while nothing new is learned" do
      floor = Floor.parse "rooms", TWO_ROOMS
      known = knowing floor
      first = known.chambers floor.columns, floor.rows
      known.see floor, 3, 3

      expect(known.chambers floor.columns, floor.rows).to be first
    end

    it "cuts again once a square is learned" do
      floor = Floor.parse "rooms", TWO_ROOMS
      known = Knowledge.new floor.id
      known.see floor, 1, 1
      first = known.chambers floor.columns, floor.rows
      known.see floor, 2, 2

      expect(known.chambers floor.columns, floor.rows).not_to be first
    end
  end
end
