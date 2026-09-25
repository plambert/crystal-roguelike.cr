require "./direction"
require "./fixture"
require "./floor"
require "./items"
require "./rng"
require "./species"

module Roguelike
  # One rectangle of a floor, in squares.
  record Area, x : Int32, y : Int32, columns : Int32, rows : Int32 do
    # The last column in it.
    def right : Int32
      @x + @columns - 1
    end

    # The last row in it.
    def bottom : Int32
      @y + @rows - 1
    end

    # The square in the middle of it.
    def middle : {Int32, Int32}
      {@x + @columns // 2, @y + @rows // 2}
    end

    # Whether *x*, *y* is inside it.
    def holds?(x : Int32, y : Int32) : Bool
      x >= @x && x <= right && y >= @y && y <= bottom
    end

    # This rectangle with *margin* squares taken off every side.
    def inset(margin : Int32) : Area
      Area.new @x + margin, @y + margin,
        @columns - margin * 2, @rows - margin * 2
    end

    # Yields every square in it, in reading order.
    def each(& : Int32, Int32 ->) : Nil
      (@y..bottom).each do |row|
        (@x..right).each { |column| yield column, row }
      end
    end

    # What a stream named after this rectangle is called.
    def to_s(io : IO) : Nil
      io << @x << ',' << @y << ' ' << @columns << 'x' << @rows
    end
  end

  # A floor dug out of solid rock.
  #
  # Binary space partition. The floor starts as one rectangle of rock. Each
  # rectangle is cut in two until it is small enough for one room, a room is
  # carved in each of the smallest rectangles, and the two halves of every cut
  # are joined by a corridor.
  #
  # Joining at every cut is what makes every square reachable from every
  # other. The rooms form a tree rather than a scattering, and a tree has a
  # path between any two of its leaves.
  #
  # Every roll is on a stream named after the rectangle or the room it is
  # about, never on one shared stream walked in order. Two floors from one
  # seed are identical, and adding a roll in one place moves nothing
  # elsewhere: putting a second sconce in a room shifts that room's lights and
  # leaves every other room where it was.
  class Generator
    # How wide a floor is.
    COLUMNS = 216

    # How tall a floor is.
    ROWS = 84

    # The smallest room there is, in squares of floor.
    LEAST = {4, 3}

    # The largest rectangle that holds one room, in squares.
    #
    # A rectangle larger than this on either side is cut again. So the number
    # of rooms follows the size of the floor rather than a fixed count, and a
    # floor twice as wide holds twice as many rooms of the same size rather
    # than the same rooms stretched.
    ROOMY = {20, 11}

    # Where along its longer side a rectangle is cut, out of a hundred.
    #
    # Near the middle. A cut at the very edge leaves a rectangle too thin for
    # a room, and the room in the other half fills almost all of it.
    SPLIT = 40..60

    # How often a door is shut rather than standing open, out of a hundred.
    SHUT = 45

    # How many sconces a room has.
    SCONCES = 0..2

    # How often a lit sconce is lit, out of a hundred.
    BURNING = 70

    # How often a room holds a creature, out of a hundred.
    INHABITED = 45

    # How many creatures such a room holds.
    CROWD = 1..2

    # What each species is worth when a creature is rolled.
    #
    # A slime and a goblin are common and an orc is not. The numbers are
    # relative and nothing depends on their sum.
    CREATURES = {
      Species::Slime  => 40,
      Species::Goblin => 45,
      Species::Orc    => 15,
    }

    # What a room's floor is made of.
    GROUND = {
      Terrain::StoneFloor => 70,
      Terrain::DirtFloor  => 30,
    }

    # What the rock between the rooms is.
    ROCK = {
      Terrain::Granite   => 50,
      Terrain::Sandstone => 25,
      Terrain::Shale     => 25,
    }

    # The stream every roll here derives from.
    DOMAIN = "worldgen"

    # A floor called *id*, dug on *rng*.
    def self.floor(rng : Rng, id : String = "dungeon",
                   columns : Int32 = COLUMNS, rows : Int32 = ROWS) : Floor
      new(rng, id, columns, rows).dig
    end

    # The floor being dug.
    getter floor : Floor

    # Every room cut into it, in the order they were cut.
    getter rooms : Array(Area) = [] of Area

    # The room the up staircase is in. `nil` before the stairs are put down.
    getter arrival : Area? = nil

    def initialize(rng : Rng, id : String, columns : Int32, rows : Int32)
      @rng = rng.derive "#{DOMAIN}:#{id}"
      @floor = Floor.solid id, columns, rows
    end

    # Digs the whole floor and answers it.
    def dig : Floor
      whole = Area.new 0, 0, @floor.columns, @floor.rows

      cut whole
      doors
      stairs
      rooms.each_with_index do |room, index|
        light room, index
        inhabit room, index
      end

      @floor
    end

    # Cuts *area* in two until each piece holds one room, and joins the
    # halves.
    #
    # Answers one room from inside *area*, which is what the cut above joins
    # to. Any room in the rectangle would do: they are all joined to each
    # other by the time this answers.
    private def cut(area : Area) : Area
      return carve area unless splittable? area

      first, second = halves area
      near = cut first
      far = cut second
      join near, far

      near
    end

    # Whether *area* is cut again rather than made into a room.
    #
    # It has to be larger than one room wants on one side, and it has to have
    # room for the smallest room there is on each side of the cut with a
    # square of rock around it. A rectangle that is too large to leave alone
    # and too small to cut is made into a room anyway.
    private def splittable?(area : Area) : Bool
      return false unless area.columns > ROOMY[0] || area.rows > ROOMY[1]

      area.columns >= least(0) * 2 || area.rows >= least(1) * 2
    end

    # How many squares a rectangle needs on *axis* to hold the smallest room
    # with a square of rock on each side of it.
    private def least(axis : Int32) : Int32
      LEAST[axis] + 2
    end

    # *area* cut in two across its longer side.
    private def halves(area : Area) : {Area, Area}
      stream = @rng.derive "cut:#{area}"
      across = wider? area, stream

      room = across ? area.columns : area.rows
      want = across ? least(0) : least(1)
      at = (room * stream.rand(SPLIT) // 100).clamp want, room - want

      return {Area.new(area.x, area.y, at, area.rows),
              Area.new(area.x + at, area.y, area.columns - at, area.rows)} if across

      {Area.new(area.x, area.y, area.columns, at),
       Area.new(area.x, area.y + at, area.columns, area.rows - at)}
    end

    # Whether *area* is cut across rather than down.
    #
    # The longer side, so the halves stay near square. A rectangle that is
    # about as wide as it is tall is cut either way.
    private def wider?(area : Area, stream : Rng) : Bool
      return true unless area.rows >= least(1) * 2
      return false unless area.columns >= least(0) * 2
      return stream.rand(2).zero? if area.columns == area.rows * 2

      area.columns > area.rows * 2
    end

    # Carves one room inside *area* and answers it.
    #
    # The room keeps a square of rock between it and the edge of *area*, so
    # two rooms in neighboring rectangles never touch.
    private def carve(area : Area) : Area
      stream = @rng.derive "room:#{area}"
      inside = area.inset 1

      # The rock this rectangle is cut out of. Every leaf takes its own, and
      # the leaves tile the floor, so what a wall is made of changes from one
      # part of the floor to another.
      rock = Items.pick stream, ROCK
      area.each { |column, row| @floor.set column, row, rock }

      columns = stream.rand LEAST[0]..Math.max(inside.columns, LEAST[0])
      rows = stream.rand LEAST[1]..Math.max(inside.rows, LEAST[1])
      columns = Math.min columns, inside.columns
      rows = Math.min rows, inside.rows

      room = Area.new(
        inside.x + stream.rand(inside.columns - columns + 1),
        inside.y + stream.rand(inside.rows - rows + 1),
        columns, rows)

      ground = Items.pick stream, GROUND
      room.each { |column, row| @floor.set column, row, ground }
      @rooms << room
      room
    end

    # Joins *near* and *far* with one corridor.
    #
    # Two straight lengths meeting at a right angle, from the middle of one
    # room to the middle of the other. Which length comes first is rolled, so
    # the corner falls on either side.
    private def join(near : Area, far : Area) : Nil
      stream = @rng.derive "corridor:#{near}:#{far}"
      from = near.middle
      to = far.middle

      if stream.rand(2).zero?
        across from[0], to[0], from[1]
        down from[1], to[1], to[0]
      else
        down from[1], to[1], from[0]
        across from[0], to[0], to[1]
      end
    end

    # Carves the squares from *first* to *last* along row *row*.
    private def across(first : Int32, last : Int32, row : Int32) : Nil
      Range.new(Math.min(first, last), Math.max(first, last)).each do |column|
        tunnel column, row
      end
    end

    # Carves the squares from *first* to *last* down column *column*.
    private def down(first : Int32, last : Int32, column : Int32) : Nil
      Range.new(Math.min(first, last), Math.max(first, last)).each do |row|
        tunnel column, row
      end
    end

    # Makes *x*, *y* a stone floor, unless it is already something to walk on.
    #
    # A corridor that reaches a room it has already joined leaves the room's
    # own ground alone, so a dirt room stays a dirt room.
    private def tunnel(x : Int32, y : Int32) : Nil
      return unless @floor.contains? x, y
      return if @floor.terrain(x, y).floor?

      @floor.set x, y, Terrain::StoneFloor
    end

    # Puts a door on every square where a corridor crosses a room's wall.
    #
    # A room's wall is the ring of squares one outside it. A corridor that
    # reaches the room has carved one of those, and that square is the
    # doorway.
    #
    # A ring square with anything other than two ways off it, facing each
    # other, is left as floor. A door needs a wall on each side of it to hang
    # from, and a door on the corner of two corridors would hang from
    # nothing.
    private def doors : Nil
      rooms.each_with_index do |room, index|
        stream = @rng.derive "doors:#{index}:#{room}"

        ring(room).each do |spot|
          next unless doorway? spot

          shut = stream.rand(100) < SHUT
          @floor.set spot[0], spot[1],
            shut ? Terrain::ClosedDoor : Terrain::OpenDoor
        end
      end
    end

    # Whether *spot* is inside any room.
    private def indoors?(spot : {Int32, Int32}) : Bool
      rooms.any? &.holds?(spot[0], spot[1])
    end

    # Every square one outside *room*, corners left out.
    #
    # A corner is not a doorway. A corridor reaching a room through its corner
    # would have a wall on one side of the opening and open floor on the
    # other.
    private def ring(room : Area) : Array({Int32, Int32})
      found = [] of {Int32, Int32}

      (room.x..room.right).each do |column|
        found << {column, room.y - 1} << {column, room.bottom + 1}
      end

      (room.y..room.bottom).each do |row|
        found << {room.x - 1, row} << {room.right + 1, row}
      end

      found.select { |spot| @floor.contains? spot[0], spot[1] }
    end

    # Whether *spot* is a square a door could hang in.
    #
    # It has to be corridor now, with exactly two ways off it, and the two
    # have to face each other.
    #
    # A square inside another room is not a doorway, and neither is one with
    # a door already beside it. Two doors in a row make a vestibule of one
    # square, which is a thing to walk through twice rather than a way into a
    # room.
    private def doorway?(spot : {Int32, Int32}) : Bool
      return false unless @floor.terrain(spot[0], spot[1]).stone_floor?
      return false if indoors? spot

      ways = Direction.values.select do |direction|
        next false if direction.diagonal?

        where = direction.from spot[0], spot[1]
        @floor.contains?(where[0], where[1]) &&
          @floor.passable?(where[0], where[1])
      end

      return false unless ways.size == 2 && ways.first.opposite == ways.last

      ways.none? do |direction|
        where = direction.from spot[0], spot[1]
        @floor.terrain(where[0], where[1]).door?
      end
    end

    # Puts the two staircases in two different rooms.
    #
    # A floor with one room has nowhere to put the second one, and a floor
    # with no rooms has nowhere to put either.
    private def stairs : Nil
      return if rooms.size < 2

      stream = @rng.derive "stairs"
      up, down = rooms.sample(2, stream)

      put stream, up, Terrain::StairsUp
      put stream, down, Terrain::StairsDown
      @arrival = up
    end

    # Puts *terrain* on a square of *room* nothing else is on.
    private def put(stream : Rng, room : Area, terrain : Terrain) : Nil
      spot = plain(room).sample stream
      @floor.set spot[0], spot[1], terrain
    end

    # Every square of *room* that is still bare ground.
    private def plain(room : Area) : Array({Int32, Int32})
      found = [] of {Int32, Int32}
      room.each do |column, row|
        next unless @floor.terrain(column, row).floor?
        next if @floor.fixture column, row
        next if @floor.monster column, row

        found << {column, row}
      end

      found.empty? ? [room.middle] : found
    end

    # Puts sconces on the walls of *room*.
    #
    # A sconce stands on the floor square beside the wall it is bolted to.
    # `Fixture#attached` is which wall that is, and a square with a wall on
    # more than one side has no one wall to hang from.
    private def light(room : Area, index : Int32) : Nil
      stream = @rng.derive "lights:#{index}:#{room}"
      brackets = walls room

      return if brackets.empty?

      stream.rand(SCONCES).times do
        bracket = brackets.sample stream
        spot = bracket.spot
        next if @floor.fixture spot[0], spot[1]

        @floor.set_fixture spot[0], spot[1],
          Fixture.new(FixtureKind::Sconce, stream.rand(100) < BURNING,
            bracket.wall)
      end
    end

    # One square of a room with a wall on exactly one side, and which side.
    record Bracket, spot : {Int32, Int32}, wall : Direction

    # Every square of *room* with a wall on exactly one side.
    private def walls(room : Area) : Array(Bracket)
      found = [] of Bracket

      room.each do |column, row|
        touching = Direction.values.select do |direction|
          next false if direction.diagonal?

          where = direction.from column, row
          !@floor.contains?(where[0], where[1]) ||
            @floor.terrain(where[0], where[1]).rock?
        end

        found << Bracket.new({column, row}, touching.first) if touching.size == 1
      end

      found
    end

    # Puts creatures in *room*.
    #
    # Each is in a band of its own. `Floor#place` writes the band down, the
    # same way it does for a creature a floor file names.
    #
    # The room with the up staircase in it gets none. A character who arrives
    # standing next to a goblin has been given no turn to decide anything.
    private def inhabit(room : Area, index : Int32) : Nil
      return if room == @arrival

      stream = @rng.derive "monsters:#{index}:#{room}"
      return unless stream.rand(100) < INHABITED

      stream.rand(CROWD).times do |which|
        spot = plain(room).sample stream
        species = Items.pick stream, CREATURES
        band = "#{@floor.id}-#{index}-#{which}"

        @floor.place Monster.new(species, spot[0], spot[1], band)
      end
    end
  end
end
