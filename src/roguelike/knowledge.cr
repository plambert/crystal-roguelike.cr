require "json"
require "./fixture"
require "./item"
require "./terrain"

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

    # What was lying on top of the pile, if anything. One item rather than the
    # pile, because one glyph is what a map draws.
    getter item : Item?

    # Which turn this was seen on.
    getter turn : Int32

    def initialize(@terrain : Terrain, @fixture : Fixture? = nil,
                   @item : Item? = nil, @turn : Int32 = 0)
    end

    # How many turns ago this was seen, as of *turn*.
    def age(turn : Int32) : Int32
      Math.max turn - @turn, 0
    end

    def ==(other : Memory) : Bool
      @terrain == other.terrain && @fixture == other.fixture &&
        @item == other.item && @turn == other.turn
    end

    def to_s(io : IO) : Nil
      io << "Memory(" << @terrain
      io << " +" << @fixture if @fixture
      io << " +" << @item if @item
      io << " turn " << @turn << ')'
    end
  end

  # Where somebody was last known to be.
  #
  # A monster that has seen the character remembers where, and how long ago.
  # It goes to that square rather than to where the character is now, which is
  # the difference between a creature that hunts and one that cheats.
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
    getter memories : Hash(String, Memory)

    # Where each creature was last seen, by who.
    #
    # `PLAYER` is the key for the character. A monster id will be the key for
    # a monster, once a band has a reason to track one.
    getter sightings : Hash(String, Sighting)

    def initialize(@floor : String,
                   @memories : Hash(String, Memory) = {} of String => Memory,
                   @sightings : Hash(String, Sighting) = {} of String => Sighting)
    end

    # The key `#sightings` holds the character under.
    PLAYER = "player"

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
      Knowledge.new @floor, @memories.dup, @sightings.dup
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

    # Whether what is remembered of *x*, *y* could be walked on.
    #
    # A square never seen answers false. A band does not walk through what it
    # has never looked at, which is what keeps it off a shortcut it has never
    # found. A door remembered as shut answers false as well, until somebody
    # looks at it again and finds it open.
    def walkable?(x : Int32, y : Int32) : Bool
      found = self[x, y]
      found ? found.terrain.passable? : false
    end

    # :ditto:
    def walkable?(spot : {Int32, Int32}) : Bool
      walkable? spot[0], spot[1]
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
    # Whatever was remembered before is replaced. A square looked at again
    # shows what is there now, not what was there before.
    def see(floor : Floor, x : Int32, y : Int32, turn : Int32 = 0) : Nil
      return unless floor.contains? x, y

      fitting = floor.fixture x, y
      pile = floor.items x, y

      @memories[Floor.spot x, y] = Memory.new floor.terrain(x, y),
        fitting.try(&.copy), pile.last?.try(&.copy), turn
    end

    # Records every square *vision* can see. This is the one way anything gets
    # in.
    def learn(floor : Floor, vision : Vision, turn : Int32 = 0) : Nil
      vision.each { |spot| see floor, spot[0], spot[1], turn }
    end

    # Yields every square that has been seen, with what was on it.
    def each(& : Int32, Int32, Memory ->) : Nil
      @memories.each do |spot, memory|
        parts = spot.split ','
        yield parts[0].to_i, parts[1].to_i, memory
      end
    end

    # Forgets everything.
    def forget : Nil
      @memories.clear
      @sightings.clear
    end

    # *floor* drawn as it is remembered, with *unknown* wherever it is not.
    #
    # For a spec and for reading a failure, the same way `Vision#to_map` is.
    def to_map(floor : Floor, unknown : Char = '?') : Array(String)
      Array.new(floor.rows) do |row|
        String.build(floor.columns) do |line|
          floor.columns.times do |column|
            memory = self[column, row]
            line << (memory ? memory.terrain.mark : unknown)
          end
        end
      end
    end

    def ==(other : Knowledge) : Bool
      @floor == other.floor && @memories == other.memories &&
        @sightings == other.sightings
    end

    def to_s(io : IO) : Nil
      io << "Knowledge(" << @floor << ' ' << @memories.size << " seen)"
    end
  end
end
