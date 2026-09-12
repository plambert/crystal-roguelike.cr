require "json"
require "./equipment"
require "./floors"
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

    # Every floor of the run, and the seed that made them.
    getter world : World

    # The character the person plays.
    getter player : Player

    # How many turns have been taken.
    #
    # A blocked step does not count. A turn gives every other creature on the
    # floor one action. A blocked step gives them none.
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
      floor = world.add Floors.proving_ground

      game = new world, Player.new(floor.id, *entrance(floor)), lore: Lore.roll(rng)
      game.scatter rng
      game.say "You are in a dungeon. Press ? for the keys."
      game
    end

    # How many items a floor starts with, until there is a generator.
    LITTER = 24

    # How much gold one pile holds, until there is a generator.
    PURSE = 5..40

    # Puts items about the floor on *rng*.
    #
    # Placement is its own stream, so the loot does not shift when anything
    # else changes how much it rolls.
    def scatter(rng : Rng) : Nil
      stream = rng.derive "litter:#{floor.id}"
      squares = [] of {Int32, Int32}
      floor.each { |column, row, tile| squares << {column, row} if tile.terrain.floor? }
      return if squares.empty?

      LITTER.times do
        spot = squares.sample stream
        item = stream.rand(4).zero? ? gold(stream) : Items.random(stream)
        floor.drop spot[0], spot[1], item
      end
    end

    # One pile of gold.
    private def gold(rng : Rng) : Item
      Item.new ItemKind::Gold, count: rng.rand(PURSE)
    end

    # Where a character arriving on *floor* stands.
    #
    # The up staircase, when the floor has one. A player enters a floor by a
    # staircase. Any passable square otherwise.
    def self.entrance(floor : Floor) : {Int32, Int32}
      found = floor.find Terrain::StairsUp
      return found if found

      floor.each do |column, row, tile|
        return {column, row} if tile.passable?
      end

      raise ArgumentError.new "floor #{floor.id} has nowhere to stand"
    end

    # The floor the character is on.
    def floor : Floor
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

      if floor.tile?(wanted[0], wanted[1]).try &.terrain.closed_door?
        floor.set wanted[0], wanted[1], Terrain::OpenDoor
        @turn += 1
        say "You open the door."
        return Step::Opened
      end

      unless floor.passable? wanted[0], wanted[1]
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
      return false unless floor.tile?(wanted[0], wanted[1]).try &.terrain.closed_door?

      floor.set wanted[0], wanted[1], Terrain::OpenDoor
      @turn += 1
      say "You open the door."
      true
    end

    # Closes the door *direction*. Answers whether it closed.
    def close(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return false unless floor.tile?(wanted[0], wanted[1]).try &.terrain.open_door?

      floor.set wanted[0], wanted[1], Terrain::ClosedDoor
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
        floor.tile?(wanted[0], wanted[1]).try(&.terrain) == terrain
      end
    end

    # What the character is standing on.
    def standing_on : Terrain
      floor.terrain @player.x, @player.y
    end

    # Goes down the staircase the character stands on. Answers whether there
    # was one.
    #
    # There is one floor, so down is out. The run ends as a win.
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
      floor.items @player.x, @player.y
    end

    # Picks *item* up off the square the character stands on.
    #
    # Gold is counted rather than carried. It takes no letter and never fills
    # the inventory.
    #
    # Answers whether the character now has it. A full inventory answers false
    # and leaves the item where it was.
    def pick_up(item : Item) : Bool
      return false unless floor.take @player.x, @player.y, item

      if item.kind.item_class.treasure?
        @player.take_gold item.count
        @turn += 1
        say "You pick up #{item.count} gold pieces."
        return true
      end

      letter = @player.inventory.add item
      unless letter
        floor.drop @player.x, @player.y, item
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

      slot = slot_of letter
      if slot
        say "You have to take #{name item} off first."
        return false
      end

      @player.inventory.remove letter
      @player.equipment.clean @player.inventory
      floor.drop @player.x, @player.y, item
      @turn += 1
      say "You drop #{name item}."
      true
    end

    # Puts *amount* gold pieces on the floor. Answers how many went.
    def drop_gold(amount : Int32) : Int32
      dropped = @player.spend_gold amount
      return 0 if dropped.zero?

      floor.drop @player.x, @player.y, Item.new(ItemKind::Gold, count: dropped)
      @turn += 1
      say "You drop #{dropped} gold pieces."
      dropped
    end

    # ------------------------------------------------------------ equipment

    # Readies what is under *letter*. Answers whether it went into a slot.
    #
    # One key readies anything that is readied at all. `Slot.for` picks the
    # slot from what the item is. A sword goes in the hand, a bow goes in the
    # other hand, and arrows go in the quiver.
    #
    # Armour is not readied this way. `#wear` puts armour on, because putting
    # armour on is a different act from picking a weapon up.
    def wield(letter : Char) : Bool
      item = @player.inventory[letter]
      return false unless item

      slot = Slot.for item
      if slot.nil? || slot.armour?
        say "You cannot wield #{name item}."
        return false
      end

      ready slot, letter, item, "You are now holding #{name item}."
    end

    # Puts on what is under *letter*. Answers whether it went on.
    #
    # A slot already filled refuses. A person takes one thing off before they
    # put another on, and saying so is clearer than doing it for them.
    def wear(letter : Char) : Bool
      item = @player.inventory[letter]
      return false unless item

      slot = Slot.for item
      unless slot && slot.armour?
        say "You cannot wear #{name item}."
        return false
      end

      held = @player.in_slot slot
      if held
        say "You are already wearing #{name held}."
        return false
      end

      ready slot, letter, item, "You are now wearing #{name item}."
    end

    # Puts *letter* in *slot* and says *line*. Always answers true.
    #
    # A cursed item announces itself as it goes on. That is the moment the
    # character finds out, and `#take_off` will refuse to let it go again.
    private def ready(slot : Slot, letter : Char, item : Item, line : String) : Bool
      @player.equipment.put slot, letter
      @turn += 1
      say line

      if item.sticks? && item.reveal_blessing
        say "#{name(item).capitalize} welds itself to you."
      end

      true
    end

    # Takes whatever is in *slot* off. Answers whether it came off.
    def take_off(slot : Slot) : Bool
      item = @player.in_slot slot
      unless item
        say "You have nothing #{slot.armour? ? "on your" : "in your"} #{slot.label}."
        return false
      end

      if item.sticks?
        item.reveal_blessing
        say "You cannot let go of #{name item}."
        return false
      end

      @player.equipment.clear slot
      @turn += 1
      say "You are no longer #{slot.armour? ? "wearing" : "holding"} #{name item}."
      true
    end

    # Every filled slot, in the order `Slot` names them.
    def readied : Array({Slot, Item})
      found = [] of {Slot, Item}

      @player.equipment.each do |slot, letter|
        item = @player.inventory[letter]
        found << {slot, item} if item
      end

      found
    end

    # Which slot holds what is under *letter*. `nil` when no slot does.
    def slot_of(letter : Char) : Slot?
      @player.equipment.slot_of letter
    end

    # ------------------------------------------------------------- movement

    # What stops a step *direction*. Answers `nil` when nothing stops it.
    def blocking(direction : Direction) : Terrain?
      wanted = direction.from @player.x, @player.y
      found = floor.tile? wanted[0], wanted[1]
      return unless found
      return if found.passable?

      found.terrain
    end

    def to_s(io : IO) : Nil
      io << "Game(turn=" << @turn << ", " << @outcome << ", " << @player << ')'
    end
  end
end
