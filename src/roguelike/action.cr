require "json"
require "./direction"
require "./slot"

module Roguelike
  # One thing the character does, as a value.
  #
  # Every verb the game has is one subclass carrying whatever that verb
  # needs. `Game#perform` takes one of these and routes it to the rule that
  # answers it. `Game#legal` answers the ones the run allows now. `Ui::Play`
  # builds one for every key that spends a turn, so the keyboard, a replay
  # log and a bot all reach the rules by the same road.
  #
  # An action serializes with a `t` field naming the verb, so one goes into a
  # replay line and comes back out of it. The names are the ones
  # `bots/PROTOCOL.md` section 2 asks for where this game has that verb.
  #
  # Where the game and the spec differ, the game wins:
  #
  # * The spec's `remove` names an item. This game's `Game#take_off` names a
  #   slot, because one key takes off whatever is in a slot and the slot is
  #   what a person picks between. `Remove` carries the slot.
  # * The spec has no `zap`, `apply`, `ascend`, `fire` or `aim`. This game
  #   has all five.
  # * The spec folds every mid-action question into `choose`. A scroll here
  #   asks one of two questions: which carried item, or which square. One
  #   `choose` cannot carry a square, so `Aim` is the second answer.
  # * `throw` takes a square and never a direction. The game aims at a
  #   square, and the targeting cursor is what picks one.
  #
  # Items are named by the inventory letter they are carried under. The spec
  # asks for a stable entity id, and a later change replaces the letter with
  # one. Nothing else about this type changes when it does.
  abstract class Action
    include JSON::Serializable

    use_json_discriminator "t", {
      "move"    => Move,
      "wait"    => Wait,
      "open"    => Open,
      "close"   => Close,
      "pickup"  => PickUp,
      "drop"    => Drop,
      "wield"   => Wield,
      "wear"    => Wear,
      "remove"  => Remove,
      "quaff"   => Quaff,
      "read"    => Read,
      "zap"     => Zap,
      "apply"   => Apply,
      "fire"    => Fire,
      "throw"   => Throw,
      "descend" => Descend,
      "ascend"  => Ascend,
      "choose"  => Choose,
      "aim"     => Aim,
    }

    # How a direction is written in JSON.
    #
    # `bots/PROTOCOL.md` section 2 names the eight `n ne e se s sw w nw`.
    # The enum's own member names would be `NorthEast` and the like, which
    # no client outside Crystal would guess.
    module Compass
      # The short name of each direction, and the direction of each short
      # name.
      NAMES = {
        Direction::North     => "n",
        Direction::NorthEast => "ne",
        Direction::East      => "e",
        Direction::SouthEast => "se",
        Direction::South     => "s",
        Direction::SouthWest => "sw",
        Direction::West      => "w",
        Direction::NorthWest => "nw",
      }

      def self.from_json(pull : JSON::PullParser) : Direction
        wanted = pull.read_string
        found = NAMES.key_for? wanted
        raise JSON::ParseException.new("unknown direction #{wanted.inspect}", 0, 0) unless found

        found
      end

      def self.to_json(value : Direction, json : JSON::Builder) : Nil
        json.string NAMES[value]
      end
    end

    # How an inventory letter is written in JSON.
    #
    # JSON has no character type, so a letter is a string one long. `Char`
    # cannot go into a `JSON::Builder` on its own either.
    module Letters
      def self.from_json(pull : JSON::PullParser) : Char
        wanted = pull.read_string
        found = wanted.size == 1 ? wanted[0] : nil
        raise JSON::ParseException.new("#{wanted.inspect} is not one letter", 0, 0) unless found

        found
      end

      def self.to_json(value : Char, json : JSON::Builder) : Nil
        json.string value.to_s
      end
    end

    # How a slot is written in JSON.
    #
    # The member name in lower case, so `Slot::Ranged` is `"ranged"`. The
    # spec has no vocabulary for slots; this game needs one.
    module Slots
      def self.from_json(pull : JSON::PullParser) : Slot
        Slot.parse pull.read_string
      end

      def self.to_json(value : Slot, json : JSON::Builder) : Nil
        json.string value.to_s.underscore
      end
    end

    # One step on the grid. `hjklyubn` do this.
    #
    # A step into a creature is an attack on it. A step into a shut door
    # opens it. Keeping both on one verb is what holds the action space to
    # eight moves, and `bots/PROTOCOL.md` asks for it.
    class Move < Action
      getter t : String = "move"

      @[JSON::Field(converter: Roguelike::Action::Compass)]
      getter dir : Direction

      def initialize(@dir : Direction)
      end
    end

    # Passing the turn. `.` does this.
    class Wait < Action
      getter t : String = "wait"

      def initialize
      end
    end

    # Opening the door one square *dir*. `o` does this.
    class Open < Action
      getter t : String = "open"

      @[JSON::Field(converter: Roguelike::Action::Compass)]
      getter dir : Direction

      def initialize(@dir : Direction)
      end
    end

    # Closing the door one square *dir*. `c` does this.
    #
    # Shutting a door on something chasing the character is a tactic, which
    # is why it has a verb of its own rather than being a bump.
    class Close < Action
      getter t : String = "close"

      @[JSON::Field(converter: Roguelike::Action::Compass)]
      getter dir : Direction

      def initialize(@dir : Direction)
      end
    end

    # Taking one thing off the square the character stands on. `,` does
    # this.
    #
    # *item* is which of the pile, counted from nothing in the order
    # `Game#here` lists it. No *item* takes the only thing there and refuses
    # a pile of several, the way the spec asks.
    #
    # The index is what stands in for the stable entity id the spec wants
    # until items have one.
    class PickUp < Action
      getter t : String = "pickup"

      getter item : Int32?

      def initialize(@item : Int32? = nil)
      end
    end

    # Putting everything under one letter on the floor. `d` does this.
    class Drop < Action
      getter t : String = "drop"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char

      def initialize(@item : Char)
      end
    end

    # Readying a weapon, a bow or a quiver. `w` does this.
    class Wield < Action
      getter t : String = "wield"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char

      def initialize(@item : Char)
      end
    end

    # Putting a piece of armour on. `W` does this.
    class Wear < Action
      getter t : String = "wear"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char

      def initialize(@item : Char)
      end
    end

    # Taking off whatever is in *slot*. `T` does this.
    class Remove < Action
      getter t : String = "remove"

      @[JSON::Field(converter: Roguelike::Action::Slots)]
      getter slot : Slot

      def initialize(@slot : Slot)
      end
    end

    # Drinking a potion. `q` does this.
    class Quaff < Action
      getter t : String = "quaff"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char

      def initialize(@item : Char)
      end
    end

    # Reading a scroll. `r` does this.
    #
    # *choice* is the carried letter a scroll of identify or of repair works
    # on, which is known before the scroll is read. A scroll of blessing and
    # one of minor teleport ask their question afterwards instead, because
    # what they ask depends on the blessing on them and reading them is how
    # the character finds that out. Those leave `Game#asking` set, and
    # `Choose` or `Aim` answers it.
    class Read < Action
      getter t : String = "read"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter choice : Char?

      def initialize(@item : Char, @choice : Char? = nil)
      end
    end

    # Zapping a wand. `z` does this.
    #
    # *target* is the square an offensive wand is aimed at. A wand of light
    # takes none.
    class Zap < Action
      getter t : String = "zap"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char

      getter target : {Int32, Int32}?

      def initialize(@item : Char, @target : {Int32, Int32}? = nil)
      end
    end

    # Lighting or putting out a torch, a candle or a wall sconce. `a` does
    # this.
    #
    # *item* names a carried light. *at* names a sconce by the square it
    # stands on. Exactly one of the two is set, which is the same split
    # `Roguelike::Apply` makes.
    class Apply < Action
      getter t : String = "apply"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char?

      getter at : {Int32, Int32}?

      def initialize(@item : Char? = nil, @at : {Int32, Int32}? = nil)
      end
    end

    # Shooting the readied ranged weapon at *target*. `f` does this.
    class Fire < Action
      getter t : String = "fire"

      getter target : {Int32, Int32}

      def initialize(@target : {Int32, Int32})
      end
    end

    # Throwing what is under *item* at *target*. `t` does this.
    class Throw < Action
      getter t : String = "throw"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char

      getter target : {Int32, Int32}

      def initialize(@item : Char, @target : {Int32, Int32})
      end
    end

    # Going down the staircase underfoot. `>` does this.
    class Descend < Action
      getter t : String = "descend"

      def initialize
      end
    end

    # Climbing out of the dungeon by the staircase underfoot. `<` does this.
    #
    # The spec has no word for this ending. It is a third one: the run is
    # over and was not won.
    class Ascend < Action
      getter t : String = "ascend"

      def initialize
      end
    end

    # Naming the carried item a scroll already read works on.
    #
    # No *item* gives up what the scroll had left to do. It is spent either
    # way.
    class Choose < Action
      getter t : String = "choose"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char?

      def initialize(@item : Char? = nil)
      end
    end

    # Naming the square a scroll already read is aimed at.
    #
    # No *target* gives it up, the same way `Choose` with no item does.
    class Aim < Action
      getter t : String = "aim"

      getter target : {Int32, Int32}?

      def initialize(@target : {Int32, Int32}? = nil)
      end
    end
  end

  # What one call to `Game#perform` did.
  #
  # An action the run will not take is answered rather than raised. A client
  # sending one is ordinary traffic: a bot picking outside `Game#legal`, a
  # replay recorded against an older build, a key arriving a moment after the
  # thing it named stopped being there. The headless protocol turns each of
  # those into a line of its own, and raising would make every caller wrap
  # every call. Nothing changed and no turn was spent, because `Game#perform`
  # decides before it dispatches.
  #
  # `#allowed` true says only that the rule ran. Opening a door where there is
  # none still answers true: refusing is that rule's own answer, and it has
  # already written the line that says so.
  #
  # `#step` is what a move came to, and `nil` for every other verb. `Ui::Play`
  # reads it to decide whether the camera follows.
  record Verdict,
    allowed : Bool,
    step : Step? = nil do
    # An action the run will not take.
    def self.refused : Verdict
      new false
    end

    # An action that reached its rule.
    def self.done(step : Step? = nil) : Verdict
      new true, step
    end

    # Whether the run would not take it.
    def refused? : Bool
      !@allowed
    end
  end
end
