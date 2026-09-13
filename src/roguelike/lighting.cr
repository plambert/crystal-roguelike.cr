require "./direction"
require "./field_of_view"
require "./floor"

module Roguelike
  # What sort of light a source throws.
  #
  # No member here carries a colour. `Ui::Palette` holds the colours, the
  # same way it holds the glyph for a terrain. A theme changes that table. A
  # spec reads a light with no terminal open.
  enum LightKind
    # A burning wick. A torch, a candle and a wall sconce all throw this.
    Flame

    # A light with nothing burning. A magically lit room throws this.
    Glimmer
  end

  # One thing that throws light.
  #
  # A lit wall sconce is one. A lit torch or candle is one, whether it is
  # carried or lying on the floor. A source is worked out from the floor and
  # the character each turn rather than stored, so nothing has to keep a list
  # of them in step with what is on the map.
  record LightSource,
    x : Int32,
    y : Int32,
    radius : Int32,
    kind : LightKind = LightKind::Flame,
    facing : Direction? = nil do
    # Where this source stands.
    def at : {Int32, Int32}
      {x, y}
    end

    # Whether this source throws light onto *x*, *y* at all.
    #
    # A source with no `#facing` throws light every way. One bolted to a wall
    # throws it away from that wall: half the compass, plus the eight squares
    # touching the bracket, which includes the wall it is bolted to.
    def throws_on?(x : Int32, y : Int32) : Bool
      wall = facing
      return true unless wall

      across = x - self.x
      down = y - self.y
      return true if across.abs <= 1 && down.abs <= 1

      across * wall.dx + down * wall.dy <= 0
    end
  end

  # How much light reaches each square of a floor.
  #
  # Light is accumulated rather than replaced. Two torches in one room make a
  # brighter room than one, and a square reached by nothing is dark.
  #
  # Each source lights what it can see, which is its own field of view cut to
  # its radius. Light does not go round a corner, so a torch in a corridor
  # does not light the room behind the wall.
  #
  # A source bolted to a wall throws light away from that wall rather than
  # all around. `LightSource#throws_on?` is that half.
  #
  # This is derived rather than stored. It is worked out again whenever
  # anything that throws light moves or goes out.
  class Lighting
    # How much light each square has beyond the floor's own.
    #
    # A square with none holds no entry. `#level` answers the ambient for it.
    getter levels : Hash({Int32, Int32}, Int32)

    # How much light every square has whatever else happens. `Floor#ambient`
    # is where this comes from.
    getter ambient : Int32

    # What sort of light is on each square: the kind of whichever source
    # throws the most light on it.
    #
    # A square lit by a torch and by a magically lit room at once takes the
    # one throwing more. What the square is drawn in follows from this, and so
    # does whether it wavers.
    getter kinds : Hash({Int32, Int32}, LightKind)

    # The strongest single contribution each square has taken, for deciding
    # which source wins `#kinds`.
    @best = {} of {Int32, Int32} => Int32

    # Where the flames reaching each square are standing.
    #
    # Only flames, because only a flame wavers. Two pools overlapping put two
    # entries on the squares they share, so what is drawn there moves by what
    # both flames are doing rather than by what one of them is.
    #
    # This says nothing about how much light a square has. `#level` is the
    # light, and no flame changes it.
    getter flames : Hash({Int32, Int32}, Array({Int32, Int32}))

    def initialize(@levels : Hash({Int32, Int32}, Int32) = {} of {Int32, Int32} => Int32,
                   @ambient : Int32 = 0,
                   @kinds : Hash({Int32, Int32}, LightKind) = {} of {Int32, Int32} => LightKind,
                   @flames : Hash({Int32, Int32}, Array({Int32, Int32})) = {} of {Int32, Int32} => Array({Int32, Int32}))
    end

    # No flame at all. What `#flames_at` answers for a square none reaches.
    NO_FLAMES = [] of {Int32, Int32}

    # Where the flames reaching *x*, *y* are standing.
    def flames_at(x : Int32, y : Int32) : Array({Int32, Int32})
      @flames[{x, y}]? || NO_FLAMES
    end

    # The light over *floor* from *sources*, plus whatever the floor glows on
    # its own.
    def self.over(floor : Floor, sources : Enumerable(LightSource)) : Lighting
      lighting = new ambient: floor.ambient
      floor.each_glow { |column, row, level| lighting.spill floor, column, row, level }
      sources.each { |source| lighting.pour floor, source }
      lighting
    end

    # How much light *x*, *y* has.
    def level(x : Int32, y : Int32) : Int32
      @ambient + (@levels[{x, y}]? || 0)
    end

    # What sort of light is on *x*, *y*. `nil` for a square with none.
    #
    # A square lit only by the floor's own ambient level takes `Glimmer`. A
    # floor lit throughout is lit by something, and nothing about it wavers.
    def kind_at(x : Int32, y : Int32) : LightKind?
      found = @kinds[{x, y}]?
      return found if found
      return LightKind::Glimmer if @ambient > 0

      nil
    end

    # Whether *x*, *y* has any light on it at all.
    def lit?(x : Int32, y : Int32) : Bool
      level(x, y) > 0
    end

    # :ditto:
    def lit?(spot : {Int32, Int32}) : Bool
      lit? spot[0], spot[1]
    end

    # How many squares have light on them beyond the floor's own.
    def size : Int32
      @levels.size
    end

    # Adds *amount* of *kind* to what *x*, *y* has.
    #
    # The kind is recorded when this is the strongest single contribution the
    # square has taken. A torch beside a magically lit room then leaves the
    # squares nearest it reading as firelight and the rest as the room's.
    protected def add(x : Int32, y : Int32, amount : Int32,
                      kind : LightKind = LightKind::Glimmer) : Nil
      return if amount <= 0

      spot = {x, y}
      @levels[spot] = (@levels[spot]? || 0) + amount

      return unless amount > (@best[spot]? || 0)

      @best[spot] = amount
      @kinds[spot] = kind
    end

    # Adds the glow of *x*, *y* there and on the squares around it.
    #
    # A room lights its own walls and its own doors. Standing in a lit room,
    # a person sees where the room ends. A glow that stopped at the floor
    # would leave the walls dark and the room with no edge to it, and a door
    # in the middle of a dark wall could not be found.
    #
    # The spill reaches one square. It does not reach past a wall into the
    # corridor behind it.
    protected def spill(floor : Floor, x : Int32, y : Int32, level : Int32) : Nil
      add x, y, level, LightKind::Glimmer

      Direction.values.each do |direction|
        spot = direction.from x, y
        next unless floor.contains? spot[0], spot[1]

        add spot[0], spot[1], level, LightKind::Glimmer
      end
    end

    # Adds what *source* throws over *floor*.
    #
    # The light falls off with distance: a square next to the flame gets the
    # whole radius, and a square at the edge of the reach gets one. Straight
    # line distance, so the pool is round.
    protected def pour(floor : Floor, source : LightSource) : Nil
      return if source.radius <= 0

      FieldOfView.from(floor, source.at, source.radius).each do |spot|
        next unless source.throws_on? spot[0], spot[1]

        across = spot[0] - source.x
        down = spot[1] - source.y
        away = Math.sqrt(across * across + down * down).round.to_i

        add spot[0], spot[1], Math.max(source.radius - away + 1, 1), source.kind
        next unless source.kind.flame?

        (@flames[spot] ||= [] of {Int32, Int32}) << source.at
      end
    end

    # *floor* drawn with *dark* wherever no light reaches.
    #
    # For a spec and for reading a failure, the same way
    # `FieldOfView#to_map` is.
    def to_map(floor : Floor, dark : Char = '?') : Array(String)
      Array.new(floor.rows) do |row|
        String.build(floor.columns) do |line|
          floor.columns.times do |column|
            line << (lit?(column, row) ? floor.terrain(column, row).mark : dark)
          end
        end
      end
    end

    # How much light each square has, as digits. A square with more than nine
    # is written `9`.
    def to_levels(floor : Floor, dark : Char = '.') : Array(String)
      Array.new(floor.rows) do |row|
        String.build(floor.columns) do |line|
          floor.columns.times do |column|
            here = level column, row
            line << (here > 0 ? Math.min(here, 9).to_s[0] : dark)
          end
        end
      end
    end

    def to_s(io : IO) : Nil
      io << "Lighting(" << @levels.size << " lit)"
    end
  end
end
