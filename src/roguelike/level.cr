require "json"
require "./tile"

module Roguelike
  # One floor of the world.
  #
  # Levels are not thrown away when they are left. A level keeps its `#id` for
  # as long as the world does, and that id is what a run's randomness is
  # derived from — `rng.derive "worldgen", level.id` — so it has to be the
  # level's own name and never a count of how many have been made, or the
  # order they were made in comes back as a dependency.
  #
  # The stored form is the terrain as text, one string per row, in the same
  # characters a level file uses. That is the compact form, the readable form
  # and the form `git diff` can show, all at once.
  #
  # Nothing here knows what anything looks like. `Ui::LevelCells` is what puts
  # a level in front of a `CellGrid`.
  class Level
    # What this level is called, for as long as the world lasts.
    getter id : String

    # Cells across.
    getter columns : Int32

    # Cells down.
    getter rows : Int32

    # Row-major, `y * columns + x`. Protected rather than private so that two
    # levels can be compared without going through a copy of every square.
    protected getter tiles : Array(Tile)

    def initialize(@id : String, @columns : Int32, @rows : Int32, @tiles : Array(Tile))
      wanted = @columns * @rows
      return if @tiles.size == wanted

      raise ArgumentError.new "level #{@id} is #{@columns}x#{@rows} " \
                              "but holds #{@tiles.size} tiles, not #{wanted}"
    end

    # A level of nothing but *terrain*, for a generator to carve.
    def self.solid(id : String, columns : Int32, rows : Int32,
                   terrain : Terrain = Terrain::Granite) : Level
      new id, columns, rows, Array.new(columns * rows) { Tile.new terrain }
    end

    # The level in *path*, named after the file.
    #
    # A file holds nothing but the map, so the name is the only place an id
    # can come from, and a level renamed on disk is a different level.
    def self.load(path : Path | String) : Level
      file = Path.new path

      parse File.basename(file.to_s, file.extension), File.read(file)
    end

    # The level *text* names, one row per line.
    #
    # Rows shorter than the longest are filled out with rock, so an editor
    # that trims trailing whitespace cannot change what a level is.
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

    # Both extents at once.
    def size : {Int32, Int32}
      {@columns, @rows}
    end

    # Whether *x*, *y* is on the level at all.
    def contains?(x : Int32, y : Int32) : Bool
      0 <= x < @columns && 0 <= y < @rows
    end

    # The square at *x*, *y*, which has to be on the level.
    def tile(x : Int32, y : Int32) : Tile
      @tiles[index x, y]
    end

    # :ditto:, answering `nil` for a square that is not.
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

    # Makes the square at *x*, *y* out of *terrain*, which is what opening a
    # door is.
    def set(x : Int32, y : Int32, terrain : Terrain) : Nil
      set x, y, tile(x, y).with_terrain(terrain)
    end

    # Whether something could walk onto *x*, *y*. Off the level is not.
    def passable?(x : Int32, y : Int32) : Bool
      found = tile? x, y
      found ? found.passable? : false
    end

    # Whether something could see through *x*, *y*. Off the level is not.
    def blocks_sight?(x : Int32, y : Int32) : Bool
      found = tile? x, y
      found ? found.blocks_sight? : true
    end

    # Yields every square, in reading order.
    def each(& : Int32, Int32, Tile ->) : Nil
      @rows.times do |row|
        @columns.times { |column| yield column, row, @tiles[index column, row] }
      end
    end

    # Where the first square of *terrain* is, or `nil` when there is none.
    #
    # What finds the staircase a level was entered by.
    def find(terrain : Terrain) : {Int32, Int32}?
      each do |column, row, tile|
        return {column, row} if tile.terrain == terrain
      end

      nil
    end

    # The terrain as text, one string per row, which is the form a level file
    # holds and the form a save file holds.
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

    # What a level is in a save file.
    struct Stored
      include JSON::Serializable

      getter id : String
      getter map : Array(String)

      def initialize(@id : String, @map : Array(String))
      end
    end

    # The stored form of this level.
    def stored : Stored
      Stored.new @id, to_map
    end

    def self.new(pull : JSON::PullParser) : Level
      held = Stored.new pull

      parse held.id, held.map
    end

    def to_json(json : JSON::Builder) : Nil
      stored.to_json json
    end

    def ==(other : Level) : Bool
      @id == other.id && @columns == other.columns &&
        @rows == other.rows && @tiles == other.tiles
    end

    def to_s(io : IO) : Nil
      io << "Level(" << @id << ' ' << @columns << 'x' << @rows << ')'
    end
  end
end
