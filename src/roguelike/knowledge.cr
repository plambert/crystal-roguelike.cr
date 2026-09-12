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

    def initialize(@floor : String,
                   @memories : Hash(String, Memory) = {} of String => Memory)
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
      @floor == other.floor && @memories == other.memories
    end

    def to_s(io : IO) : Nil
      io << "Knowledge(" << @floor << ' ' << @memories.size << " seen)"
    end
  end
end
