require "json"
require "./direction"
require "./slot"

module Roguelike
  # One thing the character does, as a value.
  #
  # Every verb the game has is one subclass. A subclass carries what that
  # verb needs. `Game#perform` takes one of these and calls the rule for it.
  # `Game#legal` gives the ones the run allows now. `Ui::Play` builds one
  # for every key that spends a turn. A replay line and a bot's choice are
  # the same value. All three reach the same rule.
  #
  # An action serializes with a `t` field naming the verb, so one is written
  # to a replay line and read back from it. The names are the ones
  # `bots/PROTOCOL.md` section 2 asks for, where this game has that verb.
  #
  # The game and the spec differ in four ways. The game is what this type
  # follows.
  #
  # * The spec's `remove` names an item. `Game#take_off` names a slot. One
  #   key takes off whatever is in a slot, and a person picks between slots.
  #   `Remove` carries the slot.
  # * The spec has no `zap`, `apply`, `ascend`, `fire` or `aim`. This game
  #   has all five.
  # * The spec has one `choose` for every mid-action question. A scroll here
  #   asks for a carried item or for a square. A `choose` cannot carry a
  #   square. `Aim` is the answer that carries one.
  # * `throw` takes a square and never a direction. The game aims at a
  #   square. The person picks that square with the targeting cursor.
  #
  # An item is named by the inventory letter it is carried under. A letter is
  # not stable across a replay, because a letter moves between items.
  # `Item#id` is stable. The letters are to be replaced by ids before the
  # replay log lands. Nothing else about this type changes then.
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
    # `bots/PROTOCOL.md` section 2 names the eight directions `n ne e se s
    # sw w nw`. The enum's own member names are `NorthEast` and the like.
    # Those names are particular to Crystal. They are not what a client in
    # another language expects.
    module Compass
      # Each direction and its short name. `Hash#key_for?` reads the table
      # the other way.
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
    # A slot is the member name in lower case, so `Slot::Ranged` is
    # `"ranged"`. The spec has no names for slots. This game needs them.
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
    # opens it. Both are on this one verb. The action space is then eight
    # moves, which is what `bots/PROTOCOL.md` asks for.
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
    # Shutting a door on something that chases the character is a tactic.
    # It is a verb of its own for that reason, rather than a step into the
    # door.
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
    # *item* is the index of one thing in the pile. The first is zero, in
    # the order `Game#here` gives. An action with no *item* takes the only
    # thing there. It is refused where several things lie there, which is
    # what the spec asks for.
    #
    # The index is what `Game#here` is addressed by, so it stays. The spec
    # asks for a stable entity id in its place. `Item#id` is that id, and
    # nothing yet needs `PickUp` to carry one.
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
    # on. That letter is known before the scroll is read. For a scroll of
    # blessing, and for one of minor teleport, the question comes after the
    # reading. The question depends on the blessing on the scroll, and the
    # reading is how the character learns it. Those two leave `Game#asking`
    # set. `Choose` or `Aim` is the answer.
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
    # stands on. Exactly one of the two is set. `Roguelike::Apply` is
    # divided the same way.
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
    # The spec has no word for this ending. It is a third ending. The run
    # is over and it was not won.
    class Ascend < Action
      getter t : String = "ascend"

      def initialize
      end
    end

    # Naming the carried item a scroll already read works on.
    #
    # An action with no *item* gives up the rest of what the scroll would
    # do. The scroll is spent either way.
    class Choose < Action
      getter t : String = "choose"

      @[JSON::Field(converter: Roguelike::Action::Letters)]
      getter item : Char?

      def initialize(@item : Char? = nil)
      end
    end

    # Naming the square a scroll already read is aimed at.
    #
    # An action with no *target* gives it up. `Choose` with no item is the
    # same.
    class Aim < Action
      getter t : String = "aim"

      getter target : {Int32, Int32}?

      def initialize(@target : {Int32, Int32}? = nil)
      end
    end
  end

  # What one call to `Game#perform` did.
  #
  # An action the run will not take is refused in the return value rather
  # than raised. Three ordinary things send one: a bot picking outside
  # `Game#legal`, a replay recorded against an older build, and a key that
  # arrives after the thing it names is gone. The headless protocol reports
  # each of those on a line of its own. An exception would need a rescue
  # around every call. A refused action changes nothing and spends no turn,
  # because `Game#perform` checks before it dispatches.
  #
  # `#allowed` true means only that the rule ran. The verdict for opening a
  # door where there is none is still true. The refusal belongs to that rule,
  # and that rule has already written the line for it.
  #
  # `#step` is what a move came to. It is `nil` for every other verb.
  # `Ui::Play` reads it and decides whether to move the view.
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
