require "json"
require "./item"
require "./knowledge"
require "./pace"
require "./species"

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

    # What sort of creature it is.
    getter species : Species

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

    # How fast it is, and how much of its next action it has paid for.
    #
    # It has a default, so a save written before this field existed loads a
    # creature at normal speed. `#after_initialize` takes the base from the
    # species again on the way in, which is where it came from.
    getter pace : Pace = Pace.new

    def initialize(@species : Species, @x : Int32, @y : Int32,
                   @band : String,
                   hit_points : Int32? = nil,
                   attributes : Attributes? = nil,
                   @memory : Hash(String, Knowledge) = {} of String => Knowledge,
                   @carrying : Array(Item) = [] of Item)
      @hit_points = hit_points || @species.hit_points
      @attributes = attributes || @species.attributes
      @pace = Pace.new @species.speed
    end

    # Takes the speed from the species after a load.
    #
    # The base belongs to the species rather than to the creature, so a save
    # written before creatures had a pace still loads a slime that oozes.
    def after_initialize : Nil
      @pace.base = @species.speed
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

    # Hit points at full health.
    def max_hit_points : Int32
      @species.hit_points
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
    # Its species' hide, plus the dexterity modifier, never below zero. That
    # is the shape `Player#armor_class` has, which is worn armor plus the
    # same modifier.
    def armor_class : Int32
      hide = @species.armor + @attributes.modifier(Attributes::Which::Dexterity)

      Math.max hide, 0
    end

    # What this creature hits for.
    #
    # Its species' dice plus the strength modifier.
    def damage : Dice
      @species.damage.with_bonus @attributes.modifier(Attributes::Which::Strength)
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
      @species.label
    end

    # A sentence about it, for the examine pane.
    def description : String
      @species.description
    end

    # Whether this creature and *other* are the same in every way the game
    # decides anything by.
    #
    # The id is left out, for the reason `Item#==` leaves it out. An id is
    # which creature this is rather than what it is.
    def ==(other : Monster) : Bool
      @species == other.species && @x == other.x && @y == other.y &&
        @hit_points == other.hit_points && @band == other.band &&
        @attributes.to_a == other.attributes.to_a && @memory == other.memory &&
        @carrying == other.carrying
    end

    def to_s(io : IO) : Nil
      io << "Monster(" << @species << ' ' << @x << ',' << @y
      io << ' ' << @hit_points << '/' << max_hit_points << ')'
    end
  end
end
