require "json"
require "./fixture"
require "./item"
require "./monster"
require "./tile"

module Roguelike
  # One floor of the world.
  #
  # The world keeps a floor after the player leaves it. A floor keeps its
  # `#id` for as long as the world lasts.
  #
  # The id is what a run's randomness derives from. `rng.derive "worldgen",
  # floor.id` uses it. So the id has to be the floor's own name. A count of
  # how many floors exist would bring back an order dependency.
  #
  # A stored floor holds its terrain as text. One string per row. The same
  # characters a floor file uses. That form is compact. A person can read it.
  # `git diff` can show a change in it.
  #
  # No method here draws a floor. `Ui::FloorCells` puts a floor in front of a
  # `CellGrid`.
  class Floor
    # What this floor is called, for as long as the world lasts.
    getter id : String

    # Cells across.
    getter columns : Int32

    # Cells down.
    getter rows : Int32

    # What is lying on the floor, by square.
    #
    # A square with nothing on it holds no entry. The newest item is last, so
    # a character picking one thing up takes what was dropped last.
    getter litter : Hash(String, Array(Item))

    # Row-major. The index of *x*, *y* is `y * columns + x`.
    #
    # This getter is protected rather than private. `#==` compares two floors
    # through it. A private getter would force a copy of every square.
    protected getter tiles : Array(Tile)

    # Which squares glow on their own, and how brightly.
    #
    # A magically lit room is written this way. The light is part of the
    # floor rather than of anything standing on it, so it does not go out and
    # nothing carries it away.
    #
    # The key is `Floor.spot`, the same key `#litter` uses. A JSON object key
    # has to be a string.
    getter glow : Hash(String, Int32)

    # How much light every square of this floor has whatever else happens.
    #
    # Zero for a dungeon floor, which is dark until somebody brings a light.
    # A town at noon and a cavern with a hole in its roof are the other case,
    # and a spec that is not about light uses this to see the whole floor.
    property ambient : Int32

    # What is fitted to each square: a sconce, and later a brazier or an
    # altar. A fixture is part of the room rather than loot, so it is here
    # rather than in `#litter`.
    #
    # The key is `Floor.spot`, the same key `#litter` uses.
    getter fixtures : Hash(String, Fixture)

    # What is standing on each square.
    #
    # The key is `Floor.spot`, so a square holds at most one creature and
    # finding what is on one costs nothing. A monster carries its own
    # position as well, and `#walk` is what keeps the two in step.
    getter monsters : Hash(String, Monster)

    # The bands the monsters on this floor belong to, by `Band#id`.
    getter bands : Hash(String, Band)

    def initialize(@id : String, @columns : Int32, @rows : Int32, @tiles : Array(Tile),
                   @litter : Hash(String, Array(Item)) = {} of String => Array(Item),
                   @glow : Hash(String, Int32) = {} of String => Int32,
                   @ambient : Int32 = 0,
                   @fixtures : Hash(String, Fixture) = {} of String => Fixture,
                   @monsters : Hash(String, Monster) = {} of String => Monster,
                   @bands : Hash(String, Band) = {} of String => Band)
      wanted = @columns * @rows
      return if @tiles.size == wanted

      raise ArgumentError.new "floor #{@id} is #{@columns}x#{@rows} " \
                              "but holds #{@tiles.size} tiles, not #{wanted}"
    end

    # A floor of nothing but *terrain*. A generator carves one of these.
    def self.solid(id : String, columns : Int32, rows : Int32,
                   terrain : Terrain = Terrain::Granite) : Floor
      new id, columns, rows, Array.new(columns * rows) { Tile.new terrain }
    end

    # The floor in *path*. The floor takes its id from the file name.
    #
    # A floor file holds nothing but the map. The file name is the only place
    # an id can come from. Renaming a floor file makes a different floor.
    def self.load(path : Path | String) : Floor
      file = Path.new path

      parse File.basename(file.to_s, file.extension), File.read(file)
    end

    # The floor *text* names. One row per line.
    #
    # A row shorter than the longest row fills out with rock. An editor that
    # trims trailing whitespace then cannot change a floor.
    def self.parse(id : String, text : String) : Floor
      parse id, text.lines.map(&.chomp)
    end

    # :ditto:
    #
    # Three of the characters a floor file may hold are not terrain. Each sits
    # on an open square and says something extra about it.
    #
    # `Terrains::GLOW` is a square that glows on its own. `FixtureKind`'s
    # marks are a fitting standing on the square. Both are recorded apart from
    # the terrain, and `#to_map` writes the plain terrain back.
    #
    # Neither says what the square under it is made of, so `#under` takes that
    # from the squares beside it. A sconce in a dirt room stands on dirt.
    def self.parse(id : String, lines : Array(String)) : Floor
      rows = lines.reject(&.empty?)
      raise ArgumentError.new "floor #{id} has no rows" if rows.empty?

      columns = rows.max_of &.size
      read = ->(column : Int32, row : Int32) do
        line = rows[row]
        column < line.size ? line[column] : Terrains::FILL
      end

      tiles = Array(Tile).new columns * rows.size
      glow = {} of String => Int32
      fixtures = {} of String => Fixture
      monsters = {} of String => Monster
      bands = {} of String => Band

      rows.each_index do |row|
        columns.times do |column|
          mark = read.call column, row
          fitting = FixtureKind.from_mark? mark
          species = Species.from_mark? mark

          if fitting
            fixtures[spot column, row] = Fixture.new fitting[0], fitting[1],
              bolted_to(read, columns, rows.size, column, row)
            mark = under read, columns, rows.size, column, row
          elsif species
            # Each in a band of one. A generator will put several in one band
            # and this is where that will be decided.
            band = Band.new "#{id}-#{species.to_s.downcase}-#{column},#{row}"
            bands[band.id] = band
            monsters[spot column, row] = Monster.new species, column, row, band.id
            mark = under read, columns, rows.size, column, row
          elsif mark == Terrains::GLOW
            glow[spot column, row] = Terrains::GLOW_LIGHT
            mark = under read, columns, rows.size, column, row
          end

          tiles << Tile.new(Terrain.from_mark(mark))
        end
      end

      new id, columns, rows.size, tiles, glow: glow, fixtures: fixtures,
        monsters: monsters, bands: bands
    end

    # What the square at *column*, *row* is made of, for a mark that does not
    # say.
    #
    # The first square beside it that is ground to stand on, looked at west,
    # east, north and then south. A stone floor when none of them is.
    private def self.under(read, columns : Int32, rows : Int32,
                           column : Int32, row : Int32) : Char
      {% begin %}
        { {-1, 0}, {1, 0}, {0, -1}, {0, 1} }.each do |step|
          beside = {column + step[0], row + step[1]}
          next unless 0 <= beside[0] < columns && 0 <= beside[1] < rows

          mark = read.call beside[0], beside[1]
          found = Terrain.from_mark? mark
          return mark if found && found.floor?
        end
      {% end %}

      Terrain::StoneFloor.mark
    end

    # Which wall a fixture at *column*, *row* is bolted to.
    #
    # The one wall touching it on a cardinal side. `nil` when none touches it,
    # and `nil` when more than one does: a fixture in a corner or a corridor
    # has no one wall to be bolted to, so it stands on the floor.
    private def self.bolted_to(read, columns : Int32, rows : Int32,
                               column : Int32, row : Int32) : Direction?
      found = nil.as Direction?

      {Direction::West, Direction::East,
       Direction::North, Direction::South}.each do |direction|
        beside = direction.from column, row
        next unless 0 <= beside[0] < columns && 0 <= beside[1] < rows

        terrain = Terrain.from_mark? read.call(beside[0], beside[1])
        next unless terrain && terrain.blocks_move?

        return if found

        found = direction
      end

      found
    end

    # The width and the height.
    def size : {Int32, Int32}
      {@columns, @rows}
    end

    # Whether *x*, *y* is on the floor.
    def contains?(x : Int32, y : Int32) : Bool
      0 <= x < @columns && 0 <= y < @rows
    end

    # The square at *x*, *y*. The square has to be on the floor.
    def tile(x : Int32, y : Int32) : Tile
      @tiles[index x, y]
    end

    # :ditto: Answers `nil` for a square off the floor.
    def tile?(x : Int32, y : Int32) : Tile?
      return unless contains? x, y

      @tiles[index x, y]
    end

    # What the square at *x*, *y* is made of.
    def terrain(x : Int32, y : Int32) : Terrain
      tile(x, y).terrain
    end

    # Puts *tile* at *x*, *y*.
    def set(x : Int32, y : Int32, tile : Tile) : Nil
      @tiles[index x, y] = tile
    end

    # Makes the square at *x*, *y* out of *terrain*. Opening a door uses
    # this.
    def set(x : Int32, y : Int32, terrain : Terrain) : Nil
      set x, y, tile(x, y).with_terrain(terrain)
    end

    # Whether a creature could walk onto *x*, *y*. A square off the floor
    # answers false.
    def passable?(x : Int32, y : Int32) : Bool
      found = tile? x, y
      found ? found.passable? : false
    end

    # ------------------------------------------------------------ monsters

    # What is standing on *x*, *y*. `nil` for an empty square.
    def monster(x : Int32, y : Int32) : Monster?
      @monsters[Floor.spot x, y]?
    end

    # Whether anything is standing on *x*, *y*.
    def monster?(x : Int32, y : Int32) : Bool
      @monsters.has_key? Floor.spot(x, y)
    end

    # Puts *creature* on the square it says it is on. Answers whether it went.
    #
    # A square already holding something answers false and takes nothing. One
    # square holds one creature.
    def place(creature : Monster) : Bool
      return false unless contains? creature.x, creature.y
      return false if monster? creature.x, creature.y

      @monsters[Floor.spot creature.x, creature.y] = creature
      @bands[creature.band] ||= Band.new creature.band
      true
    end

    # Takes whatever is standing on *x*, *y* off the floor. Answers it.
    def remove(x : Int32, y : Int32) : Monster?
      @monsters.delete Floor.spot(x, y)
    end

    # Moves what stands on *from* to *to*. Answers whether it moved.
    #
    # This is the one way a monster changes square. It keeps the floor's own
    # table and the monster's own position in step.
    def walk(from : {Int32, Int32}, to : {Int32, Int32}) : Bool
      creature = monster from[0], from[1]
      return false unless creature
      return false unless contains? to[0], to[1]
      return false if monster? to[0], to[1]

      @monsters.delete Floor.spot(from[0], from[1])
      creature.move_to to
      @monsters[Floor.spot to[0], to[1]] = creature
      true
    end

    # Yields every monster on this floor, with where it stands.
    def each_monster(& : Int32, Int32, Monster ->) : Nil
      @monsters.each_value { |creature| yield creature.x, creature.y, creature }
    end

    # The band *id* names. `nil` for a band this floor holds none of.
    def band(id : String) : Band?
      @bands[id]?
    end

    # Yields every band with a monster on this floor.
    def each_band(& : Band ->) : Nil
      @bands.each_value { |band| yield band }
    end

    # What the band *creature* belongs to knows about the character.
    #
    # A creature whose band this floor does not hold is asleep. There is no
    # band to have noticed anything.
    def awareness(creature : Monster) : Awareness
      band(creature.band).try(&.awareness) || Awareness::Asleep
    end

    # ------------------------------------------------------------ fixtures

    # What is fitted to *x*, *y*. `nil` for a square with nothing on it.
    def fixture(x : Int32, y : Int32) : Fixture?
      @fixtures[Floor.spot x, y]?
    end

    # Fits *fitting* to *x*, *y*. A `nil` takes whatever is there away.
    def set_fixture(x : Int32, y : Int32, fitting : Fixture?) : Nil
      key = Floor.spot x, y

      if fitting
        @fixtures[key] = fitting
      else
        @fixtures.delete key
      end
    end

    # Yields every fitted square, with what is on it.
    def each_fixture(& : Int32, Int32, Fixture ->) : Nil
      @fixtures.each do |spot, fitting|
        parts = spot.split ','
        yield parts[0].to_i, parts[1].to_i, fitting
      end
    end

    # How brightly *x*, *y* glows on its own. Zero for a square that does not.
    def glow_at(x : Int32, y : Int32) : Int32
      @glow[Floor.spot x, y]? || 0
    end

    # Makes *x*, *y* glow at *level*. A level of zero or less takes the glow
    # away.
    def set_glow(x : Int32, y : Int32, level : Int32) : Nil
      key = Floor.spot x, y

      if level > 0
        @glow[key] = level
      else
        @glow.delete key
      end
    end

    # Yields every square that glows on its own, with how brightly.
    def each_glow(& : Int32, Int32, Int32 ->) : Nil
      @glow.each do |spot, level|
        parts = spot.split ','
        yield parts[0].to_i, parts[1].to_i, level
      end
    end

    # Whether a creature could see through *x*, *y*. A square off the floor
    # answers true.
    def blocks_sight?(x : Int32, y : Int32) : Bool
      found = tile? x, y
      found ? found.blocks_sight? : true
    end

    # Yields every square. In reading order.
    def each(& : Int32, Int32, Tile ->) : Nil
      @rows.times do |row|
        @columns.times { |column| yield column, row, @tiles[index column, row] }
      end
    end

    # Where the first square of *terrain* is. Answers `nil` when the floor
    # has none.
    #
    # `Game.entrance` uses this to find a staircase.
    def find(terrain : Terrain) : {Int32, Int32}?
      each do |column, row, tile|
        return {column, row} if tile.terrain == terrain
      end

      nil
    end

    # The terrain as text. One string per row. A floor file holds this form.
    # A save file holds it too.
    def to_map : Array(String)
      Array.new(@rows) do |row|
        String.build(@columns) do |line|
          @columns.times { |column| line << @tiles[index column, row].terrain.mark }
        end
      end
    end

    private def index(x : Int32, y : Int32) : Int32
      y * @columns + x
    end

    # ------------------------------------------------------------ the floor

    # The key the litter table uses for *x*, *y*.
    #
    # A string, because a JSON object key is a string and a save file holds
    # this table.
    def self.spot(x : Int32, y : Int32) : String
      "#{x},#{y}"
    end

    # What is lying on *x*, *y*, oldest first. An empty array for a bare
    # square.
    def items(x : Int32, y : Int32) : Array(Item)
      @litter[Floor.spot(x, y)]? || [] of Item
    end

    # Whether anything is lying on *x*, *y*.
    def items?(x : Int32, y : Int32) : Bool
      found = @litter[Floor.spot(x, y)]?
      found ? !found.empty? : false
    end

    # Puts *item* on *x*, *y*.
    #
    # A stack joins one already there rather than making a second pile of the
    # same thing.
    def drop(x : Int32, y : Int32, item : Item) : Nil
      pile = @litter[Floor.spot(x, y)] ||= [] of Item
      found = pile.index &.stacks_with?(item)

      if found
        pile[found] = pile[found].add item.count
      else
        pile << item
      end
    end

    # Takes *item* off *x*, *y*. Answers whether it was there.
    def take(x : Int32, y : Int32, item : Item) : Bool
      spot = Floor.spot x, y
      pile = @litter[spot]?
      return false unless pile

      found = pile.index &.same?(item)
      return false unless found

      pile.delete_at found
      @litter.delete spot if pile.empty?
      true
    end

    # Takes everything off *x*, *y* and answers it.
    def clear_items(x : Int32, y : Int32) : Array(Item)
      @litter.delete(Floor.spot(x, y)) || [] of Item
    end

    # Every square with something on it, and what is on it.
    def each_pile(& : Int32, Int32, Array(Item) ->) : Nil
      @litter.each do |spot, pile|
        next if pile.empty?

        parts = spot.split ','
        yield parts[0].to_i, parts[1].to_i, pile
      end
    end

    # What a floor is in a save file.
    struct Stored
      include JSON::Serializable

      getter id : String
      getter map : Array(String)
      getter litter : Hash(String, Array(Item))
      getter glow : Hash(String, Int32)
      getter ambient : Int32
      getter fixtures : Hash(String, Fixture)
      getter monsters : Hash(String, Monster)
      getter bands : Hash(String, Band)

      def initialize(@id : String, @map : Array(String),
                     @litter : Hash(String, Array(Item)) = {} of String => Array(Item),
                     @glow : Hash(String, Int32) = {} of String => Int32,
                     @ambient : Int32 = 0,
                     @fixtures : Hash(String, Fixture) = {} of String => Fixture,
                     @monsters : Hash(String, Monster) = {} of String => Monster,
                     @bands : Hash(String, Band) = {} of String => Band)
      end
    end

    # The stored form of this floor.
    def stored : Stored
      Stored.new @id, to_map, @litter, @glow, @ambient, @fixtures, @monsters, @bands
    end

    def self.new(pull : JSON::PullParser) : Floor
      held = Stored.new pull
      floor = parse held.id, held.map
      held.litter.each { |spot, pile| floor.litter[spot] = pile }
      held.glow.each { |spot, level| floor.glow[spot] = level }
      held.fixtures.each { |spot, fitting| floor.fixtures[spot] = fitting }
      held.bands.each { |id, band| floor.bands[id] = band }
      held.monsters.each { |spot, creature| floor.monsters[spot] = creature }
      floor.ambient = held.ambient

      floor
    end

    def to_json(json : JSON::Builder) : Nil
      stored.to_json json
    end

    def ==(other : Floor) : Bool
      @id == other.id && @columns == other.columns &&
        @rows == other.rows && @tiles == other.tiles &&
        @litter == other.litter && @glow == other.glow &&
        @ambient == other.ambient && @fixtures == other.fixtures &&
        @monsters == other.monsters && @bands == other.bands
    end

    def to_s(io : IO) : Nil
      io << "Floor(" << @id << ' ' << @columns << 'x' << @rows << ')'
    end
  end
end
