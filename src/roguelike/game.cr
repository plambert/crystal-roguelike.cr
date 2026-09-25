require "json"
require "./action"
require "./apply"
require "./combat"
require "./costs"
require "./effect"
require "./event"
require "./equipment"
require "./field_of_view"
require "./fingerprint"
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
require "./replay/log"
require "./route"
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

    # What has just happened, as values.
    #
    # One event for every line `#say` wrote, oldest first. `#perform` empties
    # the list before it dispatches, so this holds what one action did. A
    # caller that reaches a rule without going through `#perform` sees the
    # events pile up until the next one.
    #
    # It is not written out. A save holds where a run is rather than what the
    # last action did.
    @[JSON::Field(ignore: true)]
    getter events : Array(Event) = [] of Event

    # What this run's items look like, and which of them the character has
    # found out.
    getter lore : Lore

    # What killed the character. `nil` while they are alive.
    #
    # The label rather than the creature. The end screen names what killed
    # them, and a creature held here would be a second copy of one the floor
    # already holds.
    getter killer : String? = nil

    # How many turns the sidebar goes on showing the creature the character
    # last traded blows with.
    #
    # Eight. A creature that breaks off and comes back inside eight turns is
    # the same fight, and eight turns is long enough to walk the width of a
    # lit room, so one that has not swung in that time is somewhere else.
    # Eight is also what a goblin and an orc notice at, so the bar holds for
    # about as long as the creature would need to close again.
    FIGHT_LASTS = 8

    # The creature the character last traded blows with.
    #
    # This is not written out. A creature held here would be a second copy of
    # one the floor already holds, which is why `#killer` holds a label
    # rather than a creature. `#fought_at` names it in the save instead, and
    # `#after_initialize` finds it again.
    @[JSON::Field(ignore: true)]
    @fought : Monster? = nil

    # Where that creature stood when the turn last ended.
    #
    # Two creatures never share a square, so a square names one creature on
    # the floor the character is on. `#tick` writes this again every turn, so
    # it still names the creature after it has walked.
    #
    # It has a default, so a save written before this field existed loads
    # with no fight going.
    getter fought_at : {Int32, Int32}? = nil

    # The turn the last blow either way was struck on.
    #
    # It has a default, so a save written before this field existed loads at
    # turn zero, which `FIGHT_LASTS` turns are long past by the time anything
    # reads it.
    getter fought_turn : Int32 = 0

    # How well the character has made that creature out.
    #
    # It keeps the best look the character has had of it, the way a square
    # keeps the closer of two looks. A creature seen in the light is the same
    # creature once it steps into the dark, so the bar goes on naming it.
    #
    # It has a default, so a save written before this field existed loads
    # with nothing made out.
    getter fought_regard : Regard = Regard::Nothing

    # The last thing to cross the floor, for whatever draws one.
    #
    # Every command that might send something across the floor clears this
    # first. A command that sent nothing then gives `nil` rather than the
    # shot before it. `Ui::Play` reads it once the command is over.
    #
    # It is not written out. A save holds where a run is rather than what
    # the screen last showed.
    @[JSON::Field(ignore: true)]
    getter in_flight : Missile? = nil

    # The run's root generator, built from the world's seed.
    #
    # This is not written out. `World#seed` is, and this is a function of it.
    @[JSON::Field(ignore: true)]
    @root : Rng? = nil

    # Whether the step just taken ended on an item the character did not
    # remember.
    #
    # `#announce_pile` sets it from the character's own map, one step at a
    # time. A walk stops on it. Somebody who set a walk going across a square
    # with a dagger drawn on it is not surprised by the dagger, and the map
    # is where that is written down.
    @[JSON::Field(ignore: true)]
    @discovery : Bool = false

    # How many lines the step just taken wrote about a pile the character
    # already remembered.
    #
    # `#told?` subtracts these before it decides whether the walk heard
    # anything worth stopping for.
    @[JSON::Field(ignore: true)]
    @forgiven : Int32 = 0

    def initialize(@world : World, @player : Player, @turn : Int32 = 0,
                   @outcome : Outcome = Outcome::Playing,
                   @log : MessageLog = MessageLog.new,
                   @lore : Lore = Lore.new,
                   @blows : Int32 = 0,
                   @uses : Int32 = 0,
                   @wanders : Int32 = 0)
    end

    # Finds the creature the character was fighting again after a load.
    #
    # The save holds the square it stood on rather than the creature itself.
    # Two creatures never share a square, so the square names it. A square
    # with nobody on it means the creature died or the character went
    # somewhere else while the save was cold, and the fight is over either
    # way.
    def after_initialize : Nil
      spot = @fought_at
      @fought = spot ? floor.monster(spot[0], spot[1]) : nil
      enrol
    end

    # What *item* is called, as this character would call it.
    #
    # *regard* says how well they have made it out. The default makes
    # everything out, which is what the pack and every menu mean: the
    # character is holding the thing.
    #
    # *blessing* false leaves the blessing word out, for a readout that
    # gives the blessing some other way.
    def name(item : Item, regard : Regard = Regard::Everything,
             blessing : Bool = true) : String
      @lore.name item, blessing: blessing, regard: regard
    end

    # What everything under *letter* is called, counted together.
    #
    # A letter holding twelve arrows and three more that differ only in a
    # hidden curse is "15 arrows". The character cannot tell them apart, so
    # neither does the line that names them.
    def name_under(letter : Char) : String
      item = carried letter
      return "nothing" unless item

      @lore.name item
    end

    # Everything under *letter* as one item, counted together.
    #
    # A letter holding twelve arrows and three more that differ only in a
    # hidden curse gives one stack of fifteen. A list is about this stack
    # rather than about the first item under the letter.
    def carried(letter : Char) : Item?
      item = @player.inventory[letter]
      return unless item

      item.with_count @player.inventory.count letter
    end

    # Adds *line* to the log and *event* to `#events`.
    #
    # The event is kept whatever the log does with the line. `MessageLog#add`
    # drops a line identical to the one before it, because a wall bumped ten
    # times reads better as one line. Two bumps are still two things that
    # happened, so both events are kept.
    def say(line : String, event : Event) : Nil
      @log.add line
      event.text = line
      record event
    end

    # Adds *event* to `#events` with no line beside it.
    #
    # Two endings use this. Climbing out and reaching the staircase down both
    # end the run and write nothing to the log. `bots/PROTOCOL.md` section 5.2
    # asks for one event per ending, and a client that saw two of the three
    # would have to work the third out from the outcome.
    private def record(event : Event) : Nil
      @events << event
    end

    # Whether the run is over.
    def over? : Bool
      @outcome.over?
    end

    # What this run is, as one string. See `Fingerprint`.
    #
    # The same state gives the same string in every process. A replay is
    # checked by comparing this turn by turn. Two runs that differ show the
    # turn they first differed on.
    def fingerprint : String
      Fingerprint.of self
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
      game.enrol
      # Two lines rather than one. The log pane is four rows of about eighty
      # columns, and one sentence saying all of this wraps onto two of them.
      #
      # They go to the log rather than through `#say`. Nothing has happened
      # yet. The first line names what the character is holding, which the
      # pack already lists, and the second is about the keyboard.
      game.log.add "You are in a dungeon with a short sword, leather armour and a lit torch."
      game.log.add "You carry three iron spikes. Press ? for the keys."
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
    #
    # Every one of them is known to be uncursed. The character has owned them
    # long enough to be sure of them. A handling roll on their own kit would
    # teach the player nothing.
    private def self.outfit(player : Player) : Nil
      {
        {Item.new(ItemKind::ShortSword, blessing_known: true), Slot::Melee},
        {Item.new(ItemKind::LeatherArmour, blessing_known: true), Slot::Body},
      }.each do |item, slot|
        letter = player.inventory.add item
        player.equipment.put slot, letter if letter
      end

      player.inventory.add Item.new(ItemKind::Torch, lit: true,
        blessing_known: true)
      player.inventory.add Item.new(ItemKind::Spike, count: SPIKES,
        blessing_known: true)
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
      @discovery = false
      @forgiven = 0
      wanted = direction.from @player.x, @player.y

      blocking_creature = floor.monster wanted[0], wanted[1]
      if blocking_creature
        attack blocking_creature
        return Step::Struck
      end

      if floor.tile?(wanted[0], wanted[1]).try &.terrain.closed_door?
        floor.set wanted[0], wanted[1], Terrain::OpenDoor
        handled wanted
        say "You open the door.", Event::Door.new(wanted, open: true)
        spend_turn
        return Step::Opened
      end

      unless floor.passable? wanted[0], wanted[1]
        refuse_step direction
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

    # How many squares one walk crosses before it stops on its own.
    #
    # A walk moves in one direction, so it reaches the edge of any floor well
    # inside this. The number is here so that a bug elsewhere cannot leave a
    # walk turning the crank forever.
    FURTHEST = 60

    # A walk in progress, and how far it has got.
    #
    # `Game#stride` takes one step of one of these. `#run` and `#follow` build
    # one and step it until it stops, which is what a spec and the trial
    # harness want. `Ui::Play` steps it on a timer instead, so the screen is
    # drawn between one step and the next and a key can stop it.
    #
    # A walk holds no floor and decides nothing. `Game` is still the one class
    # that changes a run.
    class Walk
      # The squares to cross, the character's own first. `nil` for a walk in
      # one direction.
      getter route : Array({Int32, Int32})?

      # Which way a walk in one direction goes. `nil` for a route.
      getter direction : Direction?

      # How far it has gone.
      property steps : Int32 = 0

      # Why it stopped. `nil` while it is still going.
      property halt : Halt? = nil

      # Whether the square last stepped from was a length of corridor.
      property? along : Bool = false

      # What could be seen before the step being taken.
      property seen : Vision

      def initialize(@seen : Vision,
                     @direction : Direction? = nil,
                     @route : Array({Int32, Int32})? = nil,
                     @along : Bool = false)
      end

      # Whether this is a walk in one direction rather than along a route.
      #
      # A doorway and a junction stop the first and not the second. The
      # person who picked a square picked one on the far side of both.
      def straight? : Bool
        @route.nil?
      end

      # Whether it has stopped.
      def over? : Bool
        !@halt.nil?
      end

      # What it did, for a caller that wanted the whole walk at once.
      def running : Running
        Running.new @steps, @halt || Halt::Spent
      end
    end

    # A walk in *direction*, ready to be stepped.
    def running(direction : Direction) : Walk
      Walk.new sight, direction: direction, along: corridor?(@player.at)
    end

    # A walk along *route*, ready to be stepped.
    #
    # A route that does not start where the character stands is refused. So is
    # one with nowhere to go.
    def walking(route : Array({Int32, Int32})) : Walk
      walk = Walk.new sight, route: route
      walk.halt = Halt::Blocked if route.size < 2 || route.first != @player.at

      walk
    end

    # Takes one step of *walk*. Answers whether it is still going.
    #
    # Everything one step needs to know about the step before it is on the
    # walk. Nothing about it is kept on the game, so a walk that is abandoned
    # part way leaves nothing behind.
    #
    # A run that is over takes no step. The blow that follows the last step
    # can kill the character, and the run ends there. `#wait` takes no turn
    # once they are dead, for the same reason.
    def stride(walk : Walk) : Bool
      return false if over?
      return false if walk.over?

      direction = heading walk
      return false unless direction

      @discovery = false
      @forgiven = 0

      if blocked_ahead? direction
        refuse_run direction if walk.steps.zero?
        walk.halt = Halt::Blocked
        return false
      end

      # The step goes through `#perform` rather than straight to `#step`. A
      # walk is a series of steps. `bots/PROTOCOL.md` section 2 says a macro
      # is logged as the primitive actions it expands into. A replay log and
      # a bot both read `#perform`. A walk that reached `#step` directly would
      # replay as a character standing still.
      #
      # The verdict always carries a step. `#perform` refuses a move only for
      # a run that is over, and the guard at the top of this method has
      # already covered that. `as` is used rather than a fallback to nil, so
      # a refusal that did reach here raises. A fallback would read as "did
      # not move" and would put a wrong `Halt::Blocked` on the walk.
      before = Watch.on self, walk.seen
      unless perform(Action::Move.new(direction)).step.as(Step).moved?
        walk.halt = Halt::Blocked
        return false
      end

      walk.steps += 1
      walk.seen = sight
      walk.halt = stopped_by before, walk.seen,
        along: walk.along?, doors: walk.straight?
      walk.along = walk.straight? && corridor?(@player.at)

      !walk.over?
    ensure
      @discovery = false
      @forgiven = 0
    end

    # Which way the next step of *walk* goes.
    #
    # `nil` when there is no step to take, and the walk is given the reason
    # before this answers.
    private def heading(walk : Walk) : Direction?
      route = walk.route
      unless route
        walk.halt = Halt::Spent if walk.steps >= FURTHEST

        return walk.over? ? nil : walk.direction
      end

      if walk.steps + 1 >= route.size
        walk.halt = Halt::Arrived
        return
      end

      found = Direction.between @player.at, route[walk.steps + 1]
      walk.halt = Halt::Blocked unless found

      found
    end

    # Walks *direction* until something is worth stopping for. Answers how
    # far it went and what stopped it.
    #
    # Every step is a whole turn, so every other creature on the floor acts
    # between one step and the next, and a walk is as dangerous as walking the
    # same squares one key at a time.
    #
    # A walk never attacks and never opens a door. Either one is a decision,
    # and a walk makes none: it stops in front of a creature or a shut door
    # and leaves the decision to the person.
    #
    # A walk that takes no step at all says why, the way one press of the
    # movement key against the same square would.
    def run(direction : Direction) : Running
      walk = running direction
      while stride walk
      end

      walk.running
    end

    # Walks *route* until something is worth stopping for. Answers how far it
    # went and what stopped it.
    #
    # *route* is the squares to cross, the one the character stands on first.
    # `Route.chosen` answers one of these. Every step is a whole turn, the
    # same as `#run`, so a route is as dangerous as walking it a key at a
    # time.
    #
    # A doorway and a junction do not stop a route. The person picked a
    # square on the far side of both, and a route that stopped at every door
    # between here and there would be a key press a door. What stops it is
    # what they had not seen when they picked: a creature arriving, a blow
    # landing, a message about something they did not know was there.
    #
    # A route onto a square something has since walked onto stops against it,
    # the way a walk does.
    def follow(route : Array({Int32, Int32})) : Running
      walk = walking route
      while stride walk
      end

      walk.running
    end

    # Whether the character remembers something lying on the square they
    # stand on.
    #
    # What they remember rather than what is there. A dagger dropped on a
    # square they walked past yesterday is not on their map, so a walk stops
    # when they find it. A dagger they looked at two steps ago is on their
    # map, and a walk crosses it.
    private def pile_in_mind? : Bool
      !knowledge[@player.at].try(&.item).nil?
    end

    # Says why a walk went nowhere.
    #
    # A creature in the way is named when the character can see it. One they
    # cannot see is not: they have walked into something and do not know
    # what. Anything else is the sentence a plain step writes.
    private def refuse_run(direction : Direction) : Nil
      wanted = direction.from @player.x, @player.y
      creature = floor.monster wanted[0], wanted[1]
      return refuse_step direction unless creature

      unless can_see_creature? wanted[0], wanted[1]
        return say "There is something in the way.",
          Event::Blocked.new(direction, unseen: true)
      end

      say "The #{creature.label} is in the way.",
        Event::Blocked.new(direction, creature: creature.id)
    end

    # Whether the square one step *direction* stops a walk.
    #
    # A creature standing there, or anything a character cannot walk onto. A
    # shut door is one of those, so a walk stops in front of it rather than
    # opening it.
    private def blocked_ahead?(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return true if floor.monster wanted[0], wanted[1]

      !floor.passable? wanted[0], wanted[1]
    end

    # What a walk has to compare against to know whether a step changed
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

    # What stopped the walk on this step. `nil` when nothing did.
    #
    # *before* is what `Watch.on` recorded before the step. *along* says
    # whether the square the character stepped from was a length of corridor.
    #
    # Several can hold at once, and the order here is the order a person
    # would name them. A creature coming into sight is usually what wrote the
    # message on the same step, so it is asked about first.
    #
    # Losing hit points stops a walk. Gaining one does not: a character
    # regenerating on the way down a corridor would otherwise stop every
    # twenty steps for good news.
    private def stopped_by(before : Watch, seen : Vision, along : Bool,
                           doors : Bool = true) : Halt?
      return Halt::Over if @outcome.over?
      return Halt::Hurt if @player.hit_points < before.health
      return Halt::Creature if arrived_in_sight? before.seen, seen
      return Halt::Told if told? before
      return Halt::Doorway if doors && standing_on.door?
      return Halt::Branch if along && ways(@player.at).size > CORRIDOR

      nil
    end

    # Whether the step wrote anything worth stopping for.
    #
    # An item the character did not remember counts whatever the log did with
    # the line about it. `MessageLog#add` drops a line identical to the one
    # before it, and the second dagger of a hall writes the same sentence as
    # the first. The log is then the same length, and the item under the
    # character is still one they had not seen.
    #
    # Lines about a pile the character already had on their map do not count.
    # `#announce_pile` counts those into `@forgiven`, and a step whose only
    # new lines are those reads as a step that said nothing.
    private def told?(before : Watch) : Bool
      return true if @discovery

      fresh = @log.size - before.said
      return false if fresh > 0 && fresh == @forgiven

      fresh != 0 || @log.last? != before.last
    end

    # Whether any creature in sight now was out of sight before.
    #
    # A creature that was already in sight when the step began does not stop
    # the walk, or a walk could not be started with one on the screen.
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
    # has two ways off it, at right angles to each other, and a walk along the
    # wall of a room would stop on its first step if that counted.
    #
    # A walk stops when it steps off a corridor square onto a square with more
    # ways off it. A walk that starts anywhere else goes until something else
    # stops it, so a walk leaves a dead end and crosses a room.
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

    # Says why a step did not happen.
    private def refuse_step(direction : Direction) : Nil
      stopped = blocking direction
      unless stopped
        return say "You cannot go that way.", Event::Blocked.new(direction)
      end

      say "The #{stopped.label} blocks your way.",
        Event::Blocked.new(direction, terrain: stopped.label)
    end

    # Says what the character has walked onto, when it is worth saying.
    private def arrived : Nil
      ground = standing_on
      if ground.stairs?
        say "There is #{ground.description} here.",
          Event::Ground.new(@player.at, ground.label)
      end

      take_coins
      take_ammunition
      announce_pile
    end

    # Says what is lying on the square, and records whether a walk has to stop
    # for it.
    #
    # The character's map is read before the line is written. Nothing between
    # the step and this point changes what they remember, so the map here is
    # the map they arrived with.
    #
    # A pile the character already remembered is still named. The walk treats
    # it differently. `#told?` subtracts these lines, so a walk crosses a
    # square whose dagger is on the map and stops on one whose dagger is not.
    private def announce_pile : Nil
      pile = here
      return if pile.empty?

      known = pile_in_mind?
      before = @log.size

      # The whole pile either way. The character is standing on it, so they
      # can pick any of it up, and the pane beside the map lists all of it.
      found = Event::Pile.new @player.at,
        pile.map { |item| Event::Thing.new item.id, name(item) }

      if pile.size == 1
        say "You see #{name pile.first} here.", found
      else
        say "There are #{pile.size} things here.", found
      end

      if known
        @forgiven = @log.size - before
      else
        @discovery = true
      end
    end

    # ------------------------------------------------------------- fighting

    # The creature the character last traded blows with, while the fight is
    # still worth showing.
    #
    # `nil` once the creature has died, once it has left the floor the
    # character is on, and once `FIGHT_LASTS` turns have gone by with no blow
    # either way. The sidebar asks this and draws whatever it answers.
    #
    # A creature that walks out of sight is still answered. The character has
    # just been hitting it and knows it is there, and how hurt it was is
    # worth reading whether or not they can see it now.
    def fought : Monster?
      creature = @fought
      return unless creature && creature.alive?
      return if @turn - @fought_turn >= FIGHT_LASTS

      standing = floor.monster creature.x, creature.y
      return unless standing && standing.same? creature

      creature
    end

    # Writes down that the character and *creature* have traded a blow.
    #
    # Every blow either way comes here, landed or missed. Aiming a swing at
    # something is dealing with it, and a person who has just missed wants to
    # know how much is left in what they missed.
    #
    # A blow at a different creature starts the count again and forgets what
    # was made out of the last one.
    private def fought_with(creature : Monster) : Nil
      held = @fought
      @fought_regard = Regard::Nothing unless held && held.same? creature

      @fought = creature
      @fought_at = creature.at
      @fought_turn = @turn
      @fought_regard = @fought_regard.at_least regard_of(creature)
    end

    # How many squares away the character lands a blow.
    #
    # It comes from the weapon in hand. Bare hands swing 1.
    def melee_reach : Int32
      @player.wielded.try(&.kind.melee_reach) || 1
    end

    # Whether the character can swing at *x*, *y*.
    #
    # A creature stands there, it is within the weapon's reach, and the
    # character can see it. `#legal` offers one action for each such square,
    # `#perform` refuses a swing at any other, and `Ui::Play` turns a step
    # into one of those squares into a swing.
    def melee?(x : Int32, y : Int32) : Bool
      melee? x, y, sight
    end

    # :ditto:, against a field of view that has already been worked out.
    def melee?(x : Int32, y : Int32, seen : Vision) : Bool
      return false unless floor.monster x, y
      return false unless within_reach? x, y

      seen.shows? floor, x, y
    end

    # Whether *x*, *y* is close enough to swing at.
    #
    # The grid takes eight directions, so one square of reach is the eight
    # squares around the character. The distance is the larger of the two
    # gaps for that reason.
    private def within_reach?(x : Int32, y : Int32) : Bool
      Math.max((x - @player.x).abs, (y - @player.y).abs) <= melee_reach
    end

    # The character swings at *creature*. Answers what the swing did.
    #
    # A swing takes a turn whether it lands or not. A creature left at zero
    # hit points is taken off the floor and what killing it is worth is
    # awarded.
    def attack(creature : Monster) : Blow
      fought_with creature
      blow = Combat.swing exchange, @player.to_hit,
        creature.armour_class, @player.damage

      weapon = swung_with
      if blow.hit?
        creature.hurt blow.damage
        say "You hit the #{creature.label} for #{blow.damage}.",
          Event::Attack.new(true, target: creature.id, damage: blow.damage,
            with: weapon)
        kill creature unless creature.alive?
      else
        say "You miss the #{creature.label}.",
          Event::Attack.new(false, target: creature.id, with: weapon)
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
    #
    # It throws the index away itself. A blow reaches it inside `#spend`,
    # which throws the index away anyway. The console reaches it outside
    # `#spend`, because a console command takes no turn, and the index would
    # otherwise go on answering with a creature that is off the floor.
    def kill(creature : Monster) : Nil
      clear_bearers
      floor.remove creature.x, creature.y
      creature.drop_everything.each do |item|
        floor.drop creature.x, creature.y, item
      end
      say "You kill the #{creature.label}.",
        Event::Slain.new(creature.id, creature.label)

      gained = @player.gain creature.species.experience
      return unless gained > 0

      say "Welcome to level #{@player.level}.",
        Event::LevelUp.new(@player.level)
    end

    # What the character is swinging with. `nil` for bare hands.
    private def swung_with : String?
      @player.wielded.try { |item| name item }
    end

    # ------------------------------------------------------------- shooting

    # Why the character cannot shoot. `nil` when they can.
    #
    # `Play` asks this before it puts the targeting cursor up, so a person
    # with an empty quiver is told at once and spends no turn finding out.
    def cannot_fire : String?
      firing_fault.try &.first
    end

    # Why the character cannot shoot, as a line and as a reason. `nil` when
    # they can.
    private def firing_fault : {String, Event::Refused::Reason}?
      ranged_weapon = @player.ranged_weapon
      unless ranged_weapon && ranged_weapon.kind.item_class.ranged_weapon?
        return {"You have nothing readied to shoot with.",
                Event::Refused::Reason::NothingReadied}
      end

      ammunition = @player.quivered
      unless ammunition
        return {"Your quiver is empty.",
                Event::Refused::Reason::QuiverEmpty}
      end
      return if ammunition.kind.ranged_weapon == ranged_weapon.kind

      {"You cannot shoot #{name ammunition} from #{name ranged_weapon}.",
       Event::Refused::Reason::WrongAmmunition}
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
      @in_flight = nil
      fault = firing_fault
      if fault
        say fault[0], Event::Refused.new(fault[1])
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

      say "You shoot #{name one}.",
        Event::Loosed.new(one.id, name(one), target, thrown: false)
      loose one, target, ranged_weapon.kind.reach, bonus, damage
      true
    end

    # Throws what is under *letter* at *target*. Answers whether it went.
    #
    # One of a stack goes. A person carrying twenty darts throws one dart.
    def throw(letter : Char, target : {Int32, Int32}) : Bool
      @in_flight = nil
      item = @player.inventory[letter]
      return false unless item

      slot = slot_of letter
      if slot && item.sticks?
        item.reveal_blessing
        say "You cannot let go of #{name item}.",
          Event::Refused.new(:cursed, item: item.id, name: name(item))
        return false
      end

      if slot && slot.armour?
        say "You have to take #{name item} off first.",
          Event::Refused.new(:worn, item: item.id, name: name(item))
        return false
      end

      bonus = @player.to_throw item
      damage = @player.throw_damage item
      reach = item.kind.reach

      one = draw_one letter
      return false unless one

      say "You throw #{name one}.",
        Event::Loosed.new(one.id, name(one), target, thrown: true)
      loose one, target, reach, bonus, damage
      true
    end

    # Takes one of what is under *letter* out of the inventory.
    #
    # A letter left holding nothing comes out of whatever slot held it. The
    # last arrow empties the quiver.
    private def draw_one(letter : Char) : Item?
      one = @player.inventory.take letter, 1, next_id
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
      @in_flight = Missile.new shot, missile
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
      fought_with creature
      blow = Combat.swing exchange, bonus, creature.armour_class, damage

      if blow.hit?
        creature.hurt blow.damage
        say "The #{noun} hits the #{creature.label} for #{blow.damage}.",
          Event::Attack.new(true, target: creature.id, damage: blow.damage,
            with: noun)
        kill creature unless creature.alive?
      else
        say "The #{noun} misses the #{creature.label}.",
          Event::Attack.new(false, target: creature.id, with: noun)
      end

      wake creature if creature.alive?
      blow
    end

    # Gives every awake creature that has earned an action its turn.
    #
    # Each one reads a `Pursuit::Snapshot` and answers a `Pursuit::Action`,
    # and this method applies it. The snapshot holds no floor and no player.
    # What a creature knows about the shape of the world is its band's
    # `Knowledge`. What it knows about the character is where the band last
    # saw them.
    # Every check against what is actually there happens here.
    #
    # One `Descent` is built for each awake band rather than for each of its
    # members. Every creature in the band reads the same one.
    #
    # The list is taken before any of them acts. A creature that moves would
    # otherwise change the table being walked, and a swing can end the run.
    #
    # It is sorted by square, north to south and west to east. `Floor#walk`
    # takes a creature out of the table and puts it back, so the order it is
    # held in follows what has moved rather than what is there. Two creatures
    # never share a square, so the sort is total and one tick plays out the
    # same way from the same seed.
    private def creatures_act : Nil
      return if over?

      maps = descents
      held = [] of Monster
      floor.each_monster { |_column, _row, creature| held << creature }
      held.sort_by! { |creature| {creature.y, creature.x} }

      held.each do |creature|
        break if over?
        next unless awake? creature

        # A creature that has banked more than one action takes them all
        # here. One at half again the character's speed acts twice on every
        # other tick, which is what being that fast is.
        while creature.pace.ready?
          break if over?
          break unless floor.monster? creature.x, creature.y

          creature.pace.spend Costs::TURN
          perform creature, plan(creature, maps)
        end
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
    private def plan(creature : Monster, maps : Hash(String, Descent)) : Pursuit::Action
      band = floor.band creature.band
      return Pursuit::Action.wait unless band

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
    private def perform(creature : Monster, action : Pursuit::Action) : Nil
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
      fought_with creature
      blow = Combat.swing exchange, creature.to_hit,
        @player.armour_class, creature.damage

      if blow.hit?
        @player.hurt blow.damage
        say "The #{creature.label} hits you for #{blow.damage}.",
          Event::Attack.new(true, attacker: creature.id, damage: blow.damage)
        character_died creature unless @player.alive?
      else
        say "The #{creature.label} misses you.",
          Event::Attack.new(false, attacker: creature.id)
      end

      blow
    end

    # Ends the run. *killer* is the creature that did it.
    private def character_died(killer : Monster) : Nil
      @outcome = Outcome::Died
      @killer = killer.label
      say "You die...",
        Event::Over.new(@outcome, killer: killer.id,
          killer_species: killer.label)
    end

    # Takes one turn for what the character just did.
    #
    # Every action that takes a turn ends with this, after it has said what
    # it did. What the character did is then read before what was done back.
    private def spend_turn : Nil
      spend Costs::TURN
    end

    # Takes *cost* off the character and runs the world on until they can act
    # again.
    #
    # The character pays first and the world catches up after, so one action
    # of theirs is followed by however many actions everything else has
    # earned in that time. A character at normal speed doing a one-tick
    # action gets one tick of world, which is one action from every awake
    # creature at normal speed.
    private def spend(cost : Int32) : Nil
      clear_bearers
      @player.pace.spend cost

      until @player.pace.ready? || over?
        tick
      end
    end

    # One tick of the world.
    #
    # Everything gains its speed in energy, the timers count down, and then
    # every band looks and the awake ones act. A band looks before it acts,
    # so one that notices the character on this tick swings on it.
    private def tick : Nil
      @turn += 1
      wear_off
      handle_items
      blink
      regenerate
      act_on_the_floor unless over?

      # Last, so that nothing acts on energy it earned during the same tick.
      # An actor spends what it came in with and banks what this tick paid
      # it, which is what keeps a normal actor to one action a tick.
      bank_energy

      # After everything has moved, so the square written down is where the
      # creature stands now. A fight that is over is dropped here rather than
      # left to be filtered out on every read.
      held = fought
      @fought = held
      @fought_at = held.try &.at
    end

    # Lets every band look, and the awake ones act.
    private def act_on_the_floor : Nil
      seen = sight
      noticed = creatures_notice seen
      creatures_look seen, noticed
      creatures_act
    end

    # Gives every actor on the floor a tick's worth of energy.
    #
    # A creature whose band is asleep is held at one action's worth instead
    # of banking. It acts on the tick it wakes, and a band that slept for a
    # hundred turns does not wake with a hundred actions in hand.
    private def bank_energy : Nil
      @player.pace.gain

      floor.each_monster do |_column, _row, creature|
        awake?(creature) ? creature.pace.gain : creature.pace.rest
      end
    end

    # How many ticks of going unhurt it takes before regeneration starts.
    REST = 10

    # Regenerates one hit point when the character has gone unhurt long
    # enough.
    #
    # `Player#regeneration` is how many ticks one hit point takes, and it
    # comes from constitution. Regeneration starts after `REST` ticks of
    # going unhurt, whatever the character is made of.
    #
    # Nothing is said. A line a turn saying the character is a little better
    # would fill the log and stop every walk, because anything written to the
    # log stops a walk.
    #
    # Only the character regenerates. A creature that lost the character and
    # healed while it looked for them would undo what hitting it and walking
    # away buys, and that is the one thing a slower creature leaves open.
    private def regenerate : Nil
      rested = @player.rest
      return if rested < REST
      return unless (rested % @player.regeneration).zero?

      @player.heal 1
    end

    # Counts a haste and a slow down one tick, on everything that has one.
    #
    # The character is told when their own runs out. A creature is not: the
    # character has no way to tell a creature that has slowed down from one
    # that is waiting for them.
    private def wear_off : Nil
      hurried = @player.pace.hurried?
      dragging = @player.pace.dragging?
      @player.pace.pass

      if hurried && !@player.pace.hurried?
        say "You slow down again.", Event::StatusEnd.new(:hurried)
      end

      if dragging && !@player.pace.dragging?
        say "Your feet come free.", Event::StatusEnd.new(:dragging)
      end

      floor.each_monster { |_column, _row, creature| creature.pace.pass }
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
          say_noticed creature, seen if woke
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

    # Says that a band has woken up.
    #
    # A creature the character can see is named. One they cannot is not: the
    # character has heard something move and does not know what it was.
    private def say_noticed(creature : Monster, seen : Vision) : Nil
      unless seen.shows? floor, creature.x, creature.y
        return say "You hear something stir.", Event::Noticed.new
      end

      say "The #{creature.label} notices you.",
        Event::Noticed.new(creature.id, creature.label)
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
      say "The #{creature.label} notices you.",
        Event::Noticed.new(creature.id, creature.label)
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
        say "There is nothing to open that way.", Event::Refused.new(:no_door)
        return false
      end

      floor.set wanted[0], wanted[1], Terrain::OpenDoor
      handled wanted
      say "You open the door.", Event::Door.new(wanted, open: true)
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
        say "There is nothing to close that way.", Event::Refused.new(:no_door)
        return false
      end

      blocked = doorway_blocked wanted
      if blocked
        say blocked[0], blocked[1]
        return false
      end

      floor.set wanted[0], wanted[1], Terrain::ClosedDoor
      handled wanted
      say "You close the door.", Event::Door.new(wanted, open: false)
      spend_turn
      true
    end

    # Why the door on *spot* will not shut, as a line and as an event. `nil`
    # when nothing stops it.
    #
    # A creature standing in the doorway is named when the character can see
    # it. One they cannot see is not: they have pushed the door against
    # something and do not know what. Anything lying on the square stops the
    # door the same way.
    private def doorway_blocked(spot : {Int32, Int32}) : {String, Event}?
      creature = floor.monster spot[0], spot[1]
      if creature
        unless can_see_creature? spot[0], spot[1]
          return {"There is something in the doorway.",
                  Event::Refused.new(:doorway_creature)}
        end

        return {"The #{creature.label} is in the doorway.",
                Event::Refused.new(:doorway_creature, creature: creature.id)}
      end

      return unless floor.items? spot[0], spot[1]

      {"Something is lying in the doorway.",
       Event::Refused.new(:doorway_items)}
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
    # costs, and a walk asks this twice a step. A caller with one in hand
    # passes it rather than paying for another.
    def monsters_in_sight(seen : Vision) : Array(Monster)
      found = [] of Monster

      floor.each_monster do |column, row, creature|
        found << creature if seen.shows? floor, column, row
      end

      found
    end

    # How well the character makes *creature* out.
    #
    # `Regard::Everything` for a creature with light on them, which is one
    # the character can name. `Regard::Shape` for one showing against light
    # behind them: a size reaches the character and nothing else does.
    # `Regard::Nothing` for one they cannot see at all.
    def regard_of(creature : Monster) : Regard
      regard_of creature, sight
    end

    # :ditto:, against a field of view that has already been worked out.
    def regard_of(creature : Monster, seen : Vision) : Regard
      x, y = creature.at
      return Regard::Everything if seen.includes? x, y
      return Regard::Shape if seen.backlit? floor, x, y

      Regard::Nothing
    end

    # How well the character makes out the item lying at *x*, *y*.
    #
    # A square they can see is answered by how far off it is: `Regards.of_item`
    # is the rule. A square they cannot see is answered by what they remember
    # of it.
    #
    # A closer look is never undone by a further one. A spear the character
    # has stood over stays a cursed -2 spear while they look back at it from
    # the far wall, and goes back to being a spear only if somebody swaps it
    # for another one.
    def regard_of_item(x : Int32, y : Int32) : Regard
      regard_of_item x, y, sight
    end

    # :ditto:, against a field of view that has already been worked out.
    def regard_of_item(x : Int32, y : Int32, seen : Vision) : Regard
      held = knowledge[x, y]
      return held.try(&.regard) || Regard::Nothing unless seen.includes? x, y

      made_out = Regards.of_item @player.at, {x, y}
      return made_out unless held && held.item == floor.items(x, y).last?

      made_out.at_least held.regard
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
    #
    # An empty one for a floor they have never looked at. It is not kept.
    # Every caller here reads the map and none of them writes to it.
    # `Player#knowledge` is the one that keeps what it makes, and `#look` is
    # the only thing that calls it.
    #
    # A kept empty map would be in the save and in the fingerprint. A verifier
    # that read the map before the first `#look` would then answer a different
    # fingerprint from the run it is checking, for no reason in the run.
    def knowledge : Knowledge
      @player.knowledge? || Knowledge.new @player.floor
    end

    # The route the character would walk to reach *goal*.
    #
    # Empty when they can reach nothing that way. `Route.chosen` says what
    # counts as reaching it.
    def route_to(goal : {Int32, Int32}) : Array({Int32, Int32})
      Route.chosen knowledge, sight, goal
    end

    # The route the character would walk to reach *goal*, without settling
    # for somewhere near it. Empty when they know no way there.
    def way_to(goal : {Int32, Int32}) : Array({Int32, Int32})
      Route.known knowledge, sight, goal
    end

    # Where the character remembers the nearest staircase of *terrain*. `nil`
    # when they have never seen one.
    def remembered_stairs(terrain : Terrain) : {Int32, Int32}?
      knowledge.where(terrain).min_by? { |spot| Route.apart spot, @player.at }
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
        say "You cannot light #{name item}.",
          Event::Refused.new(:not_a_light, item: item.id, name: name(item))
        return false
      end

      if item.lit?
        item.douse
        say "You put out #{name item}.",
          Event::Kindled.new(name(item), lit: false, item: item.id)
      else
        item.kindle
        say "You light #{name item}.",
          Event::Kindled.new(name(item), lit: true, item: item.id)
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
        say "You put the #{fitting.kind.label} out.",
          Event::Kindled.new(fitting.kind.label, lit: false, at: {x, y})
      else
        fitting.kindle
        say "The #{fitting.kind.label} catches and burns.",
          Event::Kindled.new(fitting.kind.label, lit: true, at: {x, y})
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
      record Event::Over.new(@outcome)
      true
    end

    # Goes up the staircase the character stands on. Answers whether there was
    # one.
    #
    # The character climbs out of the dungeon. The run ends without a win.
    def ascend : Bool
      return false unless standing_on.stairs_up?

      @outcome = Outcome::Left
      record Event::Over.new(@outcome)
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
        say "You pick up #{Game.coins item.count}.",
          Event::Gold.new(:taken, item.count)
        spend_turn
        return true
      end

      letter = @player.inventory.add item
      unless letter
        floor.drop @player.x, @player.y, item
        say "You cannot carry any more.",
          Event::Refused.new(:pack_full, item: item.id, name: name(item))
        return false
      end

      say "#{letter} - #{name item}",
        Event::PickedUp.new(taken_id(letter, item), name item)
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

      return unless taken > 0

      say "You pick up #{Game.coins taken}.", Event::Gold.new(:taken, taken)
    end

    # The id of what is under *letter* now that *item* has gone in.
    #
    # A pile put into another is gone and so is its id. `Item#merge` keeps
    # the id of the pile that was already there, and that is the one an event
    # names.
    private def taken_id(letter : Char, item : Item) : Int32
      (@player.inventory[letter] || item).id
    end

    # Takes any ammunition the readied quiver would hold, without a turn of
    # its own.
    #
    # The step onto the square is the turn, the same as it is for gold. What
    # a character is shooting is what they walk over picking up, and an
    # arrow fired at something and then walked past is the whole reason for
    # it.
    #
    # Only what would sit under the quiver's own letter is taken. A `+1`
    # arrow beside a plain one looks different and is left where it lies,
    # because taking it would move the quiver's letter to a stack the
    # character never asked for.
    private def take_ammunition : Nil
      readied = @player.quivered
      return unless readied

      here.select { |item| readied.looks_like? item }.each do |item|
        next unless floor.take @player.x, @player.y, item

        # The quiver's own letter holds anything that looks like what is in
        # it, so there is always somewhere for this to go. The pack being
        # full is checked anyway, because a thing taken off the floor with
        # nowhere to put it would be gone.
        letter = @player.inventory.add item
        unless letter
          floor.drop @player.x, @player.y, item
          next
        end

        say "You pick up #{name item}.",
          Event::PickedUp.new(taken_id(letter, item), name item)
      end
    end

    # *total* gold pieces, written so one of them is one piece.
    def self.coins(total : Int32) : String
      total == 1 ? "1 gold piece" : "#{total} gold pieces"
    end

    # Picks up everything on the square. Answers how many entries were taken.
    #
    # This is not in the `Action` union and does not belong there. An action
    # is one turn. Picking up three items takes three turns, so this is three
    # actions. A bot and a replay log use three `Action::PickUp` instead.
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
        say "You have to take #{name item} off first.",
          Event::Refused.new(:worn, item: item.id, name: name(item))
        return false
      end

      dropped = name_under letter
      held = @player.inventory.remove letter
      @player.equipment.clean @player.inventory
      held.each { |one| floor.drop @player.x, @player.y, one }
      say "You drop #{dropped}.",
        Event::Dropped.new(held.map(&.id), dropped)
      spend_turn
      true
    end

    # Puts *amount* gold pieces on the floor. Answers how many went.
    #
    # This is one turn, so it could be an action. It is not in the `Action`
    # union because no key binds it and nothing needs it yet.
    def drop_gold(amount : Int32) : Int32
      dropped = @player.spend_gold amount
      return 0 if dropped.zero?

      purse = Item.new ItemKind::Gold, count: dropped
      purse.enrol next_id
      floor.drop @player.x, @player.y, purse
      say "You drop #{dropped} gold pieces.",
        Event::Gold.new(:dropped, dropped)
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
        say "You drink #{name item}.",
          Event::Used.new(item.id, name(item), :drink)
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
        say complaint, Event::Refused.new(:too_dark)
        return false
      end

      use letter, ItemClass::Scroll, "read", choice do |item|
        say "You read #{name item}.",
          Event::Used.new(item.id, name(item), :read)
      end
    end

    # Whether reading the scroll under *letter* will ask for a carried item.
    #
    # A scroll of identify always asks. A scroll of blessing, of remove curse
    # or of repair asks only when nothing has touched it: a blessed one
    # reaches everything and a cursed one picks its own target.
    def choice_needed?(letter : Char) : Bool
      item = @player.inventory[letter]
      return false unless item

      effect = item.kind.effect
      return true if effect.identify?
      return false unless effect.picks_one?

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
        say complaint, Event::Refused.new(:too_dark)
        return
      end

      item = @player.inventory[letter]
      return unless item && item.kind.item_class.scroll?

      used = @player.inventory.take letter, 1, next_id
      return unless used
      @player.equipment.clean @player.inventory

      used.reveal_blessing unless used.blessing.uncursed?
      say "You read #{name used}.",
        Event::Used.new(used.id, name(used), :read)
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
        say complaint, Event::Refused.new(:too_dark)
        return
      end

      item = @player.inventory[letter]
      return unless item && item.kind.item_class.scroll?

      used = @player.inventory.take letter, 1, next_id
      return unless used
      @player.equipment.clean @player.inventory

      used.reveal_blessing unless used.blessing.uncursed?
      say "You read #{name used}.",
        Event::Used.new(used.id, name(used), :read)
      found_out used.kind
      spend_turn
      used
    end

    # Does what *scroll* was aimed at. Spends no turn.
    def aim_reading(scroll : Item, target : {Int32, Int32}?) : Bool
      @in_flight = nil
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
      @in_flight = nil
      item = @player.inventory[letter]
      return false unless item

      unless item.kind.item_class.wand?
        say "You cannot zap #{name item}.",
          Event::Refused.new(:not_a_wand, item: item.id, name: name(item))
        return false
      end

      if dormant? item
        say "#{name(item).capitalize} is cracked and does nothing.",
          Event::Refused.new(:wand_cracked, item: item.id, name: name(item))
        return false
      end

      if item.sticks? && free_hand.nil?
        item.reveal_blessing
        say "Neither hand is free.",
          Event::Refused.new(:hands_full, item: item.id, name: name(item))
        return false
      end

      unless item.spend
        say "You zap #{name item}. Nothing happens.",
          Event::Used.new(item.id, name(item), :zap, spent: true)
        cool item
        spend_turn
        return true
      end

      say "You zap #{name item}.",
        Event::Used.new(item.id, name(item), :zap)
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

    # Records that the character has worked out what *item* is, and sorts the
    # pack.
    #
    # A line is written to the log only when there is something to report.
    # Almost everything a character carries turns out to be uncursed. A line
    # for each of them fills the log and stops the walk. The pack still moves
    # the item to a letter of its own, so a person reading the pack sees what
    # has been worked out.
    private def noticed(letter : Char, item : Item) : Nil
      return unless item.reveal_blessing

      Game.worked_out(@lore, item).try do |line|
        say line, Event::BlessingKnown.new(item.id,
          @lore.name(item, blessing: false), item.blessing.label)
      end
      settle letter, item
    end

    # What the character says when they work a blessing out for themselves.
    # `nil` when they work out that the item is uncursed.
    #
    # The verb agrees with the count, because one stack of three says "are"
    # and a single dagger says "is".
    #
    # The name leaves the blessing word out. The blessing is already in the
    # sentence.
    def self.worked_out(lore : Lore, item : Item) : String?
      return if item.blessing.uncursed?

      named = lore.name item, blessing: false
      verb = item.count > 1 ? "are" : "is"

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
      say "You have no letter left to keep them apart, and put the rest down.",
        Event::Spilled.new(rest.map(&.id))
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
      say "#{name(item).capitalize} twists into your hand.",
        Event::Grasped.new(item.id, name(item), slot)
    end

    # Takes the curse off a wand that has nothing left.
    #
    # An empty wand has nothing to hold anybody with. The character watched
    # it let go, so they know.
    private def cool(item : Item) : Nil
      return unless item.sticks? && item.spent?
      return unless item.uncurse

      say "#{name(item).capitalize} goes cold and lets go.",
        Event::Uncursed.new(item.id, name(item))
    end

    # Rolls whether the wand in the hand cracks on this swing.
    private def jar : Nil
      item = @player.wielded
      return unless item && item.kind.item_class.wand?
      return unless draught.rand(100) < BRITTLE
      return unless item.crack

      say "#{name(item).capitalize} cracks.",
        Event::Cracked.new(item.id, name(item))
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
        say "You cannot #{verb} #{name item}.",
          Event::Refused.new(:wrong_kind, item: item.id, name: name(item))
        return false
      end

      used = @player.inventory.take letter, 1, next_id
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
      in .none?            then nothing_happens
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
      in .repair?          then patch item, choice
      in .haste?           then hurry_up item
      in .slow?            then drag_with item, target
      in .haste_other?     then hurry_with item, target
      end
    end

    # An item whose effect is nothing at all.
    private def nothing_happens : Nil
      say "Nothing happens.", Event::Fizzled.new(:no_effect)
    end

    # Passes one turn of anything that cannot see.
    #
    # The character is told when their sight comes back. A creature is not:
    # what a creature can see is its own business, and the character has no
    # way to tell one that is blind from one that is looking elsewhere.
    private def blink : Nil
      if @player.blink
        say "You can see again.", Event::StatusEnd.new(:blind)
      end

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
        say "Nothing here is worth anything.",
          Event::Fizzled.new(:nothing_found)
        return
      end

      return gather_treasure piles if scroll.blessed?
      return ruin_treasure piles if scroll.cursed?

      piles.each { |column, row, item| detect column, row, item }
      found = piles.map do |column, row, item|
        Event::Found.new item.id, name(item), {column, row}
      end

      say "You know where #{Game.piles piles.size}.",
        Event::Detected.new(found)
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
          "totalling #{total} gp.",
        Event::Gold.new(:gathered, total, piles: piles.size)
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

      say "#{ruined} piles crumble, and #{lost} gp with them.",
        Event::Gold.new(:ruined, lost, piles: ruined)
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
        say "Nothing is lying anywhere you can feel.",
          Event::Fizzled.new(:nothing_found)
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
        told = @lore.name item, identified: true
        say "#{told.capitalize} - destroyed!",
          Event::Destroyed.new(item.id, told)
      end

      found.sort_by! do |column, row, _item|
        Notice.apart({column, row}, @player.at)
      end

      found.each do |column, row, item|
        say "You feel #{name item}.",
          Event::Detected.new([Event::Found.new(item.id, name(item),
            {column, row})])
      end
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
        say "The dark here is already as deep as it goes.",
          Event::Fizzled.new(:already_dark)
        keep_scroll scroll
        return
      end

      said = scroll.cursed? ? "The light is eaten, and what held it with it." : "The light goes out."
      say said, Event::LightsOut.new(doused, darkened, eaten: scroll.cursed?)
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

      say "The writing is still on it.",
        Event::ScrollKept.new(scroll.id, name(scroll))
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
        say "#{name(item).capitalize} burns away to nothing.",
          Event::Destroyed.new(item.id, name(item))
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
        say "The dark settles on nothing.", Event::Fizzled.new(:no_target)
        return
      end

      blind_creature creature, stream
    end

    # Takes the character's own sight away.
    private def blind_myself(stream : Rng) : Nil
      @player.blind BLINDING.roll(stream)
      say "The dark closes over your eyes.", Event::StatusStart.new(:blind)
    end

    # Blinds every creature in sight.
    private def blind_everything(stream : Rng) : Nil
      seen = monsters_in_sight
      if seen.empty?
        say "The dark settles on nothing.", Event::Fizzled.new(:no_target)
        return
      end

      seen.each { |creature| blind_creature creature, stream }
    end

    # Takes one creature's sight away.
    private def blind_creature(creature : Monster, stream : Rng) : Nil
      creature.blind CREATURE_BLINDING.roll(stream)
      say "The #{creature.label} claws at its eyes.",
        Event::StatusStart.new(:blind, who: creature.id)
    end

    # --------------------------------------------------------------- speed

    # Hurries the character. A potion of haste does this.
    #
    # How long it lasts is the potion's own dice, scaled by what has touched
    # it the way a potion of healing scales what it puts back. A second
    # draught lasts longer rather than going faster.
    private def hurry_up(item : Item) : Nil
      rolled = item.kind.power.roll draught
      ticks = Math.max rolled * item.blessing.potency // 100, 1
      going = @player.pace.hurried?
      @player.pace.hurry ticks

      say going ? "The hurry in you runs on." : "You speed up.",
        Event::StatusStart.new(:hurried, again: going)
    end

    # Holds back whatever a scroll of slow monster found.
    #
    # An uncursed one takes the creature it was aimed at. A blessed one takes
    # every creature in sight. A cursed one takes the reader.
    private def drag_with(scroll : Item, target : {Int32, Int32}?) : Nil
      stream = draught
      return drag_myself scroll, stream if scroll.cursed?
      return drag_everything scroll, stream if scroll.blessed?

      creature = target ? floor.monster(target[0], target[1]) : nil
      unless creature
        say "The words settle on nothing.", Event::Fizzled.new(:no_target)
        return
      end

      drag_creature creature, scroll, stream
    end

    # Holds the character back.
    private def drag_myself(scroll : Item, stream : Rng) : Nil
      @player.pace.drag scroll.kind.power.roll(stream)
      say "Your own feet drag.", Event::StatusStart.new(:dragging)
    end

    # Holds every creature in sight back.
    private def drag_everything(scroll : Item, stream : Rng) : Nil
      seen = monsters_in_sight
      if seen.empty?
        say "The words settle on nothing.", Event::Fizzled.new(:no_target)
        return
      end

      seen.each { |creature| drag_creature creature, scroll, stream }
    end

    # Holds one creature back.
    private def drag_creature(creature : Monster, scroll : Item, stream : Rng) : Nil
      creature.pace.drag scroll.kind.power.roll(stream)
      say "The #{creature.label} slows to a crawl.",
        Event::StatusStart.new(:dragging, who: creature.id)
    end

    # Hurries whatever a scroll of haste monster found.
    #
    # An uncursed one takes the creature it was aimed at, which is a poor
    # thing to do. A blessed one turns on the reader instead. A cursed one
    # takes every creature in sight.
    private def hurry_with(scroll : Item, target : {Int32, Int32}?) : Nil
      stream = draught
      return hurry_myself scroll, stream if scroll.blessed?
      return hurry_everything scroll, stream if scroll.cursed?

      creature = target ? floor.monster(target[0], target[1]) : nil
      unless creature
        say "The words settle on nothing.", Event::Fizzled.new(:no_target)
        return
      end

      hurry_creature creature, scroll, stream
    end

    # Hurries the character.
    private def hurry_myself(scroll : Item, stream : Rng) : Nil
      going = @player.pace.hurried?
      @player.pace.hurry scroll.kind.power.roll(stream)

      say going ? "The hurry in you runs on." : "You speed up.",
        Event::StatusStart.new(:hurried, again: going)
    end

    # Hurries every creature in sight.
    private def hurry_everything(scroll : Item, stream : Rng) : Nil
      seen = monsters_in_sight
      if seen.empty?
        say "The words settle on nothing.", Event::Fizzled.new(:no_target)
        return
      end

      seen.each { |creature| hurry_creature creature, scroll, stream }
    end

    # Hurries one creature.
    private def hurry_creature(creature : Monster, scroll : Item, stream : Rng) : Nil
      creature.pace.hurry scroll.kind.power.roll(stream)
      say "The #{creature.label} speeds up.",
        Event::StatusStart.new(:hurried, who: creature.id)
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

        say "The writing fades with nowhere to go.",
          Event::Fizzled.new(:no_target)
        return
      end

      spots = teleport_spots
      if spots.empty?
        say "The writing fades with nowhere to go.",
          Event::Fizzled.new(:no_target)
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
        say "The writing fades with nothing to fear.",
          Event::Fizzled.new(:no_target)
        return
      end

      beside = Direction.values.map(&.from(worst.x, worst.y))
        .find { |spot| standable? spot }

      unless beside
        say "The writing fades with nowhere to go.",
          Event::Fizzled.new(:no_target)
        return
      end

      arrive_at beside
      say "Something large is standing right there.", Event::Looming.new
    end

    # Puts the character on *spot* and looks around.
    private def arrive_at(spot : {Int32, Int32}) : Nil
      @player.move_to spot
      say "The floor lurches, and you are somewhere else.",
        Event::Teleported.new(spot)
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

      say marked > 0 ? "Marks appear on #{marked} of them." : "No marks appear.",
        Event::Marked.new(marked)
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
        say "There was nothing here for it to do.",
          Event::Fizzled.new(:nothing_to_change)
        return
      end

      say "#{changed} of them are #{anointed scroll}.",
        Event::Anointed.new(changed, curse: lifting? scroll)
    end

    # Whether *scroll* takes a curse off rather than laying a blessing on.
    private def lifting?(scroll : Item) : Bool
      scroll.kind.effect.remove_curse?
    end

    # What a scroll leaves something as.
    private def anointed(scroll : Item) : String
      lifting?(scroll) ? "free of a curse" : "blessed"
    end

    # The same, for a line that is still running on.
    private def lifts(scroll : Item) : String
      lifting?(scroll) ? "lifts a curse" : "blesses it"
    end

    # An uncursed scroll, which works on the one item the character picked.
    private def anoint_one(scroll : Item, choice : Char?) : Nil
      item = choice ? @player.inventory[choice] : nil
      unless item && choice
        say "The writing fades with nothing to settle on.",
          Event::Fizzled.new(:no_choice)
        return
      end

      told = name item
      unless anoint_it scroll, item
        say "Nothing about #{told} changes.",
          Event::Fizzled.new(:nothing_to_change, item: item.id, name: told)
        return
      end

      say "#{told.capitalize} is #{anointed scroll}.",
        Event::Anointed.new(1, curse: lifting?(scroll), item: item.id,
          name: told)
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
        say "The writing fades with nothing to settle on.",
          Event::Fizzled.new(:nothing_to_change)
        return
      end

      letter, item = pool[stream.rand pool.size]
      picked = "The scroll picks out #{letter}, #{name item}"

      unless anoint_it scroll, item
        say "#{picked}, to no effect.",
          Event::Fizzled.new(:nothing_to_change, item: item.id,
            name: name(item))
        return
      end

      say "#{picked}, and #{lifts scroll}.",
        Event::Anointed.new(1, curse: lifting?(scroll), item: item.id,
          name: name(item))
      settle letter, item
    end

    # ------------------------------------------------------------- repairing

    # What a scroll of repair does.
    #
    # An uncursed one takes the damage out of the one item the character
    # picked. A blessed one mends everything carried and everything lying
    # underfoot, which is what `#within` already answers for a blessed
    # scroll. A cursed one breaks something that was whole instead.
    private def patch(scroll : Item, choice : Char?) : Nil
      return damage_one if scroll.cursed?
      return patch_all scroll if scroll.blessed?

      patch_one choice
    end

    # A blessed scroll, which mends everything it reaches.
    private def patch_all(scroll : Item) : Nil
      mended = 0
      within(scroll).each { |_letter, item| mended += 1 if item.repair }

      if mended.zero?
        say "Nothing within reach was broken.",
          Event::Fizzled.new(:nothing_to_change)
        return
      end

      say "#{mended} of them are as good as new.", Event::Repaired.new(mended)
    end

    # An uncursed scroll, which mends the one item the character picked.
    #
    # The name is taken before the mending, because the word the mending
    # takes out is the word that says what was wrong with it.
    private def patch_one(choice : Char?) : Nil
      item = choice ? @player.inventory[choice] : nil
      unless item && choice
        say "The writing fades with nothing to settle on.",
          Event::Fizzled.new(:no_choice)
        return
      end

      told = name item
      unless item.repair
        say "Nothing about #{told} changes.",
          Event::Fizzled.new(:nothing_to_change, item: item.id, name: told)
        return
      end

      say "#{told.capitalize} #{item.count > 1 ? "are" : "is"} as good as new.",
        Event::Repaired.new(1, item: item.id, name: told)
      settle choice, item
    end

    # A cursed scroll, which breaks something whole.
    #
    # It picks among the things a condition means something on. A character
    # carrying nothing but potions and scrolls loses the scroll and no more.
    #
    # A letter is broken whole. A stack holds what looks alike, and one arrow
    # of twelve going dull is not something the character could point at.
    private def damage_one : Nil
      stream = draught
      whole = @player.inventory.items.select do |_letter, item|
        item.mendable? && !item.condition.damaged?
      end

      if whole.empty?
        say "The writing fades with nothing to settle on.",
          Event::Fizzled.new(:nothing_to_change)
        return
      end

      letter, item = whole[stream.rand whole.size]
      told = name item
      item.crack

      said = item.count > 1 ? "buckle and crack" : "buckles and cracks"
      say "#{told.capitalize} #{said}.", Event::Cracked.new(item.id, told)
      settle letter, item
    end

    # Records that the character has found out what *kind* is, and says so.
    #
    # Every effect in this phase is one somebody watching would understand,
    # so using an item names its kind. A potion that did nothing visible
    # would not, and this is where that exception goes when there is one.
    private def found_out(kind : ItemKind) : Nil
      return unless @lore.learn kind

      say "It was #{name Item.new(kind)}.",
        Event::Identified.new(name(Item.new(kind)), @lore.appearance(kind))
    end

    # Puts hit points back.
    private def mend(item : Item) : Nil
      rolled = item.kind.power.roll draught
      strength = Math.max rolled * item.blessing.potency // 100, 1
      put_back = @player.heal strength

      say put_back > 0 ? "You feel better." : "You feel no different.",
        Event::Healed.new(put_back)
    end

    # Names the carried item under *choice*, and whether it is cursed.
    private def name_one(choice : Char?) : Nil
      item = choice ? @player.inventory[choice] : nil
      unless item && choice
        say "You feel knowledgeable, and the feeling passes.",
          Event::Fizzled.new(:no_choice)
        return
      end

      news = @lore.learn item.kind
      learned choice, item

      say news ? "It is #{name item}." : "You knew that already. It is #{name item}.",
        Event::Identified.new(name(item), @lore.appearance(item.kind),
          news: news)
    end

    # Writes the shape of the whole floor into what the character remembers.
    #
    # The shape and no more. `Knowledge#touch` records the terrain and what
    # is fixed to it, and keeps whatever item was already remembered there.
    private def map_the_floor : Nil
      tiles = 0

      floor.each do |column, row, _tile|
        next unless wall? column, row

        @player.knowledge.touch floor, column, row, @turn
        tiles += 1
      end

      say "The shape of the floor comes to you.",
        Event::FloorMapped.new(tiles)
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

      squares = 0

      thrown.levels.each do |spot, level|
        next unless level > 0
        next unless floor.passable? spot[0], spot[1]

        floor.set_glow spot[0], spot[1], Math.max(floor.glow_at(spot[0], spot[1]), level)
        squares += 1
      end

      say "Light floods out and stays.", Event::FloorLit.new(squares)
    end

    # Sends a bolt at *target*.
    #
    # It flies the way an arrow flies and stops at the first thing in the
    # line. Nothing is left on the floor afterwards.
    private def bolt(item : Item, target : {Int32, Int32}?) : Nil
      unless target
        say "The bolt goes nowhere.", Event::Fizzled.new(:no_target)
        return
      end

      shot = flight target, item.kind.reach
      @in_flight = Missile.new shot
      spot = shot.at
      struck = floor.monster spot[0], spot[1]

      unless struck
        say "The bolt strikes the #{floor.terrain(spot[0], spot[1]).label}.",
          Event::BoltStopped.new(spot, floor.terrain(spot[0], spot[1]).label)
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
        say "You cannot wield #{name item}.",
          Event::Refused.new(:not_a_weapon, item: item.id, name: name(item))
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
        say "You cannot wear #{name item}.",
          Event::Refused.new(:not_armour, item: item.id, name: name(item))
        return false
      end

      held = @player.in_slot slot
      if held
        say "You are already wearing #{name held}.",
          Event::Refused.new(:slot_filled, item: held.id, name: name(held))
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
      say line, Event::Readied.new(slot, item.id, name(item))

      if item.sticks? && item.reveal_blessing
        say "#{name(item).capitalize} welds itself to you.",
          Event::Welded.new(item.id, name(item))
      end

      spend Costs.donning(slot)
      true
    end

    # Takes whatever is in *slot* off. Answers whether it came off.
    def take_off(slot : Slot) : Bool
      item = @player.in_slot slot
      unless item
        say slot.vacant, Event::Refused.new(:slot_empty)
        return false
      end

      if item.sticks? && !dormant?(item)
        item.reveal_blessing
        say "You cannot let go of #{name item}.",
          Event::Refused.new(:cursed, item: item.id, name: name(item))
        return false
      end

      @player.equipment.clear slot
      say slot.released(name item),
        Event::Removed.new(slot, item.id, name(item))
      spend Costs.donning(slot)
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

    # ----------------------------------------------------------------- ids

    # How many ids have been given out in this run.
    #
    # An id names one item or one creature for as long as it is there. A
    # replay log and a bot use "id 41" where a person says "the arrows under
    # f". A letter moves between items, and a bot's name for a thing must
    # not.
    #
    # The counter is on the run rather than in a constant. Two runs in one
    # process then have separate counters, and a run resumed from a save
    # does not give out a number already in use.
    #
    # The field has a default, so a save written before ids existed loads and
    # starts from zero. `#enrol` then raises it.
    getter minted : Int32 = 0

    # The next id, taken. Ids start at one, so zero means no id.
    def next_id : Int32
      clear_bearers
      @minted += 1
    end

    # The item or the creature under each id, or `nil` when it has to be
    # built again.
    #
    # It is not written out. It is a second reading of what the run already
    # holds, and a save that held it could disagree with itself.
    @[JSON::Field(ignore: true)]
    @bearers : Hash(Int32, Item | Monster)? = nil

    # :ditto:, built if it is not there.
    #
    # `#each_bearer` is one pass over the world, with a sort per floor. The
    # index turns K lookups in a turn into one pass rather than K.
    #
    # A run has one floor. `#descend` ends the run rather than digging the
    # next one, so the loop over floors in `#each_bearer` is for a game with
    # more than one later. What the build costs is what one floor holds.
    private def bearers : Hash(Int32, Item | Monster)
      found = @bearers
      return found if found

      built = {} of Int32 => Item | Monster
      each_bearer { |thing| built[thing.id] = thing unless thing.id.zero? }
      @bearers = built
    end

    # Throws the index away. The next lookup builds it again.
    #
    # Four things call this, and between them they cover every way the run
    # gains, loses or moves something with an id.
    #
    # * `#spend`, which every verb that changes anything goes through. A verb
    #   that takes no time changes nothing that has an id. The creatures act
    #   inside `#spend` as well, and a creature that picks something up or
    #   dies moves items.
    # * `#next_id`, which is the only way an id is given out. Splitting one
    #   arrow off a stack takes an id, and so does anything the debug console
    #   makes.
    # * `#perform`, once the action is over. Nothing outside this class
    #   reaches a rule any other way, so this covers a verb this list has
    #   missed.
    # * `#kill`, which takes a creature off the floor and puts what it
    #   carried on the square. A blow reaches it inside `#spend`. The debug
    #   console reaches it outside `#spend` and outside `#perform`, because a
    #   console command takes no turn.
    #
    # Nothing in this class looks an id up, so an index built part way
    # through an action cannot be read before one of the four throws it away.
    private def clear_bearers : Nil
      @bearers = nil
    end

    # Gives an id to everything in the run that has none.
    #
    # `Game.start` calls this once the floor is dug, the character is dressed
    # and the litter is down. Everything made by then came from the
    # generator, from `Items` or from `Loot`. None of those three holds the
    # run, so none of them can ask for a number. Walking the finished run
    # in a fixed order numbers all of it at once. The order is a function of
    # the seed, so two runs on one seed number the same things the same way.
    #
    # `#after_initialize` calls it again after a load. A save written before
    # ids existed has none, and this gives it some rather than refusing the
    # file. A save written since has them all, and this gives out nothing.
    #
    # The largest id in the run is found first. A file edited by hand can
    # hold an id above the counter. That number given out a second time would
    # put two things under one name.
    def enrol : Nil
      each_bearer { |thing| @minted = Math.max @minted, thing.id }
      each_bearer { |thing| thing.enrol next_id if thing.id.zero? }
      clear_bearers
    end

    # The item under the id *id*, or `nil` when nothing in the run has it.
    #
    # An id ends with the thing it names. A pile put into another is gone and
    # so is its id. A potion that has been drunk is `nil`.
    def item(id : Int32) : Item?
      return if id.zero?

      bearers[id]?.as? Item
    end

    # The creature under the id *id*, or `nil` when none in the run has it.
    def monster(id : Int32) : Monster?
      return if id.zero?

      bearers[id]?.as? Monster
    end

    # Everything in the run that has an id, in a fixed order.
    #
    # The floors come in order by name. On each floor the creatures come in
    # order by the square they stand on, each one with what it carries. The
    # piles on that floor follow, in order by the square they lie on. What
    # the character carries comes last, letter by letter.
    #
    # The order comes from the state of the run. It does not come from the
    # order things were made, or from the order a hash holds them in. Two
    # runs on one seed walk the same things in the same order, in one
    # process and across two.
    private def each_bearer(& : Item | Monster ->) : Nil
      @world.floors.keys.sort!.each do |name|
        ground = @world[name]

        standing = [] of {Int32, Int32}
        ground.each_monster { |column, row, _| standing << {column, row} }
        standing.sort!

        standing.each do |spot|
          creature = ground.monster spot[0], spot[1]
          next unless creature

          yield creature
          creature.carrying.each { |held| yield held }
        end

        lying = [] of {Int32, Int32}
        ground.each_pile { |column, row, _| lying << {column, row} }
        lying.sort!

        lying.each do |spot|
          ground.items(spot[0], spot[1]).each { |lot| yield lot }
        end
      end

      @player.inventory.each_item { |_letter, carried| yield carried }
    end

    # ------------------------------------------------------- one entry point

    # The scroll that has been read and is waiting for its question to be
    # answered. It is `nil` when no question is up.
    #
    # The question comes after the reading for two scrolls. One marks what it
    # could bless. One takes a square. Both spend the scroll and the turn
    # before the question. `#perform` keeps the spent scroll here, so
    # `Action::Choose` and `Action::Aim` are values a replay can carry. The
    # alternative is a pointer to an item the caller has to hold.
    #
    # The field is not in the save, in the way the creature being fought and
    # the missile in flight are not. There are three reasons for that. The
    # behaviour is older than the field, and `#start_reading` already states
    # it. A run saved with the question up has spent the scroll and the turn
    # and has given up the rest. An `Item` written out from both the
    # inventory and this field would load as two objects rather than one.
    # Serializing it would mend the lost scroll and add an aliasing bug. The
    # fix that would work is to hold the letter rather than the item and to
    # answer the question before the file is written, and that is a change a
    # player would notice.
    #
    # Four places can write a save while a question is up, all of them
    # through `Ui::Play#keep`: naming the character, `Q`, `>` and `<`. The
    # targeting cursor is not modal, so the last three are reachable with a
    # read-aim on screen. Only the ending screen answers the question first,
    # through `Ui::Play#stop_aiming`. Whoever takes this on starts at those
    # four.
    @[JSON::Field(ignore: true)]
    getter asking : Item? = nil

    # Does *action*. Answers whether the run took it and what it came to.
    #
    # This is the one entry point. `Ui::Play` reaches every rule through it,
    # and so do a replay log and a bot. It holds no rule of its own. Every
    # branch calls the method that already had the rule.
    #
    # An action that names something that is not there is refused before any
    # dispatch. Nothing changes and no turn is spent. An action whose subject
    # is there is dispatched even where the rule then refuses it. Walking
    # into a wall, and opening a door where there is none, are both things a
    # person does with one key press. Each of those rules refuses without
    # spending a turn.
    #
    # An unanswered question is left standing. Nothing here gives it up. The
    # person at the keyboard cannot reach another verb while the box is up,
    # and `#legal` offers a bot nothing else.
    def perform(action : Action) : Verdict
      @events.clear
      return Verdict.refused if over?

      recording
      verdict = dispatched action
      clear_bearers
      @recorder.try &.act action unless verdict.refused?
      verdict
    end

    # The rule for *action*.
    #
    # There are four groups and one verb of its own. Each group calls a
    # `case` that covers its own verbs and nothing else. Crystal folds a
    # union of every subclass back
    # into the parent. One `case` over the whole of `Action` cannot be
    # checked for exhaustiveness. A group of six can be. The cost is that a
    # new verb left out of every group is not a compile error. `#legal` and
    # the specs over it are what catch that instead.
    private def dispatched(action : Action) : Verdict
      case action
      when Action::Move, Action::Wait, Action::Open, Action::Close,
           Action::Descend, Action::Ascend
        moving action
      when Action::PickUp, Action::Drop, Action::Wield, Action::Wear,
           Action::Remove
        handling action
      when Action::Quaff, Action::Read, Action::Zap, Action::Apply,
           Action::Fire, Action::Throw
        using action
      when Action::MeleeAttack
        striking action
      when Action::Choose, Action::Aim
        answering action
      else
        raise ArgumentError.new "#{action.class} has no rule"
      end
    end

    # Where this run is being written down, or `nil` when nothing records it.
    #
    # It is not written out. A save holds the run, and where a copy of the
    # run is being kept is not part of it.
    @[JSON::Field(ignore: true)]
    @recorder : Replay::Log? = nil

    # Whether a log has been asked for yet.
    @[JSON::Field(ignore: true)]
    @recorded : Bool = false

    # Opens the log for this run, once, on the first action.
    #
    # The first action is the earliest point a run is worth recording from.
    # The character has a name by then, and the header takes the name and the
    # state the run is about to act from. `Replay::Log.pattern` decides
    # whether there is a log at all.
    private def recording : Nil
      return if @recorded

      @recorded = true
      @recorder = Replay::Log.opened self
    end

    # The verbs that move the character about the floor, or off it.
    private def moving(action : Action::Move | Action::Wait | Action::Open |
                                Action::Close | Action::Descend |
                                Action::Ascend) : Verdict
      case action
      in Action::Move
        Verdict.done step(action.dir)
      in Action::Wait
        wait
        Verdict.done
      in Action::Open
        open action.dir
        Verdict.done
      in Action::Close
        close action.dir
        Verdict.done
      in Action::Descend
        descend
        Verdict.done
      in Action::Ascend
        ascend
        Verdict.done
      end
    end

    # The blow the character aims at one square.
    #
    # It reaches `#attack`, which is the rule a step into a creature reaches.
    # The two verbs land the same blow.
    private def striking(action : Action::MeleeAttack) : Verdict
      target = action.target
      creature = floor.monster target[0], target[1]
      return Verdict.refused unless creature && melee?(target[0], target[1])

      # A step clears these before it swings. A walk reads them to decide
      # whether the last step said anything, so a swing leaves them the way
      # a step does.
      @discovery = false
      @forgiven = 0

      attack creature
      Verdict.done Step::Struck
    end

    # The verbs that move a thing between the floor, the pack and a slot.
    private def handling(action : Action::PickUp | Action::Drop |
                                  Action::Wield | Action::Wear |
                                  Action::Remove) : Verdict
      case action
      in Action::PickUp
        taking action
      in Action::Drop
        letter = letter_of action.item
        return Verdict.refused unless letter

        drop letter
        Verdict.done
      in Action::Wield
        letter = letter_of action.item
        return Verdict.refused unless letter

        wield letter
        Verdict.done
      in Action::Wear
        letter = letter_of action.item
        return Verdict.refused unless letter

        wear letter
        Verdict.done
      in Action::Remove
        return Verdict.refused unless @player.in_slot action.slot

        take_off action.slot
        Verdict.done
      end
    end

    # The verbs that use a thing up or let one fly.
    private def using(action : Action::Quaff | Action::Read | Action::Zap |
                               Action::Apply | Action::Fire |
                               Action::Throw) : Verdict
      case action
      in Action::Quaff
        letter = holding action.item, ItemClass::Potion
        return Verdict.refused unless letter

        quaff letter
        Verdict.done
      in Action::Read
        reading action
      in Action::Zap
        letter = holding action.item, ItemClass::Wand
        return Verdict.refused unless letter

        zap letter, action.target
        Verdict.done
      in Action::Apply
        applying action
      in Action::Fire
        fire action.target
        Verdict.done
      in Action::Throw
        letter = letter_of action.item
        return Verdict.refused unless letter

        throw letter, action.target
        Verdict.done
      end
    end

    # The answers to a question a scroll asked after it was read.
    private def answering(action : Action::Choose | Action::Aim) : Verdict
      scroll = @asking
      return Verdict.refused unless scroll

      # A scroll asks for a square or for a carried item, never for both.
      # The wrong answer is refused rather than swallowed, so a client that
      # sent one still has the question in front of it.
      return Verdict.refused if action.is_a?(Action::Aim) != scroll.kind.effect.aims_after?

      case action
      in Action::Choose
        wanted = action.item
        choice = wanted ? letter_of(wanted) : nil
        # An id naming nothing carried is refused, and the question stays up.
        # An action with no id at all gives the rest of the scroll up.
        return Verdict.refused if wanted && choice.nil?

        @asking = nil
        finish_reading scroll, choice
      in Action::Aim
        @asking = nil
        aim_reading scroll, action.target
      end

      Verdict.done
    end

    # Takes one thing off the square underfoot.
    #
    # An action with no id takes the only thing there. An action with no id
    # is refused where several things lie there. `bots/PROTOCOL.md` section 2
    # asks for that. A client that meant one of them has to say which.
    private def taking(action : Action::PickUp) : Verdict
      pile = here
      wanted = action.item

      unless wanted
        return Verdict.refused unless pile.size == 1

        pick_up pile.first
        return Verdict.done
      end

      # Zero is the id of a thing nothing has numbered. `#letter_of` refuses
      # it for the same reason. Nothing in a run that has been through
      # `#enrol` holds it.
      return Verdict.refused if wanted.zero?

      item = pile.find { |lying| lying.id == wanted }
      return Verdict.refused unless item

      pick_up item
      Verdict.done
    end

    # Reads the scroll the action names.
    #
    # There are three cases, and they are the three `Ui::Play` has. A scroll
    # that marks what it could bless, and one that takes a square, are read
    # here and leave their question on `#asking`. Every other scroll is read
    # whole, with whatever it works on already named.
    private def reading(action : Action::Read) : Verdict
      letter = holding action.item, ItemClass::Scroll
      return Verdict.refused unless letter

      wanted = action.choice
      choice = wanted ? letter_of(wanted) : nil
      return Verdict.refused if wanted && choice.nil?

      if marks_first? letter
        @asking = start_reading letter
      elsif target_needed? letter
        @asking = start_aiming_read letter
      else
        read letter, choice
      end

      Verdict.done
    end

    # Lights or puts out what the action names.
    #
    # The target has to be one `#appliable` offers. A sconce across the room
    # is out of reach. A potion is not a light.
    private def applying(action : Action::Apply) : Verdict
      held = action.item
      spot = action.at

      wanted = if held
                 letter = letter_of held
                 letter ? Roguelike::Apply.carried(letter) : nil
               elsif spot
                 Roguelike::Apply.fixture spot[0], spot[1]
               end
      return Verdict.refused unless wanted && appliable.includes? wanted

      apply wanted
      Verdict.done
    end

    # Which letter holds the item *id*. `nil` when the character carries
    # nothing under that id.
    #
    # It walks the pack rather than the whole run. `#item` walks every floor,
    # and a verb names something the character is carrying. An id that names
    # a thing on the floor, or one that names nothing at all, answers `nil`
    # here, and `#perform` refuses the action.
    #
    # Every item under the letter is compared, not only the one an action
    # takes. A letter holds fifteen arrows as four piles when three of them
    # differ by a curse nobody has noticed. Each pile has an id of its own.
    # `#legal` offers the first, and any of the four finds the letter.
    private def letter_of(id : Int32) : Char?
      return if id.zero?

      @player.inventory.each_item do |letter, item|
        return letter if item.id == id
      end

      nil
    end

    # Which letter holds the item *id*, where what is under that letter is of
    # *wanted*. `nil` when no letter holds it, and `nil` when one does and it
    # is of some other class.
    private def holding(id : Int32, wanted : ItemClass) : Char?
      letter = letter_of id
      return unless letter

      item = @player.inventory[letter]
      return unless item && item.kind.item_class == wanted

      letter
    end

    # Every action the run allows at this turn.
    #
    # A bot picks from this list. The list is shorter than what `#perform`
    # will take. An action that carries a square is offered once per creature
    # in sight, because those are the squares worth aiming at. `#perform`
    # takes any square the targeting cursor can reach. A move is offered only
    # where a step would do something, which is onto clear ground, into a
    # shut door, or into a creature the character cannot see. Walking into a
    # wall spends no turn, so it is not on the list. A swing is offered for
    # each creature in sight within the weapon's reach, and the step into
    # that creature is left off.
    def legal : Array(Action)
      legal sight
    end

    # :ditto:, against a field of view that has already been worked out.
    #
    # Working out a field of view is most of what a turn on a large floor
    # costs. A client that asks for the legal actions and for an observation
    # in the same breath works one out and passes it to both, the way
    # `#monsters_in_sight` and `Observation.of` already take one.
    def legal(seen : Vision) : Array(Action)
      found = [] of Action
      return found if over?

      # Answering a scroll that is waiting is the only thing there is to do.
      # `bots/PROTOCOL.md` section 4.5 asks for that.
      scroll = @asking
      return answers scroll, seen if scroll

      legal_moving found, seen
      legal_melee found, seen
      legal_floor found
      legal_carried found, seen
      legal_readied found
      found
    end

    # The answers the waiting scroll will take.
    private def answers(scroll : Item, seen : Vision) : Array(Action)
      found = [] of Action

      if scroll.kind.effect.aims_after?
        monsters_in_sight(seen).each { |creature| found << Action::Aim.new creature.at }
        found << Action::Aim.new
        return found
      end

      @player.inventory.entries.each { |_letter, item| found << Action::Choose.new item.id }
      found << Action::Choose.new
      found
    end

    # Stepping, waiting, the doors beside the character and the staircase
    # under them.
    private def legal_moving(found : Array(Action), seen : Vision) : Nil
      Direction.values.each do |direction|
        wanted = direction.from @player.x, @player.y
        next if melee? wanted[0], wanted[1], seen

        found << Action::Move.new direction if steps? direction
      end

      found << Action::Wait.new
      doors(Terrain::ClosedDoor).each { |direction| found << Action::Open.new direction }
      doors(Terrain::OpenDoor).each { |direction| found << Action::Close.new direction }
      found << Action::Descend.new if standing_on.stairs_down?
      found << Action::Ascend.new if standing_on.stairs_up?
    end

    # Whether a step *direction* would do anything.
    #
    # `#step` gives `Blocked` otherwise. A blocked step spends no turn.
    private def steps?(direction : Direction) : Bool
      wanted = direction.from @player.x, @player.y
      return true if floor.monster wanted[0], wanted[1]
      return true if floor.tile?(wanted[0], wanted[1]).try &.terrain.closed_door?

      floor.passable? wanted[0], wanted[1]
    end

    # A swing at each creature in sight within the weapon's reach.
    #
    # `#legal_moving` leaves out the step into such a creature. The swing
    # stands in place of the step rather than beside it. A step into a
    # creature the character cannot see stays a step, because that is what
    # the character means to take.
    private def legal_melee(found : Array(Action), seen : Vision) : Nil
      monsters_in_sight(seen).each do |creature|
        next unless within_reach? creature.x, creature.y

        found << Action::MeleeAttack.new creature.at
      end
    end

    # What the square underfoot and the sconces beside it offer.
    private def legal_floor(found : Array(Action)) : Nil
      pile = here
      found << Action::PickUp.new if pile.size == 1
      pile.each { |item| found << Action::PickUp.new item.id }

      appliable.each do |target|
        letter = target.letter
        held = letter ? @player.inventory[letter] : nil

        found << if held
          Action::Apply.new item: held.id
        else
          Action::Apply.new at: {target.x, target.y}
        end
      end
    end

    # What the pack offers, letter by letter.
    private def legal_carried(found : Array(Action), seen : Vision) : Nil
      aims = monsters_in_sight(seen).map &.at
      readable = cannot_read.nil?
      aims.each { |spot| found << Action::Fire.new spot } if cannot_fire.nil?

      @player.inventory.entries.each do |letter, item|
        slot = slot_of letter
        found << Action::Drop.new item.id unless slot
        legal_throwing found, item, aims unless slot && (item.sticks? || slot.armour?)
        legal_readying found, letter, item

        case item.kind.item_class
        when .potion? then found << Action::Quaff.new item.id
        when .scroll? then legal_reading found, letter, item if readable
        when .wand?   then legal_zapping found, letter, item, aims
        end
      end
    end

    # Throwing *item* at each creature in sight.
    private def legal_throwing(found : Array(Action), item : Item,
                               aims : Array({Int32, Int32})) : Nil
      return if item.kind.item_class.treasure?

      aims.each { |spot| found << Action::Throw.new item.id, spot }
    end

    # Wielding or wearing what is under *letter*.
    #
    # A slot already filled offers nothing. `#wear` refuses a second item
    # rather than taking the first one off. An action for it would be an
    # action that is refused.
    private def legal_readying(found : Array(Action), letter : Char,
                               item : Item) : Nil
      slot = Slot.for item
      return unless slot
      return if slot_of(letter) == slot

      if slot.weapon?
        found << Action::Wield.new item.id
      elsif @player.in_slot(slot).nil?
        found << Action::Wear.new item.id
      end
    end

    # The ways the scroll under *letter* can be read.
    #
    # A scroll that names a carried item before it is read is offered once
    # per item it could name. It is offered once with nothing named where
    # there is nothing it could work on. `Ui::Play` offers the same list.
    private def legal_reading(found : Array(Action), letter : Char,
                              item : Item) : Nil
      # A scroll whose question comes after the reading is one action with
      # nothing named in it. A scroll with no question is the same.
      if marks_first?(letter) || !choice_needed?(letter)
        found << Action::Read.new item.id
        return
      end

      wanted = reading_choices letter
      if wanted.empty?
        found << Action::Read.new item.id
        return
      end

      wanted.each { |choice| found << Action::Read.new item.id, choice }
    end

    # The carried items the scroll under *letter* could work on, by id.
    #
    # A scroll of identify names a kind the character has not made out. A
    # scroll of repair mends what is damaged. The scroll itself is not on the
    # list, because it is about to be used up.
    private def reading_choices(letter : Char) : Array(Int32)
      repair = effect_of(letter).repair?

      @player.inventory.entries.compact_map do |held, item|
        next if held == letter
        wanted = repair ? item.mendable? && item.condition.damaged? : !@lore.known?(item.kind)
        next unless wanted

        item.id
      end
    end

    # The ways the wand under *letter* can be zapped.
    private def legal_zapping(found : Array(Action), letter : Char,
                              item : Item,
                              aims : Array({Int32, Int32})) : Nil
      unless effect_of(letter).aimed?
        found << Action::Zap.new item.id
        return
      end

      aims.each { |spot| found << Action::Zap.new item.id, spot }
    end

    # Taking off what is readied.
    private def legal_readied(found : Array(Action)) : Nil
      readied.each { |slot, _item| found << Action::Remove.new slot }
    end

    def to_s(io : IO) : Nil
      io << "Game(turn=" << @turn << ", " << @outcome << ", " << @player << ')'
    end
  end
end
