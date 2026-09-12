require "json"
require "./item"
require "./tile"

module Roguelike
  # One floor of the world.
  #
  # The world keeps a level after the player leaves it. A level keeps its
  # `#id` for as long as the world lasts.
  #
  # The id is what a run's randomness derives from. `rng.derive "worldgen",
  # level.id` uses it. So the id has to be the level's own name. A count of
  # how many levels exist would bring back an order dependency.
  #
  # A stored level holds its terrain as text. One string per row. The same
  # characters a level file uses. That form is compact. A person can read it.
  # `git diff` can show a change in it.
  #
  # No method here draws a level. `Ui::LevelCells` puts a level in front of a
  # `CellGrid`.
  class Level
    # What this level is called, for as long as the world lasts.
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
    # This getter is protected rather than private. `#==` compares two levels
    # through it. A private getter would force a copy of every square.
    protected getter tiles : Array(Tile)

    def initialize(@id : String, @columns : Int32, @rows : Int32, @tiles : Array(Tile),
                   @litter : Hash(String, Array(Item)) = {} of String => Array(Item))
      wanted = @columns * @rows
      return if @tiles.size == wanted

      raise ArgumentError.new "level #{@id} is #{@columns}x#{@rows} " \
                              "but holds #{@tiles.size} tiles, not #{wanted}"
    end

    # A level of nothing but *terrain*. A generator carves one of these.
    def self.solid(id : String, columns : Int32, rows : Int32,
                   terrain : Terrain = Terrain::Granite) : Level
      new id, columns, rows, Array.new(columns * rows) { Tile.new terrain }
    end

    # The level in *path*. The level takes its id from the file name.
    #
    # A level file holds nothing but the map. The file name is the only place
    # an id can come from. Renaming a level file makes a different level.
    def self.load(path : Path | String) : Level
      file = Path.new path

      parse File.basename(file.to_s, file.extension), File.read(file)
    end

    # The level *text* names. One row per line.
    #
    # A row shorter than the longest row fills out with rock. An editor that
    # trims trailing whitespace then cannot change a level.
    def self.parse(id : String, text : String) : Level
      parse id, text.lines.map(&.chomp)
    end

    # :ditto:
    def self.parse(id : String, lines : Array(String)) : Level
      rows = lines.reject(&.empty?)
      raise ArgumentError.new "level #{id} has no rows" if rows.empty?

      columns = rows.max_of &.size
      tiles = Array(Tile).new columns * rows.size

      rows.each do |line|
        columns.times do |column|
          mark = column < line.size ? line[column] : Terrains::FILL
          tiles << Tile.new(Terrain.from_mark(mark))
        end
      end

      new id, columns, rows.size, tiles
    end

    # The width and the height.
    def size : {Int32, Int32}
      {@columns, @rows}
    end

    # Whether *x*, *y* is on the level.
    def contains?(x : Int32, y : Int32) : Bool
      0 <= x < @columns && 0 <= y < @rows
    end

    # The square at *x*, *y*. The square has to be on the level.
    def tile(x : Int32, y : Int32) : Tile
      @tiles[index x, y]
    end

    # :ditto: Answers `nil` for a square off the level.
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

    # Whether a creature could walk onto *x*, *y*. A square off the level
    # answers false.
    def passable?(x : Int32, y : Int32) : Bool
      found = tile? x, y
      found ? found.passable? : false
    end

    # Whether a creature could see through *x*, *y*. A square off the level
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

    # Where the first square of *terrain* is. Answers `nil` when the level
    # has none.
    #
    # `Game.entrance` uses this to find a staircase.
    def find(terrain : Terrain) : {Int32, Int32}?
      each do |column, row, tile|
        return {column, row} if tile.terrain == terrain
      end

      nil
    end

    # The terrain as text. One string per row. A level file holds this form.
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
      @litter[Level.spot(x, y)]? || [] of Item
    end

    # Whether anything is lying on *x*, *y*.
    def items?(x : Int32, y : Int32) : Bool
      found = @litter[Level.spot(x, y)]?
      found ? !found.empty? : false
    end

    # Puts *item* on *x*, *y*.
    #
    # A stack joins one already there rather than making a second pile of the
    # same thing.
    def drop(x : Int32, y : Int32, item : Item) : Nil
      pile = @litter[Level.spot(x, y)] ||= [] of Item
      found = pile.index &.stacks_with?(item)

      if found
        pile[found] = pile[found].add item.count
      else
        pile << item
      end
    end

    # Takes *item* off *x*, *y*. Answers whether it was there.
    def take(x : Int32, y : Int32, item : Item) : Bool
      spot = Level.spot x, y
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
      @litter.delete(Level.spot(x, y)) || [] of Item
    end

    # Every square with something on it, and what is on it.
    def each_pile(& : Int32, Int32, Array(Item) ->) : Nil
      @litter.each do |spot, pile|
        next if pile.empty?

        parts = spot.split ','
        yield parts[0].to_i, parts[1].to_i, pile
      end
    end

    # What a level is in a save file.
    struct Stored
      include JSON::Serializable

      getter id : String
      getter map : Array(String)
      getter litter : Hash(String, Array(Item))

      def initialize(@id : String, @map : Array(String),
                     @litter : Hash(String, Array(Item)) = {} of String => Array(Item))
      end
    end

    # The stored form of this level.
    def stored : Stored
      Stored.new @id, to_map, @litter
    end

    def self.new(pull : JSON::PullParser) : Level
      held = Stored.new pull
      level = parse held.id, held.map
      held.litter.each { |spot, pile| level.litter[spot] = pile }

      level
    end

    def to_json(json : JSON::Builder) : Nil
      stored.to_json json
    end

    def ==(other : Level) : Bool
      @id == other.id && @columns == other.columns &&
        @rows == other.rows && @tiles == other.tiles && @litter == other.litter
    end

    def to_s(io : IO) : Nil
      io << "Level(" << @id << ' ' << @columns << 'x' << @rows << ')'
    end
  end
end
