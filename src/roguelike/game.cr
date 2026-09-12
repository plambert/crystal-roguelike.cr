require "json"
require "./levels"
require "./player"
require "./world"

module Roguelike
  # What one step of a movement key did.
  enum Step
    # The character walked onto the square.
    Moved

    # The character opened a door and stayed where they were. Opening a door
    # takes a turn. A person cannot walk through a door in the same turn they
    # open it.
    Opened

    # Something is in the way. No turn was taken.
    Blocked

    # Whether a turn was taken.
    def turn? : Bool
      !blocked?
    end
  end

  # How a run ended.
  enum Outcome
    # The run is still going.
    Playing

    # The character reached the down staircase.
    Won

    # The character climbed back out.
    Left

    # Whether the run is over.
    def over? : Bool
      !playing?
    end
  end

  # Everything a run is. The only class that changes a run.
  #
  # A game holds the world, the character and the turn count. It opens no
  # device. It draws nothing. A spec plays a hundred turns with no widget
  # tree. A save file is one game written out.
  #
  # Every game rule lives here. `Session` reads the answer and draws it.
  # `Session` decides nothing.
  class Game
    include JSON::Serializable

    # Every level of the run, and the seed that made them.
    getter world : World

    # The character the person plays.
    getter player : Player

    # How many turns have been taken.
    #
    # A blocked step does not count. A turn gives every other creature on the
    # level one action. A blocked step gives them none.
    getter turn : Int32

    # How the run ended. `Playing` while it has not.
    getter outcome : Outcome

    def initialize(@world : World, @player : Player, @turn : Int32 = 0,
                   @outcome : Outcome = Outcome::Playing)
    end

    # Whether the run is over.
    def over? : Bool
      @outcome.over?
    end

    # A new run on *rng*.
    def self.start(rng : Rng) : Game
      world = World.on rng
      level = world.add Levels.proving_ground

      new world, Player.new(level.id, *entrance(level))
    end

    # Where a character arriving on *level* stands.
    #
    # The up staircase, when the level has one. A player enters a level by a
    # staircase. Any passable square otherwise.
    def self.entrance(level : Level) : {Int32, Int32}
      found = level.find Terrain::StairsUp
      return found if found

      level.each do |column, row, tile|
        return {column, row} if tile.passable?
      end

      raise ArgumentError.new "level #{level.id} has nowhere to stand"
    end

    # The level the character is on.
    def level : Level
      @world[@player.level]
    end

    # Takes one step *direction*. Answers what the step did.
    #
    # A step into a shut door opens it. The character stays where they are.
    # The turn counts. A person opens a door in one turn and walks through it
    # in the next.
    #
    # A step into any other impassable square moves nothing. It counts no
    # turn.
    def step(direction : Direction) : Step
      wanted = direction.from @player.x, @player.y

      if level.tile?(wanted[0], wanted[1]).try &.terrain.closed_door?
        level.set wanted[0], wanted[1], Terrain::OpenDoor
        @turn += 1
        return Step::Opened
      end

      return Step::Blocked unless level.passable? wanted[0], wanted[1]

      @player.move_to wanted
      @turn += 1
      Step::Moved
    end

    # Opens the door *direction*. Answers whether it opened.
    #
    # Opening takes a turn. Trying to open something that is not a shut door
    # takes none.
    def open(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return false unless level.tile?(wanted[0], wanted[1]).try &.terrain.closed_door?

      level.set wanted[0], wanted[1], Terrain::OpenDoor
      @turn += 1
      true
    end

    # Closes the door *direction*. Answers whether it closed.
    def close(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return false unless level.tile?(wanted[0], wanted[1]).try &.terrain.open_door?

      level.set wanted[0], wanted[1], Terrain::ClosedDoor
      @turn += 1
      true
    end

    # Every direction holding a door of *terrain*.
    #
    # `o` and `c` use this. One door needs no question. More than one does.
    def doors(terrain : Terrain) : Array(Direction)
      Direction.values.select do |direction|
        wanted = direction.from @player.x, @player.y
        level.tile?(wanted[0], wanted[1]).try(&.terrain) == terrain
      end
    end

    # What the character is standing on.
    def standing_on : Terrain
      level.terrain @player.x, @player.y
    end

    # Goes down the staircase the character stands on. Answers whether there
    # was one.
    #
    # There is one level, so down is out. The run ends as a win.
    def descend : Bool
      return false unless standing_on.stairs_down?

      @outcome = Outcome::Won
      true
    end

    # Goes up the staircase the character stands on. Answers whether there was
    # one.
    #
    # The character climbs out of the dungeon. The run ends without a win.
    def ascend : Bool
      return false unless standing_on.stairs_up?

      @outcome = Outcome::Left
      true
    end

    # What stops a step *direction*. Answers `nil` when nothing stops it.
    def blocking(direction : Direction) : Terrain?
      wanted = direction.from @player.x, @player.y
      found = level.tile? wanted[0], wanted[1]
      return unless found
      return if found.passable?

      found.terrain
    end

    def to_s(io : IO) : Nil
      io << "Game(turn=" << @turn << ", " << @outcome << ", " << @player << ')'
    end
  end
end
