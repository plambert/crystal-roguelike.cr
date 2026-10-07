require "../roguelike"

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

  # How a floor is laid out.
  enum Layout
    # Rectangles cut in two until each holds one room, the halves of every
    # cut joined by a corridor. Its only loops are where one corridor
    # crosses another.
    Tree

    # Rooms in rows and columns, each joined to most of its neighbors. A grid
    # is full of loops.
    Grid

    # A natural cave grown by a cellular automaton. Its rock stands in
    # islands, and a walk round one comes back where it began.
    Cave
  end

  # A floor dug out of solid rock.
  #
  # The floor's size is drawn first, then its layout. A tree is a binary
  # space partition: the floor starts as one rectangle of rock, each rectangle
  # is cut in two until it is small enough for one room, a room is carved in
  # each of the smallest rectangles, and the two halves of every cut are
  # joined by a corridor. Joining at every cut makes every square reachable
  # from every other.
  #
  # Every floor is mirrored across, down, both or neither, so a tree's
  # corridors do not all run toward one corner. A large enough rectangle of a
  # tree is
  # sometimes filled as a grid or a cave instead of being cut further. A whole
  # floor may be a grid or a cave.
  #
  # `Audit` judges the result. A floor it faults is dug again on a fresh
  # stream, up to `TRIES` times.
  #
  # Every roll is on a stream named after the floor and the rectangle or room
  # it is about, never on one shared stream walked in order. Two floors from
  # one seed are identical, and adding a roll in one place moves nothing
  # elsewhere: putting a second sconce in a room shifts that room's lights and
  # leaves every other room where it was.
  class Generator
    # How wide a floor of average size is.
    COLUMNS = 216

    # How tall a floor of average size is.
    ROWS = 84

    # The area of a floor of average size.
    AREA = COLUMNS * ROWS

    # How far a floor's area strays from `AREA`, as a power of two.
    #
    # The exponent is the mean of four rolls, scaled to run from minus this
    # to plus it. So the area runs from a quarter of `AREA` to four times it,
    # on a bell centred on `AREA` itself.
    SPREAD = 2.0

    # How many rolls the exponent is the mean of. More make the bell
    # narrower.
    BELL = 4

    # The shapes a floor comes in, as columns to rows, by weight.
    #
    # The squarer shapes are commoner. A floor three times as tall as it is
    # wide is left out, because the window is wider than it is tall.
    SHAPES = {
      {1, 1} => 30,
      {3, 2} => 25,
      {2, 1} => 20,
      {2, 3} => 10,
      {3, 1} => 10,
      {1, 2} => 5,
    }

    # The narrowest and the shortest a floor is, whatever the draw.
    SMALLEST = {32, 20}

    # How often each layout is picked for a whole floor.
    LAYOUTS = {
      Layout::Tree => 60,
      Layout::Grid => 20,
      Layout::Cave => 20,
    }

    # How many rectangles of a tree are filled another way, by weight.
    #
    # Most trees are trees all through.
    MIXES = {0 => 60, 1 => 30, 2 => 10}

    # How often a rectangle that may be filled another way is, out of a
    # hundred, while the floor has any left to fill.
    MIXED = 35

    # How large a rectangle of a tree has to be before it may be filled
    # another way, and the largest share of the floor, out of a hundred, it
    # may cover.
    SECTOR       = {44, 24}
    SECTOR_SHARE = 40

    # What such a rectangle is filled with.
    SECTORS = {
      Layout::Grid => 50,
      Layout::Cave => 50,
    }

    # How many times a floor is dug before the last try is kept.
    TRIES = 6

    # The rectangle one room of a grid is carved in.
    CELL = {14, 9}

    # How often a grid joins two neighboring rooms beyond what it needs to
    # join them all, out of a hundred.
    LINKED = 65

    # How much of a cave starts open, out of a hundred.
    OPENING = 53

    # How many times the automaton smooths a cave.
    SMOOTHING = 4

    # How many rock squares among the nine around one make it rock.
    CROWDED = 5

    # The fewest squares a cave keeps. A smaller one is carved as a room.
    HOLLOW = 30

    # The fewest squares a body of a cave needs to be kept and joined to the
    # rest. A smaller one fills in.
    POCKET = 20

    # The rectangle a cave is divided into for lights and creatures, and the
    # fewest open squares one needs to count.
    #
    # A cavern is about twice the area of a rectangle a tree holds one room
    # in, so a cave holds about half as many creatures for its size. A cave
    # is open, and everything in one sees a character coming from further
    # off than it would through a door.
    CAVERN   = {20, 10}
    ROOMIEST = 12

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

    # A floor called *id*, dug on *rng*, as deep as *depth*.
    #
    # Every stream is named after *id*. A floor id names its depth, so floor
    # 3 of a seed is the same floor whether floor 2 was dug before it or not.
    #
    # *columns* and *rows* fix the size rather than drawing it.
    def self.floor(rng : Rng, id : String = World.id(1), depth : Int32 = 1,
                   columns : Int32? = nil, rows : Int32? = nil) : Floor
      dug(rng, id, depth, columns, rows).floor
    end

    # The generator that dug the floor `.floor` answers, faults and all.
    #
    # Each try that `Audit` faults is dug again on a stream of its own. The
    # last try is kept whatever it holds, so a floor always comes back.
    def self.dug(rng : Rng, id : String = World.id(1), depth : Int32 = 1,
                 columns : Int32? = nil, rows : Int32? = nil,
                 layout : Layout? = nil) : Generator
      rejected = [] of String

      TRIES.times do |attempt|
        generator = new rng, id, columns, rows, depth, attempt, layout
        generator.dig
        found = Audit.faults generator.floor, generator.rooms

        if found.empty? || attempt == TRIES - 1
          generator.rejected = rejected
          return generator
        end

        rejected.concat found
      end

      raise "no try was kept"
    end

    # The size of the floor called *id*, drawn on *rng*.
    #
    # It has a stream of its own, so a floor dug again after a fault keeps its
    # size.
    def self.size(rng : Rng, id : String) : {Int32, Int32}
      stream = rng.derive("#{DOMAIN}:#{id}").derive "size"
      mean = (0...BELL).sum { stream.rand } / BELL
      area = AREA * 2.0 ** ((mean * 2 - 1) * SPREAD)

      shape = Items.pick stream, SHAPES
      columns = Math.sqrt(area * shape[0] / shape[1]).round.to_i
      rows = (area / columns).round.to_i

      {Math.max(columns, SMALLEST[0]), Math.max(rows, SMALLEST[1])}
    end

    # How wide the chamber under the last floor is.
    CHAMBER_COLUMNS = 31

    # How tall it is.
    CHAMBER_ROWS = 11

    # The chamber under the last floor, called *id*.
    #
    # One room of dressed stone with the up staircase at the west end and
    # the amulet at the east end, lit by four sconces. Nothing lives there.
    # It rolls nothing, so it is the same chamber on every seed.
    def self.chamber(id : String = World.id(World::VAULT)) : Floor
      floor = Floor.solid id, CHAMBER_COLUMNS, CHAMBER_ROWS
      room = Area.new 3, 2, CHAMBER_COLUMNS - 6, CHAMBER_ROWS - 4
      room.each { |column, row| floor.set column, row, Terrain::StoneFloor }

      middle = room.middle[1]
      floor.set room.x, middle, Terrain::StairsUp
      floor.drop room.right, middle, Item.new(ItemKind::Amulet)

      {room.x + 4, room.right - 4}.each do |column|
        floor.set_fixture column, room.y,
          Fixture.new(FixtureKind::Sconce, true, Direction::North)
        floor.set_fixture column, room.bottom,
          Fixture.new(FixtureKind::Sconce, true, Direction::South)
      end

      floor
    end

    # The floor being dug.
    getter floor : Floor

    # Every room cut into it, in the order they were cut.
    getter rooms : Array(Area) = [] of Area

    # Every stretch of cave, in the order they were grown.
    #
    # A cavern is a rectangle of a cave with enough open squares in it to
    # hold a staircase, a sconce or a creature. It takes no doors.
    getter caverns : Array(Area) = [] of Area

    # The room or cavern the up staircase is in. `nil` before the stairs are
    # put down.
    getter arrival : Area? = nil

    # How deep the floor is. `Spawns` reads it.
    getter depth : Int32

    # Which try this is, from zero.
    getter attempt : Int32

    # How the whole floor is laid out.
    getter layout : Layout

    # What the tries before this one were faulted for.
    property rejected : Array(String) = [] of String

    # What the rectangles of a tree were filled with instead, when any were.
    getter mixed : Set(Layout) = Set(Layout).new

    # Every corridor square carved so far.
    @halls = Set({Int32, Int32}).new

    # How many more rectangles of a tree may be filled another way.
    @mixes : Int32

    # The stream every roll of this try derives from.
    @rng : Rng

    def initialize(rng : Rng, id : String, columns : Int32? = nil,
                   rows : Int32? = nil, @depth : Int32 = 1,
                   @attempt : Int32 = 0, layout : Layout? = nil)
      base = rng.derive "#{DOMAIN}:#{id}"
      @rng = @attempt.zero? ? base : base.derive("retry:#{@attempt}")

      drawn = Generator.size rng, id
      @floor = Floor.solid(id, columns || drawn[0], rows || drawn[1])
      @layout = layout || Items.pick(@rng.derive("layout"), LAYOUTS)
      @mixes = Items.pick @rng.derive("mixes"), MIXES
    end

    # What the layout is called, with whatever filled parts of a tree.
    def plan : String
      named = @layout.to_s.downcase
      return named if @mixed.empty?

      "#{named}+#{@mixed.map(&.to_s.downcase).sort!.join('+')}"
    end

    # Every room and every cavern.
    def zones : Array(Area)
      rooms + caverns
    end

    # Digs the whole floor and answers it.
    def dig : Floor
      whole = Area.new 0, 0, @floor.columns, @floor.rows

      case @layout
      in .tree? then cut whole
      in .grid? then grid whole
      in .cave? then cave whole
      end

      mirror
      doors
      stairs
      zones.each_with_index do |zone, index|
        light zone, index
        inhabit zone, index
      end

      @floor
    end

    # Cuts *area* in two until each piece holds one room, and joins the
    # halves.
    #
    # Answers every room inside *area*, which is what the cut above chooses
    # from. The two halves are joined through the two rooms, one on each
    # side, whose middles are closest. A cut joined through rooms picked any
    # other way sends its corridor past rooms a lower cut already joined, and
    # often beside the corridor that joined them.
    #
    # A large rectangle below the whole floor is sometimes filled as a grid
    # or a cave instead.
    private def cut(area : Area) : Array(Area)
      return [carve(area)] unless splittable? area

      filled = sector area
      return filled if filled

      first, second = halves area
      near = cut first
      far = cut second
      join *closest(near, far)

      near + far
    end

    # The room of *near* and the room of *far* whose middles are closest.
    #
    # Ties go to the first found, so the answer is the same on every run.
    private def closest(near : Array(Area), far : Array(Area)) : {Area, Area}
      best = {near.first, far.first}
      gap = Int32::MAX

      near.each do |one|
        far.each do |other|
          apart = Route.apart one.middle, other.middle
          next unless apart < gap

          gap = apart
          best = {one, other}
        end
      end

      best
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

    # Fills *area* as a grid or a cave, when the roll says so. Answers what
    # the cut above may join to, or `nil` to cut as usual.
    private def sector(area : Area) : Array(Area)?
      return unless @layout.tree? && @mixes > 0
      return unless area.columns >= SECTOR[0] && area.rows >= SECTOR[1]
      return if area.columns * area.rows * 100 > @floor.columns * @floor.rows * SECTOR_SHARE

      stream = @rng.derive "sector:#{area}"
      return unless stream.rand(100) < MIXED

      kind = Items.pick stream, SECTORS
      @mixes -= 1
      @mixed << kind
      kind.grid? ? grid(area) : cave(area)
    end

    # Fills *area* with rooms in rows and columns, and joins them.
    #
    # Each room is joined to the room to its right and the room below it
    # `LINKED` times out of a hundred. Any pair of neighbors still in two
    # separate groups after that is joined as well, in reading order, so
    # every room is reached and most are reached more than one way.
    #
    # Answers every room.
    private def grid(area : Area) : Array(Area)
      stream = @rng.derive "grid:#{area}"
      across = Math.max area.columns // CELL[0], 1
      down = Math.max area.rows // CELL[1], 1

      cells = Array.new(down) do |row|
        Array.new(across) do |column|
          left = area.x + area.columns * column // across
          top = area.y + area.rows * row // down
          carve Area.new(left, top,
            area.x + area.columns * (column + 1) // across - left,
            area.y + area.rows * (row + 1) // down - top)
        end
      end

      pairs = [] of { {Int32, Int32}, {Int32, Int32} }
      down.times do |row|
        across.times do |column|
          pairs << { {column, row}, {column + 1, row} } if column + 1 < across
          pairs << { {column, row}, {column, row + 1} } if row + 1 < down
        end
      end

      group = Hash({Int32, Int32}, {Int32, Int32}).new
      wanted = pairs.map { stream.rand(100) < LINKED }
      pairs.each_with_index do |pair, index|
        next unless wanted[index]

        group[leader(group, pair[0])] = leader(group, pair[1])
      end

      pairs.each_with_index do |pair, index|
        next if wanted[index]
        next if leader(group, pair[0]) == leader(group, pair[1])

        wanted[index] = true
        group[leader(group, pair[0])] = leader(group, pair[1])
      end

      pairs.each_with_index do |pair, index|
        next unless wanted[index]

        join cells[pair[0][1]][pair[0][0]], cells[pair[1][1]][pair[1][0]]
      end

      cells.flatten
    end

    # The cell that stands for the group *cell* is in.
    private def leader(group : Hash({Int32, Int32}, {Int32, Int32}),
                       cell : {Int32, Int32}) : {Int32, Int32}
      while above = group[cell]?
        break if above == cell

        cell = above
      end
      cell
    end

    # Grows a cave inside *area*.
    #
    # Each square inside a border of rock starts open `OPENING` times out of
    # a hundred. The automaton then runs `SMOOTHING` times: a square with
    # `CROWDED` rock squares or more among the nine around it and itself turns
    # to rock, and any other square opens. Every body of open squares of
    # `POCKET` or more is kept, largest first, and each is joined by a
    # corridor to the nearest square of the ones before it. The rest fill in.
    #
    # A cave too small to keep is carved as one room instead. Answers the
    # square of the cave nearest the middle of each cavern, as a rectangle of
    # one, for a corridor to reach.
    private def cave(area : Area) : Array(Area)
      stream = @rng.derive "cave:#{area}"
      rock = Items.pick stream, ROCK
      area.each { |column, row| @floor.set column, row, rock }

      inside = area.inset 1
      open = Set({Int32, Int32}).new
      inside.each { |column, row| open << {column, row} if stream.rand(100) < OPENING }

      SMOOTHING.times do
        grown = Set({Int32, Int32}).new
        inside.each do |column, row|
          solid = 0
          (-1..1).each do |shift_x|
            (-1..1).each do |shift_y|
              solid += 1 unless open.includes?({column + shift_x, row + shift_y})
            end
          end
          grown << {column, row} if solid < CROWDED
        end
        open = grown
      end

      bodies = split(open).select { |body| body.size >= POCKET }
      kept = bodies.reduce(Set({Int32, Int32}).new) { |all, body| all | body }
      return [carve(area)] if kept.size < HOLLOW

      kept.each { |spot| @floor.set spot[0], spot[1], Terrain::DirtFloor }
      reach bodies
      reached = divide area, kept
      reached.empty? ? [entry(kept, area)] : reached
    end

    # The square of *kept* nearest the middle of *area*, as a rectangle of
    # one.
    private def entry(kept : Set({Int32, Int32}), area : Area) : Area
      middle = area.middle
      spot = kept.min_by { |square| {Route.apart(square, middle), square[1], square[0]} }
      Area.new spot[0], spot[1], 1, 1
    end

    # Joins each of *bodies* after the first to the nearest square of the
    # ones before it.
    private def reach(bodies : Array(Set({Int32, Int32}))) : Nil
      joined = bodies.first.to_a
      bodies.skip(1).each do |body|
        middle = body.to_a.sum(&.[0]) // body.size
        centre = body.to_a.sum(&.[1]) // body.size
        start = body.min_by { |spot| {Route.apart(spot, {middle, centre}), spot[1], spot[0]} }
        goal = joined.min_by { |spot| {Route.apart(spot, start), spot[1], spot[0]} }

        join Area.new(start[0], start[1], 1, 1), Area.new(goal[0], goal[1], 1, 1)
        joined.concat body.to_a
      end
    end

    # The bodies of squares in *open*, joined side to side or corner to
    # corner, largest first.
    private def split(open : Set({Int32, Int32})) : Array(Set({Int32, Int32}))
      found = [] of Set({Int32, Int32})
      seen = Set({Int32, Int32}).new

      open.to_a.sort_by! { |spot| {spot[1], spot[0]} }.each do |start|
        next if seen.includes? start

        body = Set{start}
        seen << start
        queue = [start]
        while spot = queue.pop?
          Direction.values.each do |direction|
            near = direction.from spot[0], spot[1]
            next unless open.includes? near
            next if seen.includes? near

            seen << near
            body << near
            queue << near
          end
        end

        found << body
      end

      found.sort_by! { |body| -body.size }
    end

    # Divides the cave *kept* inside *area* into caverns. Answers a square of
    # each for a corridor to reach.
    private def divide(area : Area, kept : Set({Int32, Int32})) : Array(Area)
      found = [] of Area
      (area.y...area.y + area.rows).step(CAVERN[1]) do |top|
        (area.x...area.x + area.columns).step(CAVERN[0]) do |left|
          cell = Area.new left, top,
            Math.min(CAVERN[0], area.x + area.columns - left),
            Math.min(CAVERN[1], area.y + area.rows - top)
          inside = 0
          cell.each { |column, row| inside += 1 if kept.includes?({column, row}) }
          next unless inside >= ROOMIEST

          @caverns << cell
          found << entry(kept.select { |spot| cell.holds? spot[0], spot[1] }.to_set, cell)
        end
      end

      found
    end

    # Mirrors the floor across, down, both or neither, as rolled.
    #
    # It runs once the rooms, the caves and the corridors are dug and before
    # anything else is put down, so only the rock, the ground and the list of
    # rooms move.
    private def mirror : Nil
      stream = @rng.derive "mirror"
      across = stream.rand(2).zero?
      down = stream.rand(2).zero?
      return unless across || down

      columns = @floor.columns
      rows = @floor.rows
      turned = Floor.solid @floor.id, columns, rows
      @floor.each do |column, row, tile|
        turned.set across ? columns - 1 - column : column,
          down ? rows - 1 - row : row, tile.terrain
      end
      @floor = turned

      flip = ->(zone : Area) do
        Area.new(across ? columns - 1 - zone.right : zone.x,
          down ? rows - 1 - zone.bottom : zone.y, zone.columns, zone.rows)
      end
      @rooms.map! { |room| flip.call room }
      @caverns.map! { |cavern| flip.call cavern }
    end

    # Joins *near* and *far* with one corridor.
    #
    # Two straight lengths meeting at a right angle, from the middle of one
    # room to the middle of the other, so a corridor never doubles back.
    # Which length comes first is rolled, so the corner falls on either side.
    #
    # When the rolled way would run beside a corridor already dug and the
    # other way would run beside it less, the other way is taken. Two
    # corridors side by side are then rare rather than common.
    private def join(near : Area, far : Area) : Nil
      stream = @rng.derive "corridor:#{near}:#{far}"
      from = near.middle
      to = far.middle
      first = stream.rand(2).zero?

      rolled = route from, to, first
      other = route from, to, !first
      chosen = beside(other) < beside(rolled) ? other : rolled

      chosen.each { |spot| tunnel spot[0], spot[1] }
    end

    # The squares from *from* to *to*, along the row first when *level* is
    # true and down the column first when it is false.
    private def route(from : {Int32, Int32}, to : {Int32, Int32},
                      level : Bool) : Array({Int32, Int32})
      found = [] of {Int32, Int32}
      corner = level ? {to[0], from[1]} : {from[0], to[1]}

      {from, corner}.zip({corner, to}).each do |start, finish|
        if start[1] == finish[1]
          Range.new(Math.min(start[0], finish[0]), Math.max(start[0], finish[0]))
            .each { |column| found << {column, start[1]} }
        else
          Range.new(Math.min(start[1], finish[1]), Math.max(start[1], finish[1]))
            .each { |row| found << {start[0], row} }
        end
      end

      found
    end

    # How many new squares of *path* would lie beside a corridor already dug
    # that is not on *path*.
    private def beside(path : Array({Int32, Int32})) : Int32
      on = path.to_set
      path.count do |spot|
        next false unless @floor.contains? spot[0], spot[1]
        next false unless @floor.terrain(spot[0], spot[1]).rock?

        Direction.values.any? do |direction|
          next false if direction.diagonal?

          near = direction.from spot[0], spot[1]
          @halls.includes?(near) && !on.includes?(near)
        end
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
      @halls << {x, y}
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

    # Puts the two staircases in two different rooms or caverns.
    #
    # A floor with one has nowhere to put the second staircase, and `Audit`
    # faults it.
    #
    # Nothing here reads the floor above or below. Where a staircase lands
    # is rolled on this floor's own stream, over this floor's own rooms, so
    # the staircases of two floors do not line up.
    #
    # The down staircase goes in a zone `#distant` from the up one. The first
    # draw picks both zones, and the down zone is drawn again from the
    # distant ones only when that pick is too near.
    private def stairs : Nil
      places = zones
      return if places.size < 2

      stream = @rng.derive "stairs"
      up, down = places.sample(2, stream)

      arrival = put stream, up, Terrain::StairsUp
      @arrival = up

      far = distant places, up, arrival
      down = far.sample stream unless far.empty? || far.includes?(down)
      put stream, down, Terrain::StairsDown
    end

    # Every zone of *places* other than *from* that is at least half as many
    # steps from *start* as the farthest one is.
    #
    # A zone's steps are those to its nearest square, walking over the dug
    # floor and through its doors. The farthest zone always passes, and on a
    # floor of two or three zones it is often the only one. Empty only when
    # no other zone can be walked to.
    private def distant(places : Array(Area), from : Area,
                        start : {Int32, Int32}) : Array(Area)
      flood = Descent.toward surveyed, start, @floor.columns * @floor.rows, doors: true

      reached = places.compact_map do |zone|
        next if zone == from

        nearest = nil
        zone.each do |column, row|
          steps = flood[column, row]
          nearest = steps if steps && (nearest.nil? || steps < nearest)
        end
        nearest.try { |steps| {zone, steps} }
      end
      return [] of Area if reached.empty?

      most = reached.max_of &.[1]
      reached.select { |pair| pair[1] * 2 >= most }.map &.[0]
    end

    # Knowledge of every open square of the floor as it is dug so far.
    private def surveyed : Knowledge
      known = Knowledge.new @floor.id
      @floor.each do |column, row, tile|
        known.touch @floor, column, row unless tile.terrain.rock?
      end
      known
    end

    # Puts *terrain* on a square of *room* nothing else is on, and answers
    # the square.
    private def put(stream : Rng, room : Area, terrain : Terrain) : {Int32, Int32}
      spot = plain(room).sample stream
      @floor.set spot[0], spot[1], terrain
      spot
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
        next unless @floor.terrain(column, row).floor?

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

    # Puts creatures in *room*, as `Spawns` says for this depth.
    #
    # The first creature's kind is rolled from every kind that appears at
    # the floor's depth. A kind that appears alone has the room to itself.
    # Any other is joined by more of its species that also go about in
    # company, and every creature in the room is in one band. `Floor#place`
    # writes the band down.
    #
    # Each rolls its hit points from its kind's hit dice.
    #
    # The room with the up staircase in it gets none. A character who arrives
    # standing next to a goblin has been given no turn to decide anything.
    private def inhabit(room : Area, index : Int32) : Nil
      return if room == @arrival

      stream = @rng.derive "monsters:#{index}:#{room}"
      density = Spawns.density @depth
      return unless stream.rand(100) < density.inhabited

      first = Spawns.pick stream, @depth
      company = Spawns.weights @depth, first.species, alone: false
      count = first.alone? || company.empty? ? 1 : stream.rand(Spawns.crowd(first, @depth))
      band = "#{@floor.id}-#{index}"

      count.times do |which|
        kind = which.zero? ? first : Items.pick(stream, company)
        spot = plain(room).sample stream
        health = kind.hit_dice.roll stream

        @floor.place Monster.new(kind, spot[0], spot[1], band,
          hit_points: health, max_hit_points: health)
      end
    end
  end
end
