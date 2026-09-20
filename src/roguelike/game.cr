require "json"
require "./apply"
require "./combat"
require "./effect"
require "./equipment"
require "./field_of_view"
require "./flight"
require "./floors"
require "./generator"
require "./lighting"
require "./line"
require "./vision"
require "./items"
require "./loot"
require "./lore"
require "./message_log"
require "./notice"
require "./pursuit"
require "./running"
require "./player"
require "./world"

module Roguelike
  # What one step of a movement key did.
  enum Step
    # The character walked onto the square.
    Moved

    # The character swung at whatever was standing there. A step into a
    # creature is an attack on it. The character stays where they were,
    # whether the swing landed or not.
    Struck

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

    # The character was killed.
    Died

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
  # Every game rule is in this class. `Session` reads what it did and draws
  # that. `Session` decides nothing.
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

    # How many swings have been rolled in this run.
    #
    # This names the generator for the next one. See `#exchange`.
    getter blows : Int32

    # How many items have been used in this run.
    #
    # The same idea as `#blows`, on its own stream. A potion drunk mid-fight
    # must not shift the swings that follow it.
    getter uses : Int32

    # How many times a creature has been asked whether it puts a foot wrong.
    #
    # The same idea again, on a third stream. A creature blundering must not
    # shift the numbers the next swing draws.
    #
    # It has a default, so a save written before this counter existed loads
    # and carries on from zero.
    getter wanders : Int32 = 0

    # How many turns have asked what the character has noticed about what
    # they carry.
    #
    # A fourth stream, so learning that a sword is cursed does not shift what
    # the next swing rolls. It has a default, so a save written before this
    # counter existed loads and carries on from zero.
    getter handled : Int32 = 0

    # What has just happened.
    getter log : MessageLog

    # What this run's items look like, and which of them the character has
    # found out.
    getter lore : Lore

    # What killed the character. `nil` while they are alive.
    #
    # The label rather than the creature. The end screen names what killed
    # them, and a creature held here would be a second copy of one the floor
    # already holds.
    getter killer : String? = nil

    # The run's root generator, built from the world's seed.
    #
    # This is not written out. `World#seed` is, and this is a function of it.
    @[JSON::Field(ignore: true)]
    @root : Rng? = nil

    def initialize(@world : World, @player : Player, @turn : Int32 = 0,
                   @outcome : Outcome = Outcome::Playing,
                   @log : MessageLog = MessageLog.new,
                   @lore : Lore = Lore.new,
                   @blows : Int32 = 0,
                   @uses : Int32 = 0,
                   @wanders : Int32 = 0)
    end

    # What *item* is called, as this character would call it.
    def name(item : Item) : String
      @lore.name item
    end

    # What everything under *letter* is called, counted together.
    #
    # A letter holding twelve arrows and three more that differ only in a
    # hidden curse is "15 arrows". The character cannot tell them apart, so
    # neither does the line that names them.
    def name_under(letter : Char) : String
      item = @player.inventory[letter]
      return "nothing" unless item

      @lore.name item.with_count(@player.inventory.count letter)
    end

    # Adds *line* to the log.
    def say(line : String) : Nil
      @log.add line
    end

    # Whether the run is over.
    def over? : Bool
      @outcome.over?
    end

    # A new run on *rng*, played on *ground*.
    #
    # The character starts with a lit torch. A dungeon is dark, and a person
    # who arrived with no light would see one square and nothing else.
    #
    # *ground* is the floor that ships with the game unless a caller names
    # another. `Game.dug` is the one the generator digs, which is what the
    # game itself plays.
    def self.start(rng : Rng, ground : Floor = Floors.proving_ground) : Game
      world = World.on rng
      floor = world.add ground

      player = Player.new floor.id, *entrance(floor)
      outfit player

      game = new world, player, lore: Lore.roll(rng)
      game.scatter rng
      game.equip rng
      # Two lines rather than one. The log pane is four rows of about eighty
      # columns, and one sentence saying all of this wraps onto two of them.
      game.say "You are in a dungeon with a short sword, leather armour and a lit torch."
      game.say "You carry three iron spikes. Press ? for the keys."
      game
    end

    # How many spikes the character starts with.
    SPIKES = 3

    # What the character starts with, readied.
    #
    # A short sword and leather armour. Bare hands are 1d2 against a goblin's
    # armour, which is a fight a character at level one cannot win, and a
    # character who cannot win the commonest fight cannot reach level two
    # either. The torch is here because a dungeon is dark and somebody who
    # arrived without a light would see one square.
    #
    # The spikes are here because a floor hands them out rarely. A person who
    # had to find one before learning what it is for would mostly never find
    # one.
    #
    # The slots are filled rather than wielded. `#wield` and `#wear` each
    # spend a turn and write to the log, and neither has happened yet.
    private def self.outfit(player : Player) : Nil
      {
        {Item.new(ItemKind::ShortSword), Slot::Melee},
        {Item.new(ItemKind::LeatherArmour), Slot::Body},
      }.each do |item, slot|
        letter = player.inventory.add item
        player.equipment.put slot, letter if letter
      end

      player.inventory.add Item.new(ItemKind::Torch, lit: true)
      player.inventory.add Item.new(ItemKind::Spike, count: SPIKES)
    end

    # A new run on *rng*, played on a floor dug from the same seed.
    #
    # `--seed N` twice digs the same floor, because `Generator` derives every
    # roll from the seed and from nothing else.
    def self.dug(rng : Rng) : Game
      start rng, Generator.floor(rng)
    end

    # How many items a floor starts with, per hundred squares of open floor.
    #
    # A rate rather than a count. A floor nine times the area then holds nine
    # times as much, so how far a person walks between two things they can
    # pick up does not change with the size of the floor.
    LITTER = 3

    # How much gold one pile holds.
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

      (squares.size * LITTER // 100).times do
        spot = squares.sample stream
        item = stream.rand(4).zero? ? gold(stream) : Items.random(stream)
        floor.drop spot[0], spot[1], item
        supply rng, spot, item
      end
    end

    # How often a ranged weapon lands with ammunition for it nearby.
    QUIVERED = 85

    # How far from the ranged weapon that ammunition lands.
    NEARBY = 3

    # How many stacks of it land.
    SUPPLY = 1..2

    # Puts ammunition for *weapon* on or near *spot*.
    #
    # A bow with no ammunition anywhere on the floor cannot be fired.
    #
    # This rolls on a stream named by the square rather than on the litter's
    # own. The litter then falls where it always fell, and a floor from an
    # old seed gains arrows without moving anything else.
    private def supply(rng : Rng, spot : {Int32, Int32}, weapon : Item) : Nil
      kind = weapon.kind.ammunition
      return unless kind

      stream = rng.derive "ammunition:#{floor.id}:#{spot[0]},#{spot[1]}"
      return unless stream.rand(100) < QUIVERED

      stream.rand(SUPPLY).times do
        where = near stream, spot
        floor.drop where[0], where[1], Items.make(stream, kind)
      end
    end

    # A floor square within `NEARBY` of *spot*, or *spot* itself.
    #
    # The square the ranged weapon is on counts, so the ammunition may land
    # on top of it.
    private def near(rng : Rng, spot : {Int32, Int32}) : {Int32, Int32}
      found = [] of {Int32, Int32}

      ((spot[1] - NEARBY)..(spot[1] + NEARBY)).each do |row|
        ((spot[0] - NEARBY)..(spot[0] + NEARBY)).each do |column|
          next unless floor.contains? column, row
          next unless floor.terrain(column, row).floor?

          found << {column, row}
        end
      end

      found.empty? ? spot : found.sample(rng)
    end

    # Gives every monster on the floor what it is carrying.
    #
    # Each creature draws on a stream of its own, named by where it stands.
    # That is its stable identity on a floor written by hand: adding an entry
    # to a loot table shifts what one creature carries and nothing else, and
    # the order the creatures are walked in does not matter at all.
    def equip(rng : Rng) : Nil
      floor.each_monster do |column, row, creature|
        stream = rng.derive "loot:#{floor.id}:#{column},#{row}"
        creature.carry Loot.for(creature.species, stream)
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

      blocking_creature = floor.monster wanted[0], wanted[1]
      if blocking_creature
        attack blocking_creature
        return Step::Struck
      end

      if floor.tile?(wanted[0], wanted[1]).try &.terrain.closed_door?
        floor.set wanted[0], wanted[1], Terrain::OpenDoor
        handled wanted
        say "You open the door."
        spend_turn
        return Step::Opened
      end

      unless floor.passable? wanted[0], wanted[1]
        say blocked_by direction
        return Step::Blocked
      end

      @player.move_to wanted
      arrived
      spend_turn
      Step::Moved
    end

    # Passes the turn. `.` does this.
    #
    # The character does nothing. Everything else on the floor acts, the same
    # way it does after a step, so waiting is how a person lets something
    # come to them rather than walking into it.
    #
    # A run that is over takes no turn. Nothing acts after the character has
    # died, and a person reading the ending screen is not playing.
    def wait : Nil
      return if over?

      spend_turn
    end

    # ------------------------------------------------------------- running

    # How many squares one run crosses before it stops on its own.
    #
    # A run moves in one direction, so it reaches the edge of any floor well
    # inside this. The number is here so that a bug elsewhere cannot leave a
    # run turning the crank forever.
    FURTHEST = 60

    # Walks *direction* until something is worth stopping for. Answers how
    # far it went and what stopped it.
    #
    # Every step is a whole turn, so every other creature on the floor acts
    # between one step and the next, and a run is as dangerous as walking the
    # same squares one key at a time.
    #
    # A run never attacks and never opens a door. Either one is a decision,
    # and a run makes none: it stops in front of a creature or a shut door
    # and leaves the decision to the person.
    #
    # A run that takes no step at all says why, the way one press of the
    # movement key against the same square would.
    def run(direction : Direction) : Running
      steps = 0
      along = corridor? @player.at
      seen = sight

      while steps < FURTHEST
        if blocked_ahead? direction
          refuse_run direction if steps.zero?
          return Running.new steps, Halt::Blocked
        end

        before = Watch.on self, seen
        return Running.new steps, Halt::Blocked unless step(direction).moved?

        steps += 1
        seen = sight
        halt = stopped_by before, along, seen
        along = corridor? @player.at

        return Running.new steps, halt if halt
      end

      Running.new steps, Halt::Spent
    end

    # Says why a run went nowhere.
    #
    # A creature in the way is named when the character can see it. One they
    # cannot see is not: they have walked into something and do not know
    # what. Anything else is the sentence a plain step writes.
    private def refuse_run(direction : Direction) : Nil
      wanted = direction.from @player.x, @player.y
      creature = floor.monster wanted[0], wanted[1]
      return say blocked_by direction unless creature

      unless can_see_creature? wanted[0], wanted[1]
        return say "There is something in the way."
      end

      say "The #{creature.label} is in the way."
    end

    # Whether the square one step *direction* stops a run.
    #
    # A creature standing there, or anything a character cannot walk onto. A
    # shut door is one of those, so a run stops in front of it rather than
    # opening it.
    private def blocked_ahead?(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return true if floor.monster wanted[0], wanted[1]

      !floor.passable? wanted[0], wanted[1]
    end

    # What a run has to compare against to know whether a step changed
    # anything.
    #
    # The log is compared by its length and its last line rather than by its
    # whole contents. `MessageLog#add` drops a line identical to the one
    # before it, so two of those in a row leave the log as it was and leave
    # the screen as it was.
    private record Watch,
      health : Int32,
      said : Int32,
      last : String?,
      seen : Array(Monster) do
      def self.on(game : Game, seen : Vision) : Watch
        new game.player.hit_points, game.log.size, game.log.last?,
          game.monsters_in_sight(seen)
      end
    end

    # What stopped the run on this step. `nil` when nothing did.
    #
    # *before* is what `Watch.on` recorded before the step. *along* says
    # whether the square the character stepped from was a length of corridor.
    #
    # Several can hold at once, and the order here is the order a person
    # would name them. A creature coming into sight is usually what wrote the
    # message on the same step, so it is asked about first.
    private def stopped_by(before : Watch, along : Bool, seen : Vision) : Halt?
      return Halt::Over if @outcome.over?
      return Halt::Hurt if @player.hit_points != before.health
      return Halt::Creature if arrived_in_sight? before.seen, seen
      return Halt::Told if @log.size != before.said || @log.last? != before.last
      return Halt::Doorway if standing_on.door?
      return Halt::Branch if along && ways(@player.at).size > CORRIDOR

      nil
    end

    # Whether any creature in sight now was out of sight before.
    #
    # A creature that was already in sight when the step began does not stop
    # the run, or a run could not be started with one on the screen.
    private def arrived_in_sight?(before : Array(Monster), seen : Vision) : Bool
      monsters_in_sight(seen).any? do |creature|
        before.none? &.same?(creature)
      end
    end

    # How many ways off a square a length of corridor has.
    CORRIDOR = 2

    # Whether *spot* is a length of corridor.
    #
    # Two ways off it, and the two face each other. The corner of a room also
    # has two ways off it, at right angles to each other, and a run along the
    # wall of a room would stop on its first step if that counted.
    #
    # A run stops when it steps off a corridor square onto a square with more
    # ways off it. A run that starts anywhere else goes until something else
    # stops it, so a run leaves a dead end and crosses a room.
    private def corridor?(spot : {Int32, Int32}) : Bool
      found = ways spot

      found.size == CORRIDOR && found.first.opposite == found.last
    end

    # Which of the four squares beside *spot* can be walked onto.
    #
    # Cardinals only. Two squares that touch at a corner alone are not a way
    # between rooms, and counting them would read every bend in a corridor as
    # a junction.
    private def ways(spot : {Int32, Int32}) : Array(Direction)
      Direction.values.select do |direction|
        next false if direction.diagonal?

        where = direction.from spot[0], spot[1]
        floor.passable? where[0], where[1]
      end
    end

    # Records what the character has just had their hands on.
    #
    # A door they opened or shut, a sconce they lit or put out. `#look` picks
    # up whatever they can see, and in the dark that is one square. Somebody
    # who has just shut a door knows it is shut whether or not they can see
    # it, and the map has to say so rather than going on showing what was
    # there the last time there was light on it.
    #
    # It records the shape of the square and what is fixed to it, and not
    # what is lying on the floor.
    private def handled(spot : {Int32, Int32}) : Nil
      @player.knowledge.touch floor, spot[0], spot[1], @turn
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

      take_coins

      pile = here
      return if pile.empty?

      if pile.size == 1
        say "You see #{name pile.first} here."
      else
        say "There are #{pile.size} things here."
      end
    end

    # ------------------------------------------------------------- fighting

    # The character swings at *creature*. Answers what the swing did.
    #
    # A swing takes a turn whether it lands or not. A creature left at zero
    # hit points is taken off the floor and what killing it is worth is
    # awarded.
    def attack(creature : Monster) : Blow
      blow = Combat.swing exchange, @player.to_hit,
        creature.armour_class, @player.damage

      if blow.hit?
        creature.hurt blow.damage
        say "You hit the #{creature.label} for #{blow.damage}."
        kill creature unless creature.alive?
      else
        say "You miss the #{creature.label}."
      end

      jar

      wake creature if creature.alive?
      spend_turn
      blow
    end

    # Takes *creature* off the floor and awards its experience.
    #
    # Whatever it was carrying lands on the square it died on. A lit torch
    # goes on burning there.
    #
    # This is public so that the debug console's `kill` command can call it
    # rather than repeat it. Nothing in a normal run reaches it from outside
    # `Game`.
    def kill(creature : Monster) : Nil
      floor.remove creature.x, creature.y
      creature.drop_everything.each do |item|
        floor.drop creature.x, creature.y, item
      end
      say "You kill the #{creature.label}."

      gained = @player.gain creature.species.experience
      say "Welcome to level #{@player.level}." if gained > 0
    end

    # ------------------------------------------------------------- shooting

    # Why the character cannot shoot. `nil` when they can.
    #
    # `Play` asks this before it puts the targeting cursor up, so a person
    # with an empty quiver is told at once and spends no turn finding out.
    def cannot_fire : String?
      ranged_weapon = @player.ranged_weapon
      unless ranged_weapon && ranged_weapon.kind.item_class.ranged_weapon?
        return "You have nothing readied to shoot with."
      end

      ammunition = @player.quivered
      return "Your quiver is empty." unless ammunition
      return if ammunition.kind.ranged_weapon == ranged_weapon.kind

      "You cannot shoot #{name ammunition} from #{name ranged_weapon}."
    end

    # How far the readied ranged weapon shoots. Zero when nothing is readied.
    def firing_reach : Int32
      found = @player.ranged_weapon
      return 0 unless found && found.kind.item_class.ranged_weapon?

      found.kind.reach
    end

    # Where a thing let go at *target* with *reach* squares in it would stop.
    #
    # `Play` draws this while a person aims. Nothing about the run changes.
    def flight(target : {Int32, Int32}, reach : Int32) : Flight
      Flight.toward floor, @player.at, target, reach
    end

    # Fires the readied ranged weapon at *target*. Answers whether it went.
    #
    # One piece of ammunition leaves the quiver. It lands on the square the
    # shot stopped on, hit or miss.
    def fire(target : {Int32, Int32}) : Bool
      complaint = cannot_fire
      if complaint
        say complaint
        return false
      end

      ranged_weapon = @player.ranged_weapon
      letter = @player.equipment[Slot::Quiver]
      return false unless ranged_weapon && letter

      ammunition = @player.inventory[letter]
      return false unless ammunition

      bonus = @player.to_shoot ranged_weapon, ammunition
      damage = @player.shot_damage ranged_weapon, ammunition

      one = draw_one letter
      return false unless one

      say "You shoot #{name one}."
      loose one, target, ranged_weapon.kind.reach, bonus, damage
      true
    end

    # Throws what is under *letter* at *target*. Answers whether it went.
    #
    # One of a stack goes. A person carrying twenty darts throws one dart.
    def throw(letter : Char, target : {Int32, Int32}) : Bool
      item = @player.inventory[letter]
      return false unless item

      slot = slot_of letter
      if slot && item.sticks?
        item.reveal_blessing
        say "You cannot let go of #{name item}."
        return false
      end

      if slot && slot.armour?
        say "You have to take #{name item} off first."
        return false
      end

      bonus = @player.to_throw item
      damage = @player.throw_damage item
      reach = item.kind.reach

      one = draw_one letter
      return false unless one

      say "You throw #{name one}."
      loose one, target, reach, bonus, damage
      true
    end

    # Takes one of what is under *letter* out of the inventory.
    #
    # A letter left holding nothing comes out of whatever slot held it. The
    # last arrow empties the quiver.
    private def draw_one(letter : Char) : Item?
      one = @player.inventory.take letter, 1
      @player.equipment.clean @player.inventory
      one
    end

    # Sends *missile* at *target* and puts it on the floor where it stops.
    #
    # A creature in the way is swung at, whether or not it was the square
    # aimed at. A missile stops at the first thing standing in the line.
    private def loose(missile : Item, target : {Int32, Int32}, reach : Int32,
                      bonus : Int32, damage : Dice) : Nil
      shot = flight target, reach
      spot = shot.at
      struck = floor.monster spot[0], spot[1]

      hit struck, missile.kind.label, bonus, damage if struck

      floor.drop spot[0], spot[1], missile
      spend_turn
    end

    # Something called *noun* meets *creature*. Answers what it did.
    #
    # An arrow, a thrown rock and a bolt from a wand all land here. The noun
    # is what the message calls it.
    private def hit(creature : Monster, noun : String, bonus : Int32,
                    damage : Dice) : Blow
      blow = Combat.swing exchange, bonus, creature.armour_class, damage

      if blow.hit?
        creature.hurt blow.damage
        say "The #{noun} hits the #{creature.label} for #{blow.damage}."
        kill creature unless creature.alive?
      else
        say "The #{noun} misses the #{creature.label}."
      end

      wake creature if creature.alive?
      blow
    end

    # Gives every awake creature on the floor its turn.
    #
    # Each one reads a `Pursuit::Snapshot` and answers an `Action`, and this
    # method applies it. The snapshot holds no floor and no player: what a
    # creature knows about the shape of the world is its band's `Knowledge`
    # and what it knows about the character is where the band last saw them.
    # Every check against what is actually there happens here.
    #
    # One `Descent` is built for each awake band rather than for each of its
    # members. Every creature in the band reads the same one.
    #
    # The list is taken before any of them acts. A creature that moves would
    # otherwise change the table being walked, and a swing can end the run.
    private def creatures_act : Nil
      return if over?

      maps = descents
      held = [] of Monster
      floor.each_monster { |_column, _row, creature| held << creature }

      held.each do |creature|
        break if over?
        next unless awake? creature
        next unless floor.monster?(creature.x, creature.y)

        perform creature, plan(creature, maps)
      end
    end

    # One descent for each awake band that has something to walk toward.
    #
    # A band whose species does not path gets none. A slime walks straight at
    # what it is after and has no use for a map.
    private def descents : Hash(String, Descent)
      maps = {} of String => Descent

      floor.each_band do |band|
        next unless band.awake?

        quarry = band.knowledge(floor.id).sighting(Knowledge::PLAYER)
        next unless quarry

        maps[band.id] = Descent.toward band.knowledge(floor.id), quarry.at
      end

      maps
    end

    # What *creature* has decided to do.
    private def plan(creature : Monster, maps : Hash(String, Descent)) : Action
      band = floor.band creature.band
      return Action.wait unless band

      knowledge = band.knowledge floor.id
      quarry = knowledge.sighting Knowledge::PLAYER

      Pursuit.decide Pursuit::Snapshot.new(
        at: creature.at,
        knowledge: knowledge,
        quarry: quarry.try(&.at),
        stale: quarry.try(&.age(@turn)) || 0,
        descent: creature.species.paths? ? maps[creature.band]? : nil,
        blocked: standing_on_squares(creature),
        stumble: stumbles?(creature))
    end

    # Whether *creature* puts a foot wrong this turn.
    #
    # How often is `Species#clumsiness`, which falls as intelligence rises. A
    # creature that never put a foot wrong could never be shaken off in open
    # ground, whatever else it is like.
    private def stumbles?(creature : Monster) : Bool
      chance = creature.species.clumsiness
      return false unless chance > 0

      wander.rand(100) < chance
    end

    # Every square beside *creature* that something else is standing on.
    #
    # The character counts. A creature walks round its neighbours and swings
    # at the character rather than walking into them.
    private def standing_on_squares(creature : Monster) : Set({Int32, Int32})
      taken = Set({Int32, Int32}).new

      Direction.values.each do |direction|
        spot = direction.from creature.x, creature.y
        taken << spot if floor.monster? spot[0], spot[1]
      end

      taken << @player.at
      taken
    end

    # Does what *action* says, as far as the floor allows.
    #
    # A creature that decided to walk into a wall walks nowhere, and one
    # that decided to swing at an empty square swings at nothing.
    private def perform(creature : Monster, action : Action) : Nil
      direction = action.direction
      return unless direction

      wanted = direction.from creature.x, creature.y

      case action.intent
      in .wait?   then nil
      in .step?   then walk_creature creature, wanted
      in .strike? then strike creature if @player.at? wanted[0], wanted[1]
      end
    end

    # Moves *creature* onto *wanted*, when nothing is in the way.
    private def walk_creature(creature : Monster, wanted : {Int32, Int32}) : Nil
      return unless floor.passable? wanted[0], wanted[1]
      return if floor.monster? wanted[0], wanted[1]
      return if @player.at? wanted[0], wanted[1]

      floor.walk creature.at, wanted
    end

    # Whether the band *creature* belongs to has noticed the character.
    def awake?(creature : Monster) : Bool
      floor.awareness(creature).awake?
    end

    # Every creature standing next to the character.
    #
    # In the order `Direction` names them, so one turn plays out the same way
    # from the same seed.
    def adjacent : Array(Monster)
      Direction.values.compact_map do |direction|
        spot = direction.from @player.x, @player.y
        floor.monster spot[0], spot[1]
      end
    end

    # *creature* swings at the character. Answers what the swing did.
    private def strike(creature : Monster) : Blow
      blow = Combat.swing exchange, creature.to_hit,
        @player.armour_class, creature.damage

      if blow.hit?
        @player.hurt blow.damage
        say "The #{creature.label} hits you for #{blow.damage}."
        character_died creature.label unless @player.alive?
      else
        say "The #{creature.label} misses you."
      end

      blow
    end

    # Ends the run. *killer* is what did it.
    private def character_died(killer : String) : Nil
      @outcome = Outcome::Died
      @killer = killer
      say "You die..."
    end

    # Counts one turn and gives every other creature on the floor its own.
    #
    # Every action that takes a turn ends with this, after it has said what
    # it did. What the character did is then read before what was done back.
    #
    # Every band looks first and then the awake ones act, so a band that
    # notices the character this turn swings on the same turn it noticed.
    private def spend_turn : Nil
      @turn += 1
      handle_items
      blink
      return if over?

      seen = sight
      noticed = creatures_notice seen
      creatures_look seen, noticed
      creatures_act
    end

    # ------------------------------------------------------------ detection

    # Lets every band on this floor notice the character, or lose them.
    #
    # *seen* is what the character can see, which is also what can see the
    # character. The field of view is symmetric, so a creature the character
    # has a line to has a line back. That is one cast for the whole floor
    # rather than one for each creature standing on it.
    #
    # A band that notices writes down where the character is. Nothing reads
    # that until Phase 19 walks a band to the square.
    # Answers which bands noticed, and which of their creatures did it.
    private def creatures_notice(seen : Vision) : Hash(String, Monster)
      found = noticing seen

      floor.each_band do |band|
        creature = found[band.id]?

        if creature
          woke = band.awareness.asleep?
          band.awareness = Awareness::Hunting
          band.knowledge(floor.id).saw Knowledge::PLAYER, @player.x, @player.y, @turn
          say noticed(creature, seen) if woke
        elsif band.awareness.hunting?
          # It knows where the character was and cannot see them now. It
          # walks there, and gives up when the trail is cold enough.
          band.awareness = Awareness::Alert
        elsif band.awareness.alert?
          give_up band if cold? band
        end
      end

      found
    end

    # How many turns a band with nobody left on this floor goes on looking.
    #
    # Every band that has a member takes the member's own number instead. This
    # is only what is left when there is nobody to ask.
    PATIENCE = 10

    # Whether the trail *band* is following has gone cold.
    private def cold?(band : Band) : Bool
      seen = band.knowledge(floor.id).sighting Knowledge::PLAYER
      return true unless seen

      seen.age(@turn) > patience(band)
    end

    # How many turns *band* goes on looking after it has lost the character.
    #
    # The most persistent of its members decides. A band is one species now,
    # and when it is more than one the member that will not let go is what
    # keeps the whole band looking.
    #
    # This is what decides whether a person can run away. An orc follows a
    # cold trail for a long time and a goblin gives up quickly.
    private def patience(band : Band) : Int32
      most = nil.as(Int32?)

      floor.each_monster do |_column, _row, creature|
        next unless creature.band == band.id

        found = creature.species.persistence
        most = found if most.nil? || found > most
      end

      most || PATIENCE
    end

    # *band* stops looking and goes back to sleep.
    #
    # What it learned of the floor stays. Where it last saw the character
    # does not, so a band that wakes again starts from where it finds them.
    private def give_up(band : Band) : Nil
      band.awareness = Awareness::Asleep
      band.knowledge(floor.id).lost Knowledge::PLAYER
    end

    # Lets every awake creature look about and write what it saw into its
    # band's `Knowledge`.
    #
    # This is what a band builds its `Descent` over. A band that has walked a
    # corridor can walk it again in the dark; one that has never been down it
    # cannot use it as a shortcut.
    #
    # The lighting is worked out once for the whole floor and handed to each
    # of them. A species with darkvision is given none, so it learns the
    # shape of everything it has a line to whether there is light on it or
    # not.
    #
    # An asleep band looks at nothing. That is what bounds the work: a floor
    # of sleeping monsters costs one cast, the character's own.
    private def creatures_look(seen : Vision, noticed : Hash(String, Monster)) : Nil
      lighting = seen.lighting

      noticed.each do |id, creature|
        band = floor.band id
        trace band.knowledge(floor.id), creature.at if band
      end

      floor.each_monster do |column, row, creature|
        next unless awake? creature

        band = floor.band creature.band
        next unless band

        looking = Vision.new FieldOfView.from(floor, column, row),
          creature.species.darkvision? ? nil : lighting
        knowledge = band.knowledge floor.id
        knowledge.learn floor, looking, @turn
        feel knowledge, column, row
      end
    end

    # Records the ground between *from* and the character.
    #
    # A creature that can see the character can see that nothing solid stands
    # between them. A line that reached them ran through every square on the
    # way, so it knows that ground well enough to walk it, and it goes on
    # knowing it after the light has gone.
    #
    # This is what lets a creature in a dark corridor walk toward somebody
    # standing in a pool of light. The squares between are dark, so it never
    # sees them, but it can see across them.
    #
    # It records that they can be crossed and no more. What each one is made
    # of it has not looked at, and `Knowledge#opening` is careful not to
    # claim otherwise.
    private def trace(knowledge : Knowledge, from : {Int32, Int32}) : Nil
      Line.walk(from, @player.at) do |spot|
        knowledge.opening spot[0], spot[1]
      end
    end

    # Records the ground *x*, *y* could be reached out and touched from.
    #
    # A creature standing in a dark corridor sees nothing but the square
    # under its own feet. It can still feel the walls beside it and the floor
    # in front of it, and a creature that knew only what it could see would
    # never take the first step out of the dark: a `Descent` cannot reach a
    # square nobody has looked at, so it would not be on its own map.
    #
    # What it is standing on it knows whole, items and all. What is beside
    # it it knows the shape of and no more.
    private def feel(knowledge : Knowledge, x : Int32, y : Int32) : Nil
      knowledge.see floor, x, y, @turn

      Direction.values.each do |direction|
        spot = direction.from x, y
        knowledge.touch floor, spot[0], spot[1], @turn
      end
    end

    # Which bands notice the character, and which of their creatures did.
    #
    # One creature is enough to wake a band. The message names the first one
    # found.
    private def noticing(seen : Vision) : Hash(String, Monster)
      light = seen.light @player.x, @player.y
      stealth = @player.attributes.stealth
      found = {} of String => Monster

      floor.each_monster do |column, row, creature|
        next if found.has_key? creature.band
        next if creature.blind?
        next unless Notice.notices? creature.species, stealth, light,
                      {column, row}, @player.at, seen.field.includes?(column, row)

        found[creature.band] = creature
      end

      found
    end

    # What to say when a band wakes up.
    #
    # A creature the character can see is named. One they cannot is not: the
    # character has heard something move and does not know what it was.
    private def noticed(creature : Monster, seen : Vision) : String
      return "You hear something stir." unless seen.shows? floor, creature.x, creature.y

      "The #{creature.label} notices you."
    end

    # Wakes the band *creature* belongs to.
    #
    # A creature that has been hit knows it has been hit. This runs whatever
    # the light is and whatever the character's stealth is.
    #
    # It writes down where the blow came from as well. Being hit in the dark
    # says which side the character is on, and a band with nowhere to go
    # would give up the turn after it woke.
    private def wake(creature : Monster) : Nil
      band = floor.band creature.band
      return unless band

      band.knowledge(floor.id).saw Knowledge::PLAYER, @player.x, @player.y, @turn
      return unless band.awareness.asleep?

      band.awareness = Awareness::Hunting
      say "The #{creature.label} notices you."
    end

    # The generator for the next swing.
    #
    # Combat draws from a stream named by how many swings this run has
    # rolled. A fight then rolls the same numbers from the same seed whatever
    # else the run has drawn. A save file holds that count rather than the
    # position of a generator, which PCG32 cannot be asked for.
    private def exchange : Rng
      root = (@root ||= Rng.new @world.seed)
      found = root.derive "combat", @blows
      @blows += 1

      found
    end

    # The generator for the next thing used.
    #
    # `#exchange` without the fight. A potion drunk between two swings rolls
    # here, so the swings roll the same numbers whether it was drunk or not.
    private def draught : Rng
      root = (@root ||= Rng.new @world.seed)
      found = root.derive "use", @uses
      @uses += 1

      found
    end

    # The generator for the next creature asked whether it blunders.
    #
    # A stream of its own, so how many creatures are on the floor and how
    # often they put a foot wrong changes nothing about what a swing rolls.
    private def wander : Rng
      root = (@root ||= Rng.new @world.seed)
      found = root.derive "wander", @wanders
      @wanders += 1

      found
    end

    # The generator for this turn's question about what is carried.
    #
    # One stream for the whole turn, drawn from once per item. A pack with
    # forty things in it advances this counter as far as an empty one does.
    private def noticing : Rng
      root = (@root ||= Rng.new @world.seed)
      found = root.derive "handling", @handled
      @handled += 1

      found
    end

    # Opens the door *direction*. Answers whether it opened.
    #
    # Opening takes a turn. Trying to open something that is not a shut door
    # takes none.
    def open(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      unless floor.tile?(wanted[0], wanted[1]).try &.terrain.closed_door?
        say "There is nothing to open that way."
        return false
      end

      floor.set wanted[0], wanted[1], Terrain::OpenDoor
      handled wanted
      say "You open the door."
      spend_turn
      true
    end

    # Closes the door *direction*. Answers whether it closed.
    #
    # A doorway with anything in it stays open. A door swings through the
    # square it stands in, and a creature or a pile of loot is in its way.
    def close(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      unless floor.tile?(wanted[0], wanted[1]).try &.terrain.open_door?
        say "There is nothing to close that way."
        return false
      end

      blocked = doorway_blocked wanted
      if blocked
        say blocked
        return false
      end

      floor.set wanted[0], wanted[1], Terrain::ClosedDoor
      handled wanted
      say "You close the door."
      spend_turn
      true
    end

    # Why the door on *spot* will not shut. `nil` when nothing stops it.
    #
    # A creature standing in the doorway is named when the character can see
    # it. One they cannot see is not: they have pushed the door against
    # something and do not know what. Anything lying on the square stops the
    # door the same way.
    private def doorway_blocked(spot : {Int32, Int32}) : String?
      creature = floor.monster spot[0], spot[1]
      if creature
        return "There is something in the doorway." unless can_see_creature? spot[0], spot[1]

        return "The #{creature.label} is in the doorway."
      end

      return unless floor.items? spot[0], spot[1]

      "Something is lying in the doorway."
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

    # What the character can see from where they stand.
    #
    # This is worked out again every time it is asked for. It depends on where
    # the character stands, on which doors are open, and on what is alight,
    # and all of those change often enough that a cache would need
    # invalidating from a dozen places. One cast over the shipped floor
    # touches a few hundred squares. A cache goes in when a profile asks for
    # one.
    def sight : Vision
      return Vision.blind @player.at if @player.blind?

      Vision.from floor, @player.at, lights
    end

    # Whether the character can see *x*, *y* from where they stand.
    def can_see?(x : Int32, y : Int32) : Bool
      sight.includes? x, y
    end

    # Whether a creature standing at *x*, *y* would be seen.
    #
    # By the light on them, or as a shape against light behind them. A
    # creature crossing a lit doorway is seen from a dark corridor. The same
    # creature in a dark corner with nothing behind them is not.
    def can_see_creature?(x : Int32, y : Int32) : Bool
      sight.shows? floor, x, y
    end

    # Every monster on this floor the character can see.
    def monsters_in_sight : Array(Monster)
      monsters_in_sight sight
    end

    # :ditto:, against a field of view that has already been worked out.
    #
    # Working out a field of view is most of what a turn on a large floor
    # costs, and a run asks this twice a step. A caller with one in hand
    # passes it rather than paying for another.
    def monsters_in_sight(seen : Vision) : Array(Monster)
      found = [] of Monster

      floor.each_monster do |column, row, creature|
        found << creature if seen.shows? floor, column, row
      end

      found
    end

    # Works out what the character can see, and remembers it.
    #
    # This is the one place anything gets into `Player#knowledge`. Whatever is
    # about to draw the floor calls it, so what is remembered and what is
    # drawn are never out of step.
    #
    # `#sight` answers the same thing without remembering it. A spec reading
    # the field of view uses that one.
    def look : Vision
      seen = sight
      @player.knowledge.learn floor, seen, @turn
      seen
    end

    # What the character remembers of the floor they are on.
    def knowledge : Knowledge
      @player.knowledge
    end

    # ----------------------------------------------------------------- light

    # Everything on this floor that is throwing light.
    #
    # Lit wall sconces, lit torches and candles lying about, whatever the
    # character is carrying alight, and whatever a monster is carrying
    # alight. The floor's own glow is not here: a
    # glowing square is not a source, and `Lighting.over` reads it straight
    # off the floor.
    def lights : Array(LightSource)
      found = [] of LightSource

      floor.each_fixture do |column, row, fitting|
        next unless fitting.lit?

        found << LightSource.new column, row, fitting.light,
          facing: fitting.attached
      end

      floor.each_pile do |column, row, pile|
        pile.each do |item|
          found << LightSource.new(column, row, item.light) if item.lit?
        end
      end

      @player.inventory.each do |_letter, item|
        found << LightSource.new(@player.x, @player.y, item.light) if item.lit?
      end

      floor.each_monster do |column, row, creature|
        creature.carrying.each do |item|
          found << LightSource.new(column, row, item.light) if item.lit?
        end
      end

      found
    end

    # Everything the character could apply right now.
    #
    # A carried torch or candle, lit or not. A sconce on their own square or
    # beside them, lit or not. Each is one entry, and `#apply` does whatever
    # that entry's state calls for.
    def appliable : Array(Apply)
      found = [] of Apply

      @player.inventory.each do |letter, item|
        found << Apply.carried(letter) if item.burns?
      end

      found << Apply.fixture(@player.x, @player.y) if floor.fixture @player.x, @player.y

      Direction.values.each do |direction|
        wanted = direction.from @player.x, @player.y
        next unless floor.fixture wanted[0], wanted[1]

        found << Apply.fixture(wanted[0], wanted[1])
      end

      found
    end

    # Does whatever *target* calls for. Answers whether anything happened.
    #
    # An unlit thing is lit. A lit thing is put out. Either takes a turn.
    def apply(target : Apply) : Bool
      letter = target.letter
      return apply_carried letter if letter

      apply_fixture target.x, target.y
    end

    # Lights or puts out the carried item under *letter*.
    private def apply_carried(letter : Char) : Bool
      item = @player.inventory[letter]
      return false unless item

      unless item.burns?
        say "You cannot light #{name item}."
        return false
      end

      if item.lit?
        item.douse
        say "You put out #{name item}."
      else
        item.kindle
        say "You light #{name item}."
      end

      spend_turn
      true
    end

    # Lights or puts out the fixture at *x*, *y*.
    private def apply_fixture(x : Int32, y : Int32) : Bool
      fitting = floor.fixture x, y
      return false unless fitting

      if fitting.lit?
        fitting.douse
        say "You put the #{fitting.kind.label} out."
      else
        fitting.kindle
        say "The #{fitting.kind.label} catches and burns."
      end

      handled({x, y})
      spend_turn
      true
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
        say "You pick up #{Game.coins item.count}."
        spend_turn
        return true
      end

      letter = @player.inventory.add item
      unless letter
        floor.drop @player.x, @player.y, item
        say "You cannot carry any more."
        return false
      end

      say "#{letter} - #{name item}"
      spend_turn
      true
    end

    # Takes any gold on the square, without a turn of its own.
    #
    # The step onto the square is the turn. Nobody walks over coins and
    # leaves them, and asking would be a keystroke for every pile.
    #
    # Gold is counted rather than carried, so there is no pack to fill and no
    # way for this to refuse.
    private def take_coins : Nil
      taken = 0

      here.select(&.kind.item_class.treasure?).each do |item|
        next unless floor.take @player.x, @player.y, item

        @player.take_gold item.count
        taken += item.count
      end

      say "You pick up #{Game.coins taken}." if taken > 0
    end

    # *total* gold pieces, written so one of them is one piece.
    def self.coins(total : Int32) : String
      total == 1 ? "1 gold piece" : "#{total} gold pieces"
    end

    # Picks up everything on the square. Answers how many entries were taken.
    def pick_up_all : Int32
      taken = 0

      here.dup.each do |item|
        break if over?

        taken += 1 if pick_up item
      end

      taken
    end

    # Puts everything under *letter* on the floor. Answers whether it went.
    #
    # A curse holds what is in a slot and nothing else, so the slot check
    # below is the whole rule. A cursed dagger at the bottom of the pack goes
    # on the floor like any other.
    def drop(letter : Char) : Bool
      item = @player.inventory[letter]
      return false unless item

      slot = slot_of letter
      if slot
        say "You have to take #{name item} off first."
        return false
      end

      dropped = name_under letter
      held = @player.inventory.remove letter
      @player.equipment.clean @player.inventory
      held.each { |one| floor.drop @player.x, @player.y, one }
      say "You drop #{dropped}."
      spend_turn
      true
    end

    # Puts *amount* gold pieces on the floor. Answers how many went.
    def drop_gold(amount : Int32) : Int32
      dropped = @player.spend_gold amount
      return 0 if dropped.zero?

      floor.drop @player.x, @player.y, Item.new(ItemKind::Gold, count: dropped)
      say "You drop #{dropped} gold pieces."
      spend_turn
      dropped
    end

    # ---------------------------------------------------------- consumables

    # What using the item under *letter* would do.
    #
    # `Play` asks this before it uses the item. A wand that needs a square to
    # aim at and a scroll that needs an item to work on each say so here, so
    # the question is asked before the turn is spent rather than after.
    def effect_of(letter : Char) : Effect
      @player.inventory[letter].try(&.kind.effect) || Effect::None
    end

    # Drinks what is under *letter*. Answers whether it went down.
    def quaff(letter : Char) : Bool
      use letter, ItemClass::Potion, "drink" do |item|
        say "You drink #{name item}."
      end
    end

    # Why the character cannot read. `nil` when they can.
    #
    # `Play` asks this before it offers the scrolls, so a person standing in
    # the dark is told before they choose one rather than after.
    def cannot_read : String?
      return if sight.lit? @player.x, @player.y

      "It is too dark to read."
    end

    # Reads what is under *letter*. Answers whether it was read.
    #
    # *choice* is the carried item a scroll of identify works on. Every other
    # scroll ignores it.
    #
    # A scroll is words on paper. Somebody standing in the dark cannot make
    # them out, and the scroll is not spent finding that out.
    def read(letter : Char, choice : Char? = nil) : Bool
      complaint = cannot_read
      if complaint
        say complaint
        return false
      end

      use letter, ItemClass::Scroll, "read", choice do |item|
        say "You read #{name item}."
      end
    end

    # Whether reading the scroll under *letter* will ask for a carried item.
    #
    # A scroll of identify always asks. A scroll of blessing asks only when
    # nothing has touched it: a blessed one reaches everything and a cursed
    # one picks its own target.
    def choice_needed?(letter : Char) : Bool
      item = @player.inventory[letter]
      return false unless item

      effect = item.kind.effect
      return true if effect.identify?
      return false unless effect.marks?

      item.blessing.uncursed?
    end

    # Whether reading the scroll under *letter* will ask for a square.
    #
    # A scroll of blindness aims at a creature, and a blessed scroll of minor
    # teleport goes where the character says. Neither question can be asked
    # before the scroll is read, because what the scroll does depends on the
    # blessing on it and reading it is how the character finds that out.
    def target_needed?(letter : Char) : Bool
      item = @player.inventory[letter]
      return false unless item
      return false unless item.kind.effect.aims_after?
      return false if item.cursed?

      item.kind.effect.teleport? ? item.blessed? : !item.blessed?
    end

    # Whether the scroll under *letter* has to show the character something
    # before it asks.
    #
    # The marks are half of what a scroll of blessing does, and picking
    # without them is picking blind.
    def marks_first?(letter : Char) : Bool
      item = @player.inventory[letter]
      return false unless item

      item.kind.effect.marks? && choice_needed? letter
    end

    # Reads the scroll under *letter* as far as its question.
    #
    # The scroll is used up, the marks are made and the turn is spent.
    # Answers the scroll, which `#finish_reading` needs, or `nil` when it
    # could not be read at all.
    #
    # The two halves are separate because the marks have to be on screen
    # before the character picks. Nothing is held between the two calls:
    # a game saved while the question is up has spent the scroll and the
    # turn, and has given up whatever the second half would have done.
    def start_reading(letter : Char) : Item?
      complaint = cannot_read
      if complaint
        say complaint
        return
      end

      item = @player.inventory[letter]
      return unless item && item.kind.item_class.scroll?

      used = @player.inventory.take letter, 1
      return unless used
      @player.equipment.clean @player.inventory

      used.reveal_blessing unless used.blessing.uncursed?
      say "You read #{name used}."
      found_out used.kind
      mark_for used
      spend_turn
      used
    end

    # Does what *scroll* answered for. Spends no turn.
    #
    # `#start_reading` has already used the scroll up and spent the turn.
    # A character who picked nothing gets nothing.
    def finish_reading(scroll : Item, choice : Char?) : Bool
      return false unless scroll.kind.effect.marks?

      anoint_one scroll, choice
      true
    end

    # Reads the scroll under *letter* as far as its aim.
    #
    # The scroll is used up and the turn is spent, the same way
    # `#start_reading` does it. Answers the scroll, which `#aim_reading`
    # needs. The square is asked for afterwards, because until the scroll is
    # read the character does not know what it wants one for.
    def start_aiming_read(letter : Char) : Item?
      complaint = cannot_read
      if complaint
        say complaint
        return
      end

      item = @player.inventory[letter]
      return unless item && item.kind.item_class.scroll?

      used = @player.inventory.take letter, 1
      return unless used
      @player.equipment.clean @player.inventory

      used.reveal_blessing unless used.blessing.uncursed?
      say "You read #{name used}."
      found_out used.kind
      spend_turn
      used
    end

    # Does what *scroll* was aimed at. Spends no turn.
    def aim_reading(scroll : Item, target : {Int32, Int32}?) : Bool
      return false unless scroll.kind.effect.aims_after?

      work scroll.kind.effect, scroll, target: target
      true
    end

    # Zaps what is under *letter*. Answers whether anything came out of it.
    #
    # *target* is the square an offensive wand is aimed at. A wand of light
    # ignores it.
    #
    # A charge goes whether or not the wand does anything worth seeing. A
    # spent one says so and still costs the turn: a person cannot know a wand
    # is empty until they try it.
    def zap(letter : Char, target : {Int32, Int32}? = nil) : Bool
      item = @player.inventory[letter]
      return false unless item

      unless item.kind.item_class.wand?
        say "You cannot zap #{name item}."
        return false
      end

      if dormant? item
        say "#{name(item).capitalize} is cracked and does nothing."
        return false
      end

      if item.sticks? && free_hand.nil?
        item.reveal_blessing
        say "Neither hand is free."
        return false
      end

      unless item.spend
        say "You zap #{name item}. Nothing happens."
        cool item
        spend_turn
        return true
      end

      say "You zap #{name item}."
      work item.kind.effect, item, target: target
      found_out item.kind
      grasp letter, item
      cool item
      spend_turn
      true
    end

    # ------------------------------------------------ what the character can tell

    # Asks what the character has noticed about what they carry.
    #
    # Every item they have not placed gains what this turn was worth and then
    # rolls. `Handling` holds the numbers.
    #
    # The rolls are collected before any of them is acted on. Noticing a
    # blessing moves the item to a letter of its own, and moving things about
    # while walking them is how entries get missed.
    private def handle_items : Nil
      stream = noticing
      found = [] of {Char, Item}

      @player.inventory.each_item do |letter, item|
        next if item.blessing_known?

        gain = @player.equipment.readied?(letter) ? Handling::WORN : Handling::CARRIED
        item.handle gain
        next if item.handling < Handling::LEAST
        next unless stream.rand(Handling::SPAN) < gain

        found << {letter, item}
      end

      found.each { |letter, item| noticed letter, item }
    end

    # Says the character has worked out what *item* is, and sorts the pack.
    private def noticed(letter : Char, item : Item) : Nil
      return unless item.reveal_blessing

      say Game.worked_out @lore, item
      settle letter, item
    end

    # What the character says when they work a blessing out for themselves.
    #
    # The verb agrees with the count, because one stack of three says "are"
    # and a single dagger says "is".
    #
    # The name leaves the blessing word out either way, because the sentence
    # is what says it. A curse or a blessing is news and the line ends in a
    # mark. An uncursed item is not news and the line is flat.
    def self.worked_out(lore : Lore, item : Item) : String
      named = lore.name item, blessing: false
      verb = item.count > 1 ? "are" : "is"
      return "You are certain that #{named} #{verb} not cursed." if item.blessing.uncursed?

      "You realize that #{named} #{verb} #{item.blessing.label}!"
    end

    # Records that the character has found out *item*'s blessing, and sorts
    # the pack. Answers whether that was news.
    private def learned(letter : Char, item : Item) : Bool
      return false unless item.reveal_blessing

      settle letter, item
      true
    end

    # Moves *item* to a letter of its own, now that it no longer looks like
    # what it was sitting with.
    #
    # With every letter taken there is nowhere for it to go. What it was
    # sitting with goes on the floor instead, and what the character has just
    # worked out keeps the letter.
    private def settle(letter : Char, item : Item) : Nil
      return if @player.inventory.relocate letter, item

      rest = @player.inventory.strip letter, item
      return if rest.empty?

      rest.each { |one| floor.drop @player.x, @player.y, one }
      @player.equipment.clean @player.inventory
      say "You have no letter left to keep them apart, and put the rest down."
    end

    # ---------------------------------------------------------- cursed wands

    # How often in a hundred swings a wand in the hand cracks.
    BRITTLE = 8

    # Whether *item* is a wand that has cracked.
    #
    # A cracked wand does nothing and holds nothing. It is the way out of a
    # curse that never ran out of charges.
    private def dormant?(item : Item) : Bool
      item.kind.item_class.wand? && item.condition.damaged?
    end

    # Which hand a cursed wand can take. `nil` when both are held.
    #
    # The weapon hand first, and the one that holds a bow when a curse has
    # the weapon hand already. A slot counts as free when it is empty or
    # when what is in it is not cursed, whether or not the character knows
    # that yet.
    private def free_hand : Slot?
      {Slot::Melee, Slot::Ranged}.find do |slot|
        item = @player.in_slot slot
        item.nil? || !item.sticks?
      end
    end

    # Puts a cursed wand in the character's hand.
    #
    # Zapping a cursed wand is how a wand gets into a hand at all. `w` does
    # not offer one, because `Slot.for` puts a wand in no slot.
    #
    # Whatever it displaces goes back to being carried. It is not readied
    # again when the wand leaves; the character does that.
    private def grasp(letter : Char, item : Item) : Nil
      return unless item.sticks?
      return if @player.equipment.readied? letter

      slot = free_hand
      return unless slot

      item.reveal_blessing
      @player.equipment.clear slot
      @player.equipment.put slot, letter
      say "#{name(item).capitalize} twists into your hand."
    end

    # Takes the curse off a wand that has nothing left.
    #
    # An empty wand has nothing to hold anybody with. The character watched
    # it let go, so they know.
    private def cool(item : Item) : Nil
      return unless item.sticks? && item.spent?
      return unless item.uncurse

      say "#{name(item).capitalize} goes cold and lets go."
    end

    # Rolls whether the wand in the hand cracks on this swing.
    private def jar : Nil
      item = @player.wielded
      return unless item && item.kind.item_class.wand?
      return unless draught.rand(100) < BRITTLE
      return unless item.crack

      say "#{name(item).capitalize} cracks."
    end

    # Uses one of what is under *letter*, which has to be of *item_class*.
    #
    # A potion and a scroll are used up. The block says what using it looks
    # like, before the effect says what it did.
    private def use(letter : Char, item_class : ItemClass, verb : String,
                    choice : Char? = nil, & : Item -> Nil) : Bool
      item = @player.inventory[letter]
      return false unless item

      unless item.kind.item_class == item_class
        say "You cannot #{verb} #{name item}."
        return false
      end

      used = @player.inventory.take letter, 1
      return false unless used
      @player.equipment.clean @player.inventory

      # A curse or a blessing on a thing that is used up shows in what it
      # does, so the character learns what this one was as they use it. An
      # uncursed one has nothing to show. The rest of the stack keeps its
      # secret either way.
      used.reveal_blessing unless used.blessing.uncursed?

      yield used
      found_out used.kind
      work used.kind.effect, used, choice: choice
      spend_turn
      true
    end

    # Does what *effect* names.
    #
    # This is the one place an effect turns into something happening. Every
    # item names its effect and nothing holds a block, so this method is the
    # whole registry.
    private def work(effect : Effect, item : Item,
                     choice : Char? = nil,
                     target : {Int32, Int32}? = nil) : Nil
      case effect
      in .none?            then say "Nothing happens."
      in .heal?            then mend item
      in .identify?        then name_one choice
      in .map_floor?       then map_the_floor
      in .light?           then light_up
      in .strike?          then bolt item, target
      in .bless?           then anoint item, choice
      in .remove_curse?    then anoint item, choice
      in .detect_treasure? then find_treasure item
      in .detect_items?    then find_items item
      in .darkness?        then put_out item
      in .blind?           then blind_with item, target
      in .teleport?        then teleport_with item, target
      end
    end

    # Passes one turn of anything that cannot see.
    #
    # The character is told when their sight comes back. A creature is not:
    # what a creature can see is its own business, and the character has no
    # way to tell one that is blind from one that is looking elsewhere.
    private def blink : Nil
      say "You can see again." if @player.blink

      floor.each_monster { |_column, _row, creature| creature.blink }
    end

    # ------------------------------------------------------------- detection

    # How far across and down the oval a scroll of item detection reaches is,
    # as a share of the floor out of a hundred.
    #
    # An oval rather than a circle, because a floor is wider than it is tall
    # and a circle on one reaches most of the way to the top and bottom edges
    # while leaving the sides untouched.
    DETECTION_SPAN = 25

    # How much of the gold a cursed scroll of treasure detection ruins, out
    # of a hundred.
    TREASURE_RUIN = 50

    # How much of what it found a cursed scroll of item detection destroys,
    # out of a hundred. It rounds up, so it always destroys something.
    DETECTION_RUIN = 20

    # What a ruined pile of gold is left holding.
    RUINED = 1

    # Writes down where the gold on this floor is.
    #
    # A cursed one ruins half of what it finds on the way past, leaving a
    # single coin behind and saying how much went. A blessed one brings it
    # all to the character's feet rather than writing it down.
    private def find_treasure(scroll : Item) : Nil
      piles = [] of {Int32, Int32, Item}
      floor.each_pile do |column, row, pile|
        pile.each do |item|
          piles << {column, row, item} if item.kind.item_class.treasure?
        end
      end

      if piles.empty?
        say "Nothing here is worth anything."
        return
      end

      return gather_treasure piles if scroll.blessed?
      return ruin_treasure piles if scroll.cursed?

      piles.each { |column, row, item| detect column, row, item }
      say "You know where #{Game.piles piles.size}."
    end

    # *count* piles of gold, with the verb that agrees with them.
    def self.piles(count : Int32) : String
      count == 1 ? "1 pile of gold is" : "#{count} piles of gold are"
    end

    # A blessed scroll, which brings the gold to the character.
    private def gather_treasure(piles : Array({Int32, Int32, Item})) : Nil
      total = 0

      piles.each do |column, row, item|
        next unless floor.take column, row, item

        @player.take_gold item.count
        total += item.count
      end

      say "#{piles.size} piles of gold teleport to your location, " \
          "totalling #{total} gp."
    end

    # A cursed scroll, which ruins half of what it finds.
    #
    # What is left is written down like the rest. A person who read it knows
    # where the gold was and what it is worth now.
    private def ruin_treasure(piles : Array({Int32, Int32, Item})) : Nil
      stream = draught
      lost = 0
      ruined = 0

      piles.each do |column, row, item|
        unless stream.rand(100) < TREASURE_RUIN
          detect column, row, item
          next
        end

        gone = item.count - RUINED
        next if gone <= 0

        floor.take column, row, item
        left = item.with_count RUINED
        floor.drop column, row, left
        detect column, row, left

        lost += gone
        ruined += 1
      end

      say "#{ruined} piles crumble, and #{lost} gp with them."
    end

    # Writes down what is lying about.
    #
    # An oval round the character, a quarter of the floor across and a
    # quarter down. A blessed one reaches the whole floor. A cursed one
    # destroys a fifth of what it found, rounded up, and says what it was.
    #
    # Gold is left out. A scroll of treasure detection is what finds that,
    # and a scroll that found both would make one of the two pointless.
    private def find_items(scroll : Item) : Nil
      found = [] of {Int32, Int32, Item}

      floor.each_pile do |column, row, pile|
        next unless scroll.blessed? || within_oval?(column, row)

        pile.each do |item|
          next if item.kind.item_class.treasure?

          found << {column, row, item}
        end
      end

      if found.empty?
        say "Nothing is lying anywhere you can feel."
        return
      end

      destroyed = scroll.cursed? ? destroy_some(found) : [] of Item
      found.each { |column, row, item| detect column, row, item }
      list_detected found, destroyed
    end

    # Whether *x*, *y* is inside the oval a scroll of item detection reaches.
    #
    # An oval rather than a circle. A floor is wider than it is tall, and a
    # circle on one reaches the top and bottom edges while leaving the sides
    # alone.
    private def within_oval?(x : Int32, y : Int32) : Bool
      # The span is how far across the whole oval is, so the reach from the
      # middle to the edge is half of it.
      across = Math.max floor.columns * DETECTION_SPAN // 200, 1
      down = Math.max floor.rows * DETECTION_SPAN // 200, 1

      dx = (x - @player.x) / across.to_f
      dy = (y - @player.y) / down.to_f

      dx * dx + dy * dy <= 1.0
    end

    # Destroys a fifth of *found*, rounded up, and takes those off the floor.
    #
    # Answers what went, which the list names in full. The entries it took
    # are taken out of *found* as well, so nothing is written down as lying
    # somewhere it no longer is.
    private def destroy_some(found : Array({Int32, Int32, Item})) : Array(Item)
      stream = draught
      wanted = (found.size * DETECTION_RUIN + 99) // 100
      gone = [] of Item

      found.shuffle(stream).first(wanted).each do |column, row, item|
        next unless floor.take column, row, item

        gone << item
      end

      found.reject! { |_column, _row, item| gone.any? &.same?(item) }
      gone
    end

    # Says what the scroll found, and what it destroyed on the way.
    #
    # What it destroyed goes first and is named in full, because a thing that
    # no longer exists has no secret left to keep. Naming it teaches nothing:
    # `Lore` is not told, so the colour that potion came in still means
    # nothing for the rest of the run.
    #
    # The rest are named as the character knows them, nearest first. Nothing
    # in the game has a price yet, so distance is what orders them.
    private def list_detected(found : Array({Int32, Int32, Item}),
                              destroyed : Array(Item)) : Nil
      destroyed.each do |item|
        say "#{@lore.name(item, identified: true).capitalize} - destroyed!"
      end

      found.sort_by! do |column, row, _item|
        Notice.apart({column, row}, @player.at)
      end

      found.each { |_column, _row, item| say "You feel #{name item}." }
    end

    # ---------------------------------------------------------------- dark

    # How far a scroll of darkness reaches.
    DARKNESS = 25

    # How often in a hundred a blessed scroll of darkness survives being
    # read.
    DARKNESS_KEPT = 50

    # Puts out the lights nearby and takes the glow off the squares.
    #
    # A cursed one destroys what it puts out rather than dousing it, the
    # carried ones with it. A blessing on a thing carried saves it.
    private def put_out(scroll : Item) : Nil
      doused = douse_fixtures scroll
      doused += douse_piles scroll
      doused += douse_carried scroll
      darkened = unglow

      if doused.zero? && darkened.zero?
        say "The dark here is already as deep as it goes."
        keep_scroll scroll
        return
      end

      said = scroll.cursed? ? "The light is eaten, and what held it with it." : "The light goes out."
      say said
      keep_scroll scroll
    end

    # Puts a blessed scroll of darkness back in the pack, half the time.
    #
    # It is the only scroll that survives being read. `#use` has already
    # taken it out, so this puts it back rather than holding it there.
    private def keep_scroll(scroll : Item) : Nil
      return unless scroll.blessed?
      return unless draught.rand(100) < DARKNESS_KEPT
      return unless @player.inventory.add scroll

      say "The writing is still on it."
    end

    # Whether *x*, *y* is near enough for the scroll to reach.
    private def near?(x : Int32, y : Int32) : Bool
      Notice.within? @player.at, {x, y}, DARKNESS
    end

    # Puts out the sconces in reach. A cursed scroll takes them off the wall.
    private def douse_fixtures(scroll : Item) : Int32
      doused = 0
      broken = [] of {Int32, Int32}

      floor.each_fixture do |column, row, fitting|
        next unless near? column, row
        next unless fitting.lit?

        fitting.douse
        doused += 1
        broken << {column, row} if scroll.cursed?
      end

      broken.each { |spot| floor.set_fixture spot[0], spot[1], nil }
      doused
    end

    # Puts out what is burning on the floor in reach.
    private def douse_piles(scroll : Item) : Int32
      doused = 0
      burned = [] of {Int32, Int32, Item}

      floor.each_pile do |column, row, pile|
        next unless near? column, row

        pile.each do |item|
          next unless item.lit?

          item.douse
          doused += 1
          burned << {column, row, item} if scroll.cursed?
        end
      end

      burned.each { |column, row, item| floor.take column, row, item }
      doused
    end

    # Puts out what the character is carrying.
    #
    # A cursed scroll burns those up as well, and a blessing on one saves it.
    # Nothing saves what is lying on the floor: a blessing holds a thing to
    # its owner, and a thing on the floor has none.
    private def douse_carried(scroll : Item) : Int32
      doused = 0
      burned = [] of {Char, Item}

      @player.inventory.items.each do |letter, item|
        next unless item.lit?

        item.douse
        doused += 1
        burned << {letter, item} if scroll.cursed? && !item.blessed?
      end

      burned.each do |letter, item|
        say "#{name(item).capitalize} burns away to nothing."
        @player.inventory.relocate letter, item
        @player.inventory.strip letter, item
        @player.inventory.remove letter if @player.inventory[letter].try(&.same? item)
        @player.equipment.clean @player.inventory
      end

      doused
    end

    # Takes the glow off every square in reach. Answers how many went dark.
    private def unglow : Int32
      wanted = [] of {Int32, Int32}
      floor.each_glow do |column, row, _level|
        wanted << {column, row} if near? column, row
      end

      wanted.each { |spot| floor.set_glow spot[0], spot[1], 0 }
      wanted.size
    end

    # ----------------------------------------------------------- blindness

    # How many turns a cursed scroll of blindness takes the character's sight
    # away for.
    BLINDING = Dice.new 2, 6

    # How many turns it takes a creature's sight away for.
    CREATURE_BLINDING = Dice.new 3, 6

    # Blinds what the scroll is aimed at.
    #
    # A cursed one blinds the reader. A blessed one blinds everything they
    # can see. An uncursed one blinds the creature on *target*.
    private def blind_with(scroll : Item, target : {Int32, Int32}?) : Nil
      stream = draught
      return blind_myself stream if scroll.cursed?
      return blind_everything stream if scroll.blessed?

      creature = target ? floor.monster(target[0], target[1]) : nil
      unless creature
        say "The dark settles on nothing."
        return
      end

      blind_creature creature, stream
    end

    # Takes the character's own sight away.
    private def blind_myself(stream : Rng) : Nil
      @player.blind BLINDING.roll(stream)
      say "The dark closes over your eyes."
    end

    # Blinds every creature in sight.
    private def blind_everything(stream : Rng) : Nil
      seen = monsters_in_sight
      if seen.empty?
        say "The dark settles on nothing."
        return
      end

      seen.each { |creature| blind_creature creature, stream }
    end

    # Takes one creature's sight away.
    private def blind_creature(creature : Monster, stream : Rng) : Nil
      creature.blind CREATURE_BLINDING.roll(stream)
      say "The #{creature.label} claws at its eyes."
    end

    # ------------------------------------------------------------ teleport

    # The nearest a scroll of minor teleport will put the character.
    TELEPORT_LEAST = 15

    # Puts the character somewhere else on this floor.
    #
    # An uncursed one picks a square at random, no nearer than
    # `TELEPORT_LEAST`. A blessed one goes where they chose. A cursed one
    # puts them beside whatever on the floor is worth the most experience.
    private def teleport_with(scroll : Item, target : {Int32, Int32}?) : Nil
      return teleport_to_trouble if scroll.cursed?

      if scroll.blessed?
        return arrive_at target if target && standable? target

        say "The writing fades with nowhere to go."
        return
      end

      spots = teleport_spots
      if spots.empty?
        say "The writing fades with nowhere to go."
        return
      end

      arrive_at spots.sample(draught)
    end

    # Whether the character could stand on *spot*.
    private def standable?(spot : {Int32, Int32}) : Bool
      floor.passable?(spot[0], spot[1]) && !floor.monster?(spot[0], spot[1])
    end

    # Every square a scroll of minor teleport would put the character on.
    private def teleport_spots : Array({Int32, Int32})
      found = [] of {Int32, Int32}

      floor.each do |column, row, tile|
        next unless tile.terrain.passable?
        next unless standable?({column, row})
        next if Notice.within? @player.at, {column, row}, TELEPORT_LEAST - 1

        found << {column, row}
      end

      found
    end

    # Puts the character beside the strongest thing on the floor.
    private def teleport_to_trouble : Nil
      worst = nil.as Monster?
      floor.each_monster do |_column, _row, creature|
        worst = creature if worst.nil? ||
                            creature.species.experience > worst.species.experience
      end

      unless worst
        say "The writing fades with nothing to fear."
        return
      end

      beside = Direction.values.map(&.from(worst.x, worst.y))
        .find { |spot| standable? spot }

      unless beside
        say "The writing fades with nowhere to go."
        return
      end

      arrive_at beside
      say "Something large is standing right there."
    end

    # Puts the character on *spot* and looks around.
    private def arrive_at(spot : {Int32, Int32}) : Nil
      @player.move_to spot
      say "The floor lurches, and you are somewhere else."
      arrived
    end

    # Writes *item* down at *column*, *row* without claiming anything else
    # about the square.
    #
    # The terrain goes in because a `Memory` holds one, and something lying
    # on a square says the square can be walked on whatever else it is. What
    # is already remembered wins, so a scroll never rewrites a square the
    # character has looked at.
    private def detect(column : Int32, row : Int32, item : Item) : Nil
      held = @player.knowledge[column, row]
      @player.knowledge.remember column, row,
        Memory.new(held.try(&.terrain) || floor.terrain(column, row),
          held.try(&.fixture), item.copy, held.try(&.turn) || @turn)
    end

    # ------------------------------------------------- blessing and uncursing

    # How often in a hundred a cursed scroll looks at everything carried
    # rather than at what it could change.
    STRAY = 25

    # What a scroll of blessing or of remove curse does.
    #
    # An uncursed one marks what a god has touched and then works on the one
    # item the character picked. A blessed one marks and works on everything
    # carried and everything lying underfoot. A cursed one marks nothing and
    # picks its own target, which it often cannot change at all.
    private def anoint(scroll : Item, choice : Char?) : Nil
      return anoint_astray scroll if scroll.cursed?

      mark_for scroll

      if scroll.blessed?
        anoint_all scroll
      else
        anoint_one scroll, choice
      end
    end

    # Reveals the blessing on everything within the scroll's reach that has
    # one.
    #
    # A scroll of blessing shows what a god has touched either way. A scroll
    # of remove curse shows only the curses. An uncursed item is left
    # unmarked, which says what it is to anybody counting.
    private def mark_for(scroll : Item) : Int32
      marked = 0

      within(scroll).each do |letter, item|
        next if item.blessing_known?
        next unless scroll.kind.effect.remove_curse? ? item.cursed? : !item.blessing.uncursed?

        marked += 1
        letter ? learned(letter, item) : item.reveal_blessing
      end

      say marked > 0 ? "Marks appear on #{marked} of them." : "No marks appear."
      marked
    end

    # Everything the scroll reaches, by letter.
    #
    # A blessed scroll reaches what is lying on the character's own square as
    # well, and those have no letter.
    private def within(scroll : Item) : Array({Char?, Item})
      found = [] of {Char?, Item}
      @player.inventory.each_item { |letter, item| found << {letter.as(Char?), item} }
      return found unless scroll.blessed?

      floor.items(@player.x, @player.y).each { |item| found << {nil.as(Char?), item} }
      found
    end

    # Whether *item* is something this scroll could change.
    private def changes?(scroll : Item, item : Item) : Bool
      scroll.kind.effect.remove_curse? ? item.cursed? : !item.blessed?
    end

    # Does what the scroll does to *item*. Answers whether anything changed.
    private def anoint_it(scroll : Item, item : Item) : Bool
      scroll.kind.effect.remove_curse? ? item.uncurse : item.bless
    end

    # A blessed scroll, which works on everything it reaches.
    private def anoint_all(scroll : Item) : Nil
      changed = 0

      within(scroll).each do |letter, item|
        next unless anoint_it scroll, item

        changed += 1
        settle letter, item if letter
      end

      if changed.zero?
        say "There was nothing here for it to do."
        return
      end

      say "#{changed} of them are #{anointed scroll}."
    end

    # What a scroll leaves something as.
    private def anointed(scroll : Item) : String
      scroll.kind.effect.remove_curse? ? "free of a curse" : "blessed"
    end

    # The same, for a line that is still running on.
    private def lifts(scroll : Item) : String
      scroll.kind.effect.remove_curse? ? "lifts a curse" : "blesses it"
    end

    # An uncursed scroll, which works on the one item the character picked.
    private def anoint_one(scroll : Item, choice : Char?) : Nil
      item = choice ? @player.inventory[choice] : nil
      unless item && choice
        say "The writing fades with nothing to settle on."
        return
      end

      told = name item
      unless anoint_it scroll, item
        say "Nothing about #{told} changes."
        return
      end

      say "#{told.capitalize} is #{anointed scroll}."
      settle choice, item
    end

    # A cursed scroll, which picks its own target.
    #
    # Three times in four it picks among the things it could change. The
    # fourth time it picks among everything carried, and lands often enough
    # on something it does nothing to.
    private def anoint_astray(scroll : Item) : Nil
      stream = draught
      carried = @player.inventory.items
      wanted = carried.select { |_letter, item| changes? scroll, item }

      pool = stream.rand(100) < STRAY || wanted.empty? ? carried : wanted
      if pool.empty?
        say "The writing fades with nothing to settle on."
        return
      end

      letter, item = pool[stream.rand pool.size]
      picked = "The scroll picks out #{letter}, #{name item}"

      unless anoint_it scroll, item
        say "#{picked}, to no effect."
        return
      end

      say "#{picked}, and #{lifts scroll}."
      settle letter, item
    end

    # Records that the character has found out what *kind* is, and says so.
    #
    # Every effect in this phase is one somebody watching would understand,
    # so using an item names its kind. A potion that did nothing visible
    # would not, and this is where that exception goes when there is one.
    private def found_out(kind : ItemKind) : Nil
      return unless @lore.learn kind

      say "It was #{name Item.new(kind)}."
    end

    # Puts hit points back.
    private def mend(item : Item) : Nil
      rolled = item.kind.power.roll draught
      strength = Math.max rolled * item.blessing.potency // 100, 1
      put_back = @player.heal strength

      say put_back > 0 ? "You feel better." : "You feel no different."
    end

    # Names the carried item under *choice*, and whether it is cursed.
    private def name_one(choice : Char?) : Nil
      item = choice ? @player.inventory[choice] : nil
      unless item && choice
        say "You feel knowledgeable, and the feeling passes."
        return
      end

      news = @lore.learn item.kind
      learned choice, item

      say news ? "It is #{name item}." : "You knew that already. It is #{name item}."
    end

    # Writes the shape of the whole floor into what the character remembers.
    #
    # The shape and no more. `Knowledge#touch` records the terrain and what
    # is fixed to it, and keeps whatever item was already remembered there.
    private def map_the_floor : Nil
      floor.each do |column, row, _tile|
        next unless wall? column, row

        @player.knowledge.touch floor, column, row, @turn
      end

      say "The shape of the floor comes to you."
    end

    # Whether *x*, *y* is rock with something walkable beside it.
    #
    # The walls of the rooms and the corridors, and not the rock behind them.
    # Deep rock is not a wall, and a map that wrote it down would be a map of
    # the whole floor drawn in one colour.
    private def wall?(x : Int32, y : Int32) : Bool
      return false unless floor.terrain(x, y).rock?

      Direction.values.any? do |direction|
        beside = direction.from x, y
        floor.passable? beside[0], beside[1]
      end
    end

    # How far a wand of light makes the floor glow.
    GLOW = 6

    # Makes the squares round the character glow for good.
    #
    # Only the passable ones. A glowing square spills onto every neighbour,
    # so the walls of the room light up the way they do round a magically lit
    # room. Setting the glow on the walls as well would light what is behind
    # them.
    private def light_up : Nil
      thrown = Lighting.from floor, LightSource.new(@player.x, @player.y, GLOW,
        LightKind::Glimmer)

      thrown.levels.each do |spot, level|
        next unless level > 0
        next unless floor.passable? spot[0], spot[1]

        floor.set_glow spot[0], spot[1], Math.max(floor.glow_at(spot[0], spot[1]), level)
      end

      say "Light floods out and stays."
    end

    # Sends a bolt at *target*.
    #
    # It flies the way an arrow flies and stops at the first thing in the
    # line. Nothing is left on the floor afterwards.
    private def bolt(item : Item, target : {Int32, Int32}?) : Nil
      unless target
        say "The bolt goes nowhere."
        return
      end

      shot = flight target, item.kind.reach
      spot = shot.at
      struck = floor.monster spot[0], spot[1]

      unless struck
        say "The bolt strikes the #{floor.terrain(spot[0], spot[1]).label}."
        return
      end

      hit struck, "bolt", @player.to_zap, item.kind.power
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

      ready slot, letter, item, slot.readied(name item)
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

      ready slot, letter, item, slot.readied(name item)
    end

    # Puts *letter* in *slot* and says *line*. Always answers true.
    #
    # A cursed item announces itself as it goes on. That is the moment the
    # character finds out, and `#take_off` will refuse to let it go again.
    private def ready(slot : Slot, letter : Char, item : Item, line : String) : Bool
      @player.equipment.put slot, letter
      say line

      if item.sticks? && item.reveal_blessing
        say "#{name(item).capitalize} welds itself to you."
      end

      spend_turn
      true
    end

    # Takes whatever is in *slot* off. Answers whether it came off.
    def take_off(slot : Slot) : Bool
      item = @player.in_slot slot
      unless item
        say slot.vacant
        return false
      end

      if item.sticks? && !dormant?(item)
        item.reveal_blessing
        say "You cannot let go of #{name item}."
        return false
      end

      @player.equipment.clear slot
      say slot.released(name item)
      spend_turn
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
