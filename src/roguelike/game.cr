require "json"
require "./apply"
require "./combat"
require "./equipment"
require "./field_of_view"
require "./floors"
require "./lighting"
require "./line"
require "./vision"
require "./items"
require "./loot"
require "./lore"
require "./message_log"
require "./notice"
require "./pursuit"
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

    # How many swings have been rolled in this run.
    #
    # This names the generator for the next one. See `#exchange`.
    getter blows : Int32

    # What has just happened.
    getter log : MessageLog

    # What this run's items look like, and which of them the character has
    # found out.
    getter lore : Lore

    # The run's root generator, built from the world's seed.
    #
    # This is not written out. `World#seed` is, and this is a function of it.
    @[JSON::Field(ignore: true)]
    @root : Rng? = nil

    def initialize(@world : World, @player : Player, @turn : Int32 = 0,
                   @outcome : Outcome = Outcome::Playing,
                   @log : MessageLog = MessageLog.new,
                   @lore : Lore = Lore.new,
                   @blows : Int32 = 0)
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
    #
    # The character starts with a lit torch. A dungeon is dark, and a person
    # who arrived with no light would see one square and nothing else.
    def self.start(rng : Rng) : Game
      world = World.on rng
      floor = world.add Floors.proving_ground

      player = Player.new floor.id, *entrance(floor)
      player.inventory.add Item.new(ItemKind::Torch, lit: true)

      game = new world, player, lore: Lore.roll(rng)
      game.scatter rng
      game.equip rng
      game.say "You are in a dungeon, holding a lit torch. Press ? for the keys."
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

    # Records what the character has just had their hands on.
    #
    # A door they opened or shut, a sconce they lit or put out. `#look` picks
    # up whatever they can see, and in the dark that is one square. Somebody
    # who has just shut a door knows it is shut whether or not they can see
    # it, and the map has to say so rather than going on showing what was
    # there the last time there was light on it.
    #
    # It records the shape of the square and what is fixed to it, and not
    # what is lying on the floor. Working a door latch says nothing about
    # what is under your feet on the far side of it.
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

      wake creature if creature.alive?
      spend_turn
      blow
    end

    # Takes *creature* off the floor and awards its experience.
    #
    # Whatever it was carrying lands on the square it died on. A lit torch
    # goes on burning there, which is how a fight in a dark corridor leaves a
    # light behind it.
    private def kill(creature : Monster) : Nil
      floor.remove creature.x, creature.y
      creature.drop_everything.each do |item|
        floor.drop creature.x, creature.y, item
      end
      say "You kill the #{creature.label}."

      gained = @player.gain creature.species.experience
      say "Welcome to level #{@player.level}." if gained > 0
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
    # members. The band searches. The creatures walk downhill.
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
        blocked: standing_on_squares(creature))
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
    # This is where a decision meets what is actually there. A creature that
    # decided to walk into a wall walks nowhere and a creature that decided
    # to swing at an empty square swings at nothing.
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
        character_died unless @player.alive?
      else
        say "The #{creature.label} misses you."
      end

      blow
    end

    # Ends the run. The character has been killed.
    private def character_died : Nil
      @outcome = Outcome::Died
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

    # How many turns a band goes on looking after it has lost the character.
    #
    # It walks to the square it last saw them on, and then casts about there
    # until this runs out.
    PATIENCE = 10

    # Whether the trail *band* is following has gone cold.
    private def cold?(band : Band) : Bool
      seen = band.knowledge(floor.id).sighting Knowledge::PLAYER
      return true unless seen

      seen.age(@turn) > PATIENCE
    end

    # *band* stops looking and goes back to sleep.
    #
    # What it learned of the floor stays. Where it last saw the character
    # does not: a band that wakes again looks for them where it finds them,
    # not where they were half a dungeon ago.
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
    # What it is standing on it knows whole, items and all. What is beside it
    # it knows the shape of and no more. Reaching out in the dark tells a
    # creature there is a wall there. It does not tell it there is a sword on
    # the floor.
    private def feel(knowledge : Knowledge, x : Int32, y : Int32) : Nil
      knowledge.see floor, x, y, @turn

      Direction.values.each do |direction|
        spot = direction.from x, y
        knowledge.touch floor, spot[0], spot[1], @turn
      end
    end

    # Which bands notice the character, and which of their creatures did.
    #
    # One creature is enough to wake a band. The first one found is the one
    # named in the message.
    private def noticing(seen : Vision) : Hash(String, Monster)
      light = seen.light @player.x, @player.y
      stealth = @player.attributes.stealth
      found = {} of String => Monster

      floor.each_monster do |column, row, creature|
        next if found.has_key? creature.band
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

    # Opens the door *direction*. Answers whether it opened.
    #
    # Opening takes a turn. Trying to open something that is not a shut door
    # takes none.
    def open(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return false unless floor.tile?(wanted[0], wanted[1]).try &.terrain.closed_door?

      floor.set wanted[0], wanted[1], Terrain::OpenDoor
      handled wanted
      say "You open the door."
      spend_turn
      true
    end

    # Closes the door *direction*. Answers whether it closed.
    def close(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return false unless floor.tile?(wanted[0], wanted[1]).try &.terrain.open_door?

      floor.set wanted[0], wanted[1], Terrain::ClosedDoor
      handled wanted
      say "You close the door."
      spend_turn
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

    # What the character can see from where they stand.
    #
    # This is worked out again every time it is asked for. It depends on where
    # the character stands, on which doors are open, and on what is alight,
    # and all of those change often enough that a cache would need
    # invalidating from a dozen places. One cast over the shipped floor
    # touches a few hundred squares. A cache goes in when a profile asks for
    # one.
    def sight : Vision
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
      seen = sight
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
        say "You pick up #{item.count} gold pieces."
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

    # Picks up everything on the square. Answers how many entries were taken.
    def pick_up_all : Int32
      taken = 0

      here.dup.each do |item|
        break if over?

        taken += 1 if pick_up item
      end

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
      say "You drop #{name item}."
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
        say "You have nothing #{slot.armour? ? "on your" : "in your"} #{slot.label}."
        return false
      end

      if item.sticks?
        item.reveal_blessing
        say "You cannot let go of #{name item}."
        return false
      end

      @player.equipment.clear slot
      say "You are no longer #{slot.armour? ? "wearing" : "holding"} #{name item}."
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
