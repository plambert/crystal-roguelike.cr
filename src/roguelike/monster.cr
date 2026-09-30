require "json"
require "../roguelike"

module Roguelike
  # One creature on a floor.
  #
  # A monster knows what it is, where it stands, how hurt it is and which band
  # it belongs to. It decides nothing. Phase 19 gives a band a plan and this
  # class still decides nothing: an AI reads a snapshot and answers an action,
  # and the one owner of the game state applies it.
  class Monster
    include JSON::Serializable

    # What this creature is called in a log or by a bot, for as long as it
    # lives.
    #
    # Zero means it has no id yet. `Game#enroll` walks the run and gives an
    # id to whatever has none. A creature the generator placed is numbered
    # that way. A save written before ids existed is numbered the same way.
    #
    # The field has a default, so such a save loads rather than being
    # refused.
    getter id : Int32 = 0

    # What family of creature it is.
    getter species : Species

    # Which kind of its species it is.
    #
    # A save written before kinds existed has no such field. `#kind` answers
    # the species' default kind for one of those, which is the creature the
    # species was then.
    @kind : Kind? = nil

    # The column it stands in.
    getter x : Int32

    # The row it stands in.
    getter y : Int32

    # Hit points left. It dies at zero.
    getter hit_points : Int32

    # What it is made of.
    getter attributes : Attributes

    # Which band it belongs to, by `Band#id`.
    #
    # Nothing reads this yet. Every monster is in a band of one until a band
    # has something to share.
    getter band : String

    # What this creature believes, by floor id, apart from what its band
    # believes.
    #
    # Every creature has its own. A band whose `Sharing` is `Inherited` gives
    # a new member a copy of the band's to start from and the two go their own
    # ways after that. One whose sharing is `Hive` writes both at once. One
    # whose sharing is `Called` writes its own and passes it on when it can.
    # In every case what this creature saw is here and what the band was told
    # is there, so the two can be told apart.
    #
    # Nothing reads this yet. It is here because adding a field to a
    # serialized type later means migrating save files.
    getter memory : Hash(String, Knowledge)

    # What it is carrying.
    #
    # `Loot` rolls this when the floor is made. Everything in it goes on the
    # square the creature dies on. Nothing else reads it: a monster does not
    # swing the sword it is holding until a later phase gives it a reason to,
    # and its armor does not add to what it takes off a blow either.
    #
    # A lit torch in here does throw light. `Game#lights` reads it, which is
    # where Phase 13's carried source finally has a carrier.
    getter carrying : Array(Item)

    # How many turns this creature cannot see for.
    #
    # It has a default, so a save written before this field existed loads
    # with every creature able to see.
    getter blinded : Int32 = 0

    # How many turns in a row every square nearer the character held another
    # creature.
    #
    # `Game` reads it to send a creature round a blocker it has waited on.
    # It has a default, so a save written before this field existed loads
    # with every creature free.
    getter hemmed : Int32 = 0

    # The squares this creature treats as solid while it walks round a
    # blocker. Empty when it is not.
    getter avoiding : Array({Int32, Int32}) = [] of {Int32, Int32}

    # How many more turns it keeps avoiding those squares.
    getter detour : Int32 = 0

    # How fast it is, and how much of its next action it has paid for.
    #
    # It has a default, so a save written before this field existed loads a
    # creature at normal speed. `#after_initialize` takes the base from the
    # species again on the way in, which is where it came from.
    getter pace : Pace = Pace.new

    # Hit points at full health.
    #
    # Zero in a save written before creatures rolled their hit points.
    # `#after_initialize` gives such a creature its kind's average.
    getter max_hit_points : Int32 = 0

    # How many turns until it can mend a neighbour again. Zero when it can.
    getter mending : Int32 = 0

    # How many turns it has counted toward its next split.
    #
    # `nil` while it has counted none, so a creature that never splits
    # writes out the bytes it wrote before splitting existed.
    @bud : Int32? = nil

    def initialize(kind : Kind, @x : Int32, @y : Int32,
                   @band : String,
                   hit_points : Int32? = nil,
                   attributes : Attributes? = nil,
                   @memory : Hash(String, Knowledge) = {} of String => Knowledge,
                   @carrying : Array(Item) = [] of Item,
                   max_hit_points : Int32? = nil)
      @kind = kind
      @species = kind.species
      @max_hit_points = max_hit_points || kind.hit_points
      @hit_points = hit_points || @max_hit_points
      @attributes = attributes || kind.attributes
      @pace = Pace.new kind.speed
    end

    # A creature of *species*' default kind.
    def self.new(species : Species, x : Int32, y : Int32, band : String,
                 hit_points : Int32? = nil, attributes : Attributes? = nil,
                 memory : Hash(String, Knowledge) = {} of String => Knowledge,
                 carrying : Array(Item) = [] of Item) : Monster
      new species.default, x, y, band, hit_points, attributes, memory, carrying
    end

    # Fills in after a load what an older save does not hold.
    #
    # The speed belongs to the kind rather than to the creature, so it is
    # taken from the kind again on the way in.
    def after_initialize : Nil
      @kind ||= @species.default
      @max_hit_points = kind.hit_points if @max_hit_points <= 0
      @pace.base = kind.speed
    end

    # Which kind of its species it is.
    def kind : Kind
      @kind || @species.default
    end

    # Whether it can mend a neighbour this turn.
    def ready_to_mend? : Bool
      kind.mends? && @mending <= 0
    end

    # Starts the wait before it can mend again.
    def mended(wait : Int32) : Nil
      @mending = wait
    end

    # How many turns it has counted toward its next split.
    def bud : Int32
      @bud || 0
    end

    # Counts one turn toward its next split.
    def grow : Nil
      @bud = bud + 1
    end

    # Starts the count toward its next split again.
    def budded : Nil
      @bud = nil
    end

    # Passes one turn of the wait before it can mend again.
    def rest_from_mending : Nil
      @mending -= 1 if @mending > 0
    end

    # Gives back *amount* hit points, never past full. Answers how many it
    # took.
    def heal(amount : Int32) : Int32
      before = @hit_points
      @hit_points = Math.min @hit_points + amount, @max_hit_points
      @hit_points - before
    end

    # Whether it has lost any hit points.
    def hurt? : Bool
      alive? && @hit_points < @max_hit_points
    end

    # Gives this creature the id *id*. Answers whether it took one.
    #
    # A creature takes an id once, for the same reason an item does. See
    # `Item#enroll`.
    def enroll(id : Int32) : Bool
      return false unless @id.zero?
      return false if id.zero?

      @id = id
      true
    end

    # Counts this turn as hemmed in when *hemmed*, and clears the count
    # otherwise.
    def hem(hemmed : Bool) : Nil
      @hemmed = hemmed ? @hemmed + 1 : 0
    end

    # Starts walking round *squares* for *turns* turns.
    def detour(squares : Array({Int32, Int32}), turns : Int32) : Nil
      @avoiding = squares
      @detour = turns
    end

    # Whether it is walking round something.
    def detouring? : Bool
      @detour > 0
    end

    # Uses up one turn of the detour.
    def detour_turn : Nil
      return unless detouring?

      @detour -= 1
      end_detour if @detour.zero?
    end

    # Goes back to walking the band's map.
    def end_detour : Nil
      @detour = 0
      @avoiding = [] of {Int32, Int32}
    end

    # Whether this creature cannot see.
    def blind? : Bool
      @blinded > 0
    end

    # Takes this creature's sight away for *turns*.
    def blind(turns : Int32) : Bool
      return false if turns <= @blinded

      @blinded = turns
      true
    end

    # Passes one turn of being unable to see. Answers whether sight came
    # back on this one.
    def blink : Bool
      return false unless blind?

      @blinded -= 1
      @blinded.zero?
    end

    # What this creature believes about the floor *id*, empty until it learns
    # something.
    def knowledge(id : String) : Knowledge
      @memory[id] ||= Knowledge.new id
    end

    # :ditto: Answers `nil` for a floor it has never been on.
    def knowledge?(id : String) : Knowledge?
      @memory[id]?
    end

    # Where it stands.
    def at : {Int32, Int32}
      {@x, @y}
    end

    # Puts it at *x*, *y*. This method does not check the square. `Floor#walk`
    # checks the square and keeps the floor's own table in step.
    def move_to(x : Int32, y : Int32) : Nil
      @x = x
      @y = y
    end

    # :ditto:
    def move_to(spot : {Int32, Int32}) : Nil
      move_to spot[0], spot[1]
    end

    # Whether it stands on *x*, *y*.
    def at?(x : Int32, y : Int32) : Bool
      @x == x && @y == y
    end

    # What this creature adds to a swing.
    #
    # Its dexterity modifier and nothing else. A creature carrying a sword is
    # not yet swinging it: `#carrying` is what drops when it dies and nothing
    # more than that.
    def to_hit : Int32
      @attributes.modifier Attributes::Which::Dexterity
    end

    # How much an attack on this creature is reduced by.
    #
    # Its kind's hide, plus the dexterity modifier, never below zero. That
    # is the shape `Player#armor_class` has, which is worn armor plus the
    # same modifier.
    def armor_class : Int32
      hide = kind.armor + @attributes.modifier(Attributes::Which::Dexterity)

      Math.max hide, 0
    end

    # What this creature hits for.
    #
    # Its kind's dice plus the strength modifier.
    def damage : Dice
      kind.damage.with_bonus @attributes.modifier(Attributes::Which::Strength)
    end

    # Whether it is still alive.
    def alive? : Bool
      @hit_points > 0
    end

    # Takes *amount* off its hit points. Answers how many are left.
    def hurt(amount : Int32) : Int32
      @hit_points = Math.max @hit_points - amount, 0
    end

    # Gives it *items* to carry, on top of whatever it already had.
    def carry(items : Enumerable(Item)) : Nil
      items.each { |item| @carrying << item }
    end

    # Takes everything it is carrying off it. Answers what was taken.
    def drop_everything : Array(Item)
      taken = @carrying.dup
      @carrying.clear
      taken
    end

    # What it is called.
    def label : String
      kind.label
    end

    # A sentence about it, for the examine pane.
    def description : String
      kind.description
    end

    # Whether this creature and *other* are the same in every way the game
    # decides anything by.
    #
    # The id is left out, for the reason `Item#==` leaves it out. An id is
    # which creature this is rather than what it is.
    def ==(other : Monster) : Bool
      kind == other.kind && @x == other.x && @y == other.y &&
        @hit_points == other.hit_points && @band == other.band &&
        @attributes.to_a == other.attributes.to_a && @memory == other.memory &&
        @carrying == other.carrying && @max_hit_points == other.max_hit_points &&
        @mending == other.mending && bud == other.bud
    end

    def to_s(io : IO) : Nil
      io << "Monster(" << kind << ' ' << @x << ',' << @y
      io << ' ' << @hit_points << '/' << max_hit_points << ')'
    end
  end
end
