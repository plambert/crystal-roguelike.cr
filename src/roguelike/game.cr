require "json"
require "./levels"
require "./items"
require "./lore"
require "./message_log"
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
  # Every game rule is in this class. `Session` reads the answer and draws it.
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

    # What has just happened.
    getter log : MessageLog

    # What this run's items look like, and which of them the character has
    # found out.
    getter lore : Lore

    def initialize(@world : World, @player : Player, @turn : Int32 = 0,
                   @outcome : Outcome = Outcome::Playing,
                   @log : MessageLog = MessageLog.new,
                   @lore : Lore = Lore.new)
    end

    # What *item* is called, as this character would call it.
    def name(item : Item) : String
      @lore.name item
    end

    # Adds *line* to the log.
    def say(line : String) : Nil
      @log.add line
    end

    # Whether the run is over.
    def over? : Bool
      @outcome.over?
    end

    # A new run on *rng*.
    def self.start(rng : Rng) : Game
      world = World.on rng
      level = world.add Levels.proving_ground

      game = new world, Player.new(level.id, *entrance(level)), lore: Lore.roll(rng)
      game.scatter rng
      game.say "You are in a dungeon. Press ? for the keys."
      game
    end

    # How many items a level starts with, until there is a generator.
    LITTER = 24

    # How much gold one pile holds, until there is a generator.
    PURSE = 5..40

    # Puts items about the level on *rng*.
    #
    # Placement is its own stream, so the loot does not shift when anything
    # else changes how much it rolls.
    def scatter(rng : Rng) : Nil
      stream = rng.derive "litter:#{level.id}"
      floors = [] of {Int32, Int32}
      level.each { |column, row, tile| floors << {column, row} if tile.terrain.floor? }
      return if floors.empty?

      LITTER.times do
        spot = floors.sample stream
        item = stream.rand(4).zero? ? gold(stream) : Items.random(stream)
        level.drop spot[0], spot[1], item
      end
    end

    # One pile of gold.
    private def gold(rng : Rng) : Item
      Item.new ItemKind::Gold, count: rng.rand(PURSE)
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
      @world[@player.floor]
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
        say "You open the door."
        return Step::Opened
      end

      unless level.passable? wanted[0], wanted[1]
        say blocked_by direction
        return Step::Blocked
      end

      @player.move_to wanted
      @turn += 1
      arrived
      Step::Moved
    end

    # What to say about a step that did not happen.
    private def blocked_by(direction : Direction) : String
      stopped = blocking direction
      return "You cannot go that way." unless stopped

      "The #{stopped.label} blocks your way."
    end

    # Says what the character has walked onto, when it is worth saying.
    private def arrived : Nil
      ground = standing_on
      say "There is #{ground.description} here." if ground.stairs?

      pile = here
      return if pile.empty?

      if pile.size == 1
        say "You see #{name pile.first} here."
      else
        say "There are #{pile.size} things here."
      end
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
      say "You open the door."
      true
    end

    # Closes the door *direction*. Answers whether it closed.
    def close(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return false unless level.tile?(wanted[0], wanted[1]).try &.terrain.open_door?

      level.set wanted[0], wanted[1], Terrain::ClosedDoor
      @turn += 1
      say "You close the door."
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

    # ---------------------------------------------------------------- items

    # What is lying on the square the character stands on.
    def here : Array(Item)
      level.items @player.x, @player.y
    end

    # Picks *item* up off the square the character stands on.
    #
    # Gold is counted rather than carried. It takes no letter and never fills
    # the inventory.
    #
    # Answers whether the character now has it. A full inventory answers false
    # and leaves the item where it was.
    def pick_up(item : Item) : Bool
      return false unless level.take @player.x, @player.y, item

      if item.kind.item_class.treasure?
        @player.take_gold item.count
        @turn += 1
        say "You pick up #{item.count} gold pieces."
        return true
      end

      letter = @player.inventory.add item
      unless letter
        level.drop @player.x, @player.y, item
        say "You cannot carry any more."
        return false
      end

      @turn += 1
      say "#{letter} - #{name item}"
      true
    end

    # Picks up everything on the square. Answers how many entries were taken.
    def pick_up_all : Int32
      taken = 0
      here.dup.each { |item| taken += 1 if pick_up item }
      taken
    end

    # Puts what is under *letter* on the floor. Answers whether it went.
    def drop(letter : Char) : Bool
      item = @player.inventory[letter]
      return false unless item

      if item.sticks? && item.blessing_known?
        say "You cannot let go of #{name item}."
        return false
      end

      @player.inventory.remove letter
      level.drop @player.x, @player.y, item
      @turn += 1
      say "You drop #{name item}."
      true
    end

    # Puts *amount* gold pieces on the floor. Answers how many went.
    def drop_gold(amount : Int32) : Int32
      dropped = @player.spend_gold amount
      return 0 if dropped.zero?

      level.drop @player.x, @player.y, Item.new(ItemKind::Gold, count: dropped)
      @turn += 1
      say "You drop #{dropped} gold pieces."
      dropped
    end

    # ------------------------------------------------------------- movement

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
