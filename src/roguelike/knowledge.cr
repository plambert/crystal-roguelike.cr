require "json"
require "../roguelike"

module Roguelike
  # What one square looked like the last time somebody saw it.
  #
  # A memory is a copy rather than a view. The floor goes on changing after a
  # creature looks away, and what they remember does not.
  class Memory
    include JSON::Serializable

    # What the square was made of.
    getter terrain : Terrain

    # What was fitted to it, if anything.
    getter fixture : Fixture?

    # What was lying on top of the pile, if anything. This is the one a map
    # draws. `#under` holds the rest of the pile.
    getter item : Item?

    # Which turn this was seen on.
    getter turn : Int32

    # How well the item on the square was made out.
    #
    # `Regard::Everything` for an item looked at from close enough to read.
    # `Regard::Kind` for one seen from further off than `Regards::READING`:
    # the character made out a scroll and not what was written on it.
    #
    # It has a default, so a square remembered before this field existed
    # loads as one the character made everything out on. That is what those
    # saves meant: the name was written in full whatever the distance.
    getter regard : Regard = Regard::Everything

    # Whether the door was seen with a spike in it.
    #
    # `nil` rather than false for a square without one, so a memory written
    # before spikes existed and one written now read the same.
    @spiked : Bool? = nil

    # What was lying under `#item`, bottom first. `nil` when nothing was.
    #
    # A square with one item or none writes no field, so it writes what it
    # wrote before this existed. A memory read from an older save has nothing
    # under its top item.
    getter under : Array(Item)? = nil

    def initialize(@terrain : Terrain, @fixture : Fixture? = nil,
                   @item : Item? = nil, @turn : Int32 = 0,
                   @regard : Regard = Regard::Everything,
                   spiked : Bool = false, under : Array(Item)? = nil)
      @spiked = spiked || nil
      @under = under unless under.nil? || under.empty?
    end

    # Every item remembered here, bottom first and `#item` last. Empty for a
    # square seen with nothing on it.
    def pile : Array(Item)
      found = @under.try(&.dup) || [] of Item
      @item.try { |top| found << top }
      found
    end

    # Whether any item remembered here passes the block.
    def holds?(& : Item -> Bool) : Bool
      @under.try &.each { |item| return true if yield item }
      top = @item
      top ? (yield top) : false
    end

    # Whether the door was seen with a spike in it.
    def spiked? : Bool
      @spiked == true
    end

    # How many turns ago this was seen, as of *turn*.
    def age(turn : Int32) : Int32
      Math.max turn - @turn, 0
    end

    def ==(other : Memory) : Bool
      @terrain == other.terrain && @fixture == other.fixture &&
        @item == other.item && @turn == other.turn && @regard == other.regard &&
        spiked? == other.spiked? && @under == other.under
    end

    def to_s(io : IO) : Nil
      io << "Memory(" << @terrain
      io << " +" << @fixture if @fixture
      pile.each { |item| io << " +" << item }
      io << ' ' << @regard unless @regard.everything?
      io << " spiked" if spiked?
      io << " turn " << @turn << ')'
    end
  end

  # Where somebody was last known to be.
  #
  # A monster that has seen the character remembers where, and how long ago.
  # It goes to that square rather than to where the character is now.
  record Sighting, x : Int32, y : Int32, turn : Int32 do
    include JSON::Serializable

    # Where they were.
    def at : {Int32, Int32}
      {x, y}
    end

    # How many turns ago that was, as of *now*.
    def age(now : Int32) : Int32
      Math.max now - turn, 0
    end
  end

  # What somebody believes about one floor.
  #
  # What is on a floor and what somebody thinks is on a floor are two
  # different things. This is the second one. The character gets one per floor
  # they have walked on, and a monster band will get one of its own.
  #
  # Nothing here reads the floor unless it is told to. `#learn` is the one way
  # anything gets in, and it takes the squares a `Vision` says can be seen.
  class Knowledge
    include JSON::Serializable

    # Which floor this is about.
    getter floor : String

    # What each square looked like when it was last seen. The key is
    # `Floor.spot`, the same key `Floor#litter` uses.
    @[JSON::Field(converter: Roguelike::Sorted(Hash(String, Roguelike::Memory)))]
    getter memories : Hash(String, Memory)

    # Where each creature was last seen, by who.
    #
    # `PLAYER` is the key for the character. `.creature` is the key for a
    # monster.
    @[JSON::Field(converter: Roguelike::Sorted(Hash(String, Roguelike::Sighting)))]
    getter sightings : Hash(String, Sighting)

    # Squares known to be open, with nothing else known about them.
    #
    # Seeing somebody across a square says nothing solid is in the way. It
    # does not say what the square is made of, so there is no `Memory` for
    # one of these: `#walkable?` answers true and `#seen?` answers false,
    # because it has not been seen.
    #
    # The key is `Floor.spot`, the same key `#memories` uses.
    @[JSON::Field(converter: Roguelike::Sorted(Set(String)))]
    getter openings : Set(String)

    # Shut doors found to be spiked against whoever holds this knowledge.
    #
    # A band that tried one and could not open it stops pathing through it.
    # Seeing the door open again takes it off this list.
    #
    # `nil` rather than empty when there are none, so knowledge that holds
    # none writes what it wrote before spikes existed. The key is
    # `Floor.spot`.
    @[JSON::Field(converter: Roguelike::Sorted(Set(String)))]
    @barred : Set(String)? = nil

    # How many times what is known of the ground has changed.
    #
    # A square seen for the first time, a square whose terrain or top item
    # changed, an opening and a door found barred each count. A square looked
    # at again and found the same does not. `#chambers` is rebuilt only when
    # this has moved.
    #
    # It is not in a save. Knowledge read back starts again from zero, and
    # nothing compares the number across two objects.
    @[JSON::Field(ignore: true)]
    getter revision : Int32 = 0

    # The chambers worked out at `#revision`, or `nil` before the first ask.
    @[JSON::Field(ignore: true)]
    @chambers : Chambers? = nil

    # What is known of the ground as flat flags, or `nil` until a flood or
    # a cut asks.
    @[JSON::Field(ignore: true)]
    @grid : Grid? = nil

    # The rows `#to_map` drew last, and what it drew them from.
    @[JSON::Field(ignore: true)]
    @drawn : Array(String)? = nil

    # :ditto:
    @[JSON::Field(ignore: true)]
    @drawn_from : {Int32, Int32, Int32, Char}? = nil

    def initialize(@floor : String,
                   @memories : Hash(String, Memory) = {} of String => Memory,
                   @sightings : Hash(String, Sighting) = {} of String => Sighting,
                   @openings : Set(String) = Set(String).new,
                   @barred : Set(String)? = nil)
    end

    # Every door found spiked against whoever holds this.
    def barred : Set(String)
      @barred || Set(String).new
    end

    # Records that the door at *x*, *y* would not open.
    def bar(x : Int32, y : Int32) : Nil
      changed if (@barred ||= Set(String).new).add?(Floor.spot x, y)
      regrid x, y
    end

    # Whether the door at *x*, *y* is known to be spiked against whoever
    # holds this.
    def barred?(x : Int32, y : Int32) : Bool
      @barred.try(&.includes? Floor.spot(x, y)) || false
    end

    # Forgets that the door at *x*, *y* would not open.
    private def unbar(x : Int32, y : Int32) : Nil
      held = @barred
      return unless held

      changed if held.delete Floor.spot(x, y)
      @barred = nil if held.empty?
    end

    # Counts one change to what is known of the ground.
    private def changed : Nil
      @revision += 1
    end

    # The chambers of a floor of *columns* by *rows*, as this knowledge
    # stands.
    #
    # Worked out once per `#revision`. Walking over ground already known asks
    # again and gets the same object back.
    def chambers(columns : Int32, rows : Int32) : Chambers
      held = @chambers
      if held && held.revision == @revision && held.columns == columns && held.rows == rows
        return held
      end

      @chambers = Chambers.of self, columns, rows
    end

    # What is known of the ground as flat flags.
    #
    # Built on the first ask and kept up to date by every write after that.
    def grid : Grid
      @grid ||= build_grid
    end

    # A grid over every square remembered or crossed, with `Grid::MARGIN`
    # squares round them.
    private def build_grid : Grid
      left = top = Int32::MAX
      right = bottom = Int32::MIN
      spots = @memories.keys.map { |key| Floor.unspot key }
      opened = @openings.map { |key| Floor.unspot key }

      {spots, opened}.each do |list|
        list.each do |spot|
          left = Math.min left, spot[0]
          top = Math.min top, spot[1]
          right = Math.max right, spot[0]
          bottom = Math.max bottom, spot[1]
        end
      end

      return Grid.new(0, 0, 0, 0) if left > right

      margin = Grid::MARGIN
      built = Grid.new left - margin, top - margin,
        right - left + 1 + 2 * margin, bottom - top + 1 + 2 * margin

      opened.each { |spot| built[spot[0], spot[1]] = Grid::OPENED }
      index = 0
      @memories.each_value do |memory|
        spot = spots[index]
        index += 1
        barred = memory.terrain.door? && barred?(spot[0], spot[1])
        built[spot[0], spot[1]] = Grid.remembered(memory, barred)
      end

      built
    end

    # Writes what is known of *x*, *y* into the grid, when there is one.
    #
    # A square outside the grid drops it, and the next ask builds a larger
    # one.
    private def regrid(x : Int32, y : Int32, memory : Memory? = self[x, y]) : Nil
      held = @grid
      return unless held

      unless held.covers? x, y
        @grid = nil
        return
      end

      held[x, y] = if memory
                     Grid.remembered(memory, memory.terrain.door? && barred?(x, y))
                   elsif @openings.includes? Floor.spot(x, y)
                     Grid::OPENED
                   else
                     0_u8
                   end
    end

    # The key `#sightings` holds the character under.
    PLAYER = "player"

    # The key `#sightings` holds the monster *id* under.
    def self.creature(id : Int32) : String
      "creature-#{id}"
    end

    # Records that *who* was at *x*, *y* on *turn*.
    def saw(who : String, x : Int32, y : Int32, turn : Int32) : Nil
      @sightings[who] = Sighting.new x, y, turn
    end

    # Where *who* was last seen. `nil` for somebody never seen.
    def sighting(who : String) : Sighting?
      @sightings[who]?
    end

    # Forgets where *who* was.
    def lost(who : String) : Nil
      @sightings.delete who
    end

    # A copy of this knowledge, to hand a member of a band as a start.
    #
    # A band whose members each keep their own beliefs gives each of them one
    # of these. What one of them learns after that is its own.
    def copy : Knowledge
      Knowledge.new @floor, @memories.dup, @sightings.dup, @openings.dup,
        @barred.try(&.dup)
    end

    # What *x*, *y* looked like. `nil` for a square never seen.
    def [](x : Int32, y : Int32) : Memory?
      @memories[Floor.spot x, y]?
    end

    # :ditto:
    def [](spot : {Int32, Int32}) : Memory?
      self[spot[0], spot[1]]
    end

    # Whether *x*, *y* has ever been seen.
    def seen?(x : Int32, y : Int32) : Bool
      @memories.has_key? Floor.spot(x, y)
    end

    # Whether anything at all is known of *spot*: it has been seen, or
    # somebody was seen across it.
    def known?(spot : {Int32, Int32}) : Bool
      seen?(spot[0], spot[1]) || @openings.includes?(Floor.spot spot[0], spot[1])
    end

    # Whether what is known of *x*, *y* could be walked on.
    #
    # A square never seen and never crossed answers false. A band does not
    # walk through what it knows nothing about, which is what keeps it off a
    # shortcut it has never found. A door remembered as shut answers false as
    # well, until somebody looks at it again and finds it open.
    #
    # What is remembered wins over what was inferred. A square seen to be a
    # wall is a wall, whatever was once guessed about it.
    def walkable?(x : Int32, y : Int32) : Bool
      grid.walkable? x, y
    end

    # :ditto:
    def walkable?(spot : {Int32, Int32}) : Bool
      walkable? spot[0], spot[1]
    end

    # Whether what is known of *x*, *y* could be crossed on the way
    # somewhere, counting a door remembered as shut.
    #
    # The character opens any door they can reach. A shut door on the way to
    # a square they picked costs them a turn rather than stopping them, so a
    # route crosses one. A door remembered as shut that somebody else has
    # since opened is crossed for the same reason.
    #
    # A door known to be spiked against whoever holds this is not crossed.
    #
    # A band whose members open doors paths with this. One whose members do
    # not paths with `#walkable?`.
    def crossable?(x : Int32, y : Int32) : Bool
      grid.crossable? x, y
    end

    # :ditto:
    def crossable?(spot : {Int32, Int32}) : Bool
      crossable? spot[0], spot[1]
    end

    # How many squares have been seen.
    def size : Int32
      @memories.size
    end

    # Whether nothing has been seen.
    def empty? : Bool
      @memories.empty?
    end

    # Records what *floor* holds at *x*, *y* as of *turn*.
    #
    # The whole pile is remembered. The character sees every item on a square
    # in sight, and explore walks to one the pickup takes wherever it lies in
    # the pile.
    #
    # Whatever was remembered before is replaced. A square looked at again
    # shows what is there now, not what was there before.
    #
    # *regard* says how well the item lying there was made out. The default
    # makes everything out, which is what a caller that says nothing about
    # distance means.
    #
    # A worse look does not undo a better one. A square whose item has not
    # changed keeps the best regard it has ever been seen with, so glancing
    # back at a spear from across a hall does not turn a cursed -2 spear back
    # into a spear.
    def see(floor : Floor, x : Int32, y : Int32, turn : Int32 = 0,
            regard : Regard = Regard::Everything) : Nil
      return unless floor.contains? x, y

      fitting = floor.fixture x, y
      pile = floor.items x, y
      lying = pile.last?.try(&.copy)
      beneath = pile.size > 1 ? pile[0, pile.size - 1].map(&.copy) : nil

      held = self[x, y]
      made_out = regard
      made_out = made_out.at_least held.regard if held && held.item == lying

      terrain = floor.terrain x, y
      changed if held.nil? || held.terrain != terrain || held.item.try(&.id) != lying.try(&.id)
      memory = Memory.new terrain,
        fitting.try(&.copy), lying, turn, made_out, floor.spiked?(x, y), beneath
      @memories[Floor.spot x, y] = memory
      unbar x, y unless terrain.closed_door?
      regrid x, y, memory
    end

    # Records the shape of *x*, *y* and what is fixed to it, and no more.
    #
    # Reaching out in the dark says whether there is a wall there, and a
    # bracket bolted to the wall is felt the same way. It does not say what
    # is lying on the floor, so whatever was remembered about that is kept
    # rather than replaced.
    #
    # This is also what a door opened or closed by hand records. Somebody who
    # has just shut a door knows it is shut, whether or not they can see it.
    def touch(floor : Floor, x : Int32, y : Int32, turn : Int32 = 0) : Nil
      return unless floor.contains? x, y

      held = self[x, y]
      terrain = floor.terrain x, y
      changed if held.nil? || held.terrain != terrain
      memory = Memory.new terrain,
        floor.fixture(x, y).try(&.copy), held.try(&.item), turn,
        held.try(&.regard) || Regard::Nothing, floor.spiked?(x, y),
        held.try(&.under)
      @memories[Floor.spot x, y] = memory
      unbar x, y unless terrain.closed_door?
      regrid x, y, memory
    end

    # Writes *memory* down at *x*, *y*, over whatever was there.
    #
    # Everything else here builds a memory from what a creature looked at.
    # This is for a caller that has built one of its own: a scroll that says
    # where something is without saying how the square got that way.
    def remember(x : Int32, y : Int32, memory : Memory) : Nil
      changed
      @memories[Floor.spot x, y] = memory
      regrid x, y, memory
    end

    # Records that *x*, *y* can be crossed, and nothing else about it.
    #
    # This is what seeing somebody across a square gives. The line that
    # reached them ran through the square, so nothing solid is in it. What
    # the square is made of is not known, and this does not guess: a `Memory`
    # written here would claim the square is a stone floor, or an open door,
    # or a staircase, none of which the creature has looked at.
    def opening(x : Int32, y : Int32) : Nil
      changed if @openings.add?(Floor.spot x, y)
      regrid x, y
    end

    # Records every square *vision* can see. This is the one way anything gets
    # in.
    #
    # How well the item on each square was made out comes from how far the
    # square is from where the creature stands. `Regards.of_item` is the
    # rule.
    def learn(floor : Floor, vision : Vision, turn : Int32 = 0) : Nil
      origin = vision.origin

      vision.each do |spot|
        see floor, spot[0], spot[1], turn, Regards.of_item(origin, spot)
      end
    end

    # Every square remembered as *terrain*.
    #
    # The staircase a character has walked past is found this way. What is on
    # the floor now is not asked about: a route is walked over what somebody
    # remembers, and so is the arrow that points at it.
    def where(terrain : Terrain) : Array({Int32, Int32})
      found = [] of {Int32, Int32}
      each { |column, row, memory| found << {column, row} if memory.terrain == terrain }
      found
    end

    # Yields every square that has been seen, with what was on it.
    def each(& : Int32, Int32, Memory ->) : Nil
      @memories.each do |spot, memory|
        column, row = Floor.unspot spot
        yield column, row, memory
      end
    end

    # Yields every square remembered with an item on it, with what was on it.
    def each_item(& : Int32, Int32, Memory ->) : Nil
      @memories.each do |spot, memory|
        next unless memory.item

        column, row = Floor.unspot spot
        yield column, row, memory
      end
    end

    # Yields every square remembered with a fixture on it, with what was on
    # it.
    def each_fixture(& : Int32, Int32, Memory ->) : Nil
      @memories.each do |spot, memory|
        next unless memory.fixture

        column, row = Floor.unspot spot
        yield column, row, memory
      end
    end

    # Forgets everything.
    def forget : Nil
      changed
      @memories.clear
      @sightings.clear
      @openings.clear
      @barred = nil
      @grid = nil
    end

    # *floor* drawn as it is remembered, with *unknown* wherever it is not.
    #
    # An observation writes it every turn, so it is drawn once per
    # `#revision` and kept. A square's terrain moves the revision whenever it
    # changes, so a kept drawing is never out of date.
    def to_map(floor : Floor, unknown : Char = '?') : Array(String)
      key = {@revision, floor.columns, floor.rows, unknown}
      held = @drawn
      return held.dup if held && @drawn_from == key

      made = draw floor.columns, floor.rows, unknown
      @drawn = made
      @drawn_from = key
      made.dup
    end

    # The rows `#to_map` answers, worked out from the memories alone.
    #
    # It walks the squares that have been seen rather than every square of
    # the floor, so a floor seen a little is drawn quickly.
    private def draw(columns : Int32, rows : Int32, unknown : Char) : Array(String)
      grid = Array.new(rows) { Array.new(columns, unknown) }

      @memories.each do |spot, memory|
        column, row = Floor.unspot spot
        next unless 0 <= column < columns && 0 <= row < rows

        grid[row][column] = memory.terrain.mark
      end

      grid.map &.join
    end

    def ==(other : Knowledge) : Bool
      @floor == other.floor && @memories == other.memories &&
        @sightings == other.sightings && @openings == other.openings &&
        barred == other.barred
    end

    def to_s(io : IO) : Nil
      io << "Knowledge(" << @floor << ' ' << @memories.size << " seen)"
    end
  end

  # What a `Knowledge` holds of the ground, as flags in one flat array.
  #
  # `Knowledge#walkable?` and `Knowledge#crossable?` read it, and so do the
  # floods and the chambers cut. It covers every square that is remembered
  # or crossed, with a margin, and answers nothing known for a square
  # outside it.
  #
  # The knowledge writes each change into it as the change is made, so it
  # never needs building again while what is learned stays inside it.
  class Knowledge::Grid
    # The square has a memory.
    SEEN = 1_u8

    # `Knowledge#walkable?` holds.
    WALK = 2_u8

    # `Knowledge#crossable?` holds.
    CROSS = 4_u8

    # The square is remembered as walkable and not a door.
    GROUND = 8_u8

    # The square is remembered with an item on it.
    ITEM = 16_u8

    # How many squares the grid reaches past what was known when it was
    # built.
    MARGIN = 24

    # The first column and row it covers, and how many of each.
    getter left : Int32
    getter top : Int32
    getter columns : Int32
    getter rows : Int32

    @flags : Bytes

    # Which crossable squares are joined to which, across the eight ways
    # off a square, as a union-find over the grid. `nil` until `#joined?`
    # asks, and again after a square stops being crossable.
    @joined : Array(Int32)? = nil

    def initialize(@left : Int32, @top : Int32, @columns : Int32, @rows : Int32)
      @flags = Bytes.new @columns * @rows
    end

    # Whether *x*, *y* lies inside the grid.
    def covers?(x : Int32, y : Int32) : Bool
      x >= @left && y >= @top && x < @left + @columns && y < @top + @rows
    end

    # The flags of *x*, *y*. Zero outside the grid.
    def [](x : Int32, y : Int32) : UInt8
      covers?(x, y) ? @flags[(y - @top) * @columns + x - @left] : 0_u8
    end

    # Sets the flags of *x*, *y*, which must lie inside the grid.
    #
    # A square that becomes crossable joins the crossable squares around
    # it. One that stops being crossable may split what it joined, so the
    # joins are worked out again on the next ask.
    def []=(x : Int32, y : Int32, flags : UInt8) : UInt8
      at = (y - @top) * @columns + x - @left
      before = @flags[at]
      @flags[at] = flags

      if sets = @joined
        if before & CROSS != 0 && flags & CROSS == 0
          @joined = nil
        elsif before & CROSS == 0 && flags & CROSS != 0
          join_around sets, at
        end
      end

      flags
    end

    # Whether *one* and *other* are both crossable and joined by crossable
    # squares across the eight ways off a square.
    #
    # A flood that crosses doors reaches a square from one beside where it
    # starts exactly when this holds for the two.
    def joined?(one : {Int32, Int32}, other : {Int32, Int32}) : Bool
      return false unless crossable?(one[0], one[1]) && crossable?(other[0], other[1])

      sets = @joined ||= build_joined
      root(sets, (one[1] - @top) * @columns + one[0] - @left) ==
        root(sets, (other[1] - @top) * @columns + other[0] - @left)
    end

    private def build_joined : Array(Int32)
      sets = Array(Int32).new(@flags.size) { |square| square }
      @flags.each_with_index do |flags, square|
        join_around sets, square unless flags & CROSS == 0
      end
      sets
    end

    # Joins the crossable square *at* to every crossable square around it.
    private def join_around(sets : Array(Int32), at : Int32) : Nil
      column = at % @columns
      row = at // @columns

      (Math.max(row - 1, 0)..Math.min(row + 1, @rows - 1)).each do |near_row|
        (Math.max(column - 1, 0)..Math.min(column + 1, @columns - 1)).each do |near_column|
          near = near_row * @columns + near_column
          next if near == at || @flags[near] & CROSS == 0

          one = root sets, at
          other = root sets, near
          sets[Math.max(one, other)] = Math.min(one, other) unless one == other
        end
      end
    end

    private def root(sets : Array(Int32), at : Int32) : Int32
      while (parent = sets[at]) != at
        grand = sets[parent]
        sets[at] = grand
        at = grand
      end
      at
    end

    # Copies the flags of the squares of a floor of *columns* by *rows*
    # into *into*, row by row. A square outside the grid is left as it is.
    def copy(into : Bytes, columns : Int32, rows : Int32) : Nil
      first = Math.max 0, @left
      last = Math.min columns, @left + @columns
      return if first >= last

      (Math.max(0, @top)...Math.min(rows, @top + @rows)).each do |row|
        width = last - first
        @flags[(row - @top) * @columns + first - @left, width]
          .copy_to into[row * columns + first, width]
      end
    end

    def walkable?(x : Int32, y : Int32) : Bool
      self[x, y] & WALK != 0
    end

    def crossable?(x : Int32, y : Int32) : Bool
      self[x, y] & CROSS != 0
    end

    # The flags a square remembered as *memory* takes. *barred* says
    # whether it is a door known to be spiked.
    def self.remembered(memory : Memory, barred : Bool) : UInt8
      terrain = memory.terrain
      flags = SEEN
      flags |= ITEM if memory.item
      if terrain.passable?
        flags |= WALK | CROSS
        flags |= GROUND unless terrain.door?
      elsif terrain.door? && !barred
        flags |= CROSS
      end
      flags
    end

    # The flags of an opening, a square crossed and never seen.
    OPENED = WALK | CROSS
  end
end
