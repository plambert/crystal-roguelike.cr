require "json"
require "./action"
require "./direction"
require "./slot"

module Roguelike
  # One thing that happened, as a value.
  #
  # Every point in `Game` that writes a line to the message log builds one of
  # these beside it. The line is English for a person. The event is the same
  # fact in fields, for a bot and for a replay log. `Game#events` holds the
  # ones the last `Game#perform` produced, oldest first.
  #
  # An event serializes with a `kind` field naming what happened, the way an
  # `Action` serializes with a `t` field. `bots/PROTOCOL.md` section 5.2 asks
  # for that name.
  #
  # An event holds nothing the character cannot know. The line beside it is
  # the bound. An event may carry what its line says. It leaves out what its
  # line leaves out. A creature the character cannot see is named by neither.
  # Exact hit points are in neither. A potion the character has not made out
  # gives its appearance in both.
  #
  # An item or a creature is named by its id, which `Game#item` and
  # `Game#monster` read back. An inventory letter and a pile index are not
  # ids. Both move between things. A field named `who`, `target` or `attacker`
  # is `nil` for the character, who has no id.
  abstract class Event
    include JSON::Serializable

    use_json_discriminator "kind", {
      "anointed"       => Anointed,
      "attack"         => Attack,
      "blessing_known" => BlessingKnown,
      "blocked"        => Blocked,
      "bolt_stopped"   => BoltStopped,
      "cracked"        => Cracked,
      "destroyed"      => Destroyed,
      "detected"       => Detected,
      "door"           => Door,
      "dropped"        => Dropped,
      "fizzled"        => Fizzled,
      "floor_lit"      => FloorLit,
      "floor_mapped"   => FloorMapped,
      "gold"           => Gold,
      "grasped"        => Grasped,
      "ground"         => Ground,
      "healed"         => Healed,
      "identified"     => Identified,
      "kindled"        => Kindled,
      "level_up"       => LevelUp,
      "lights_out"     => LightsOut,
      "looming"        => Looming,
      "loosed"         => Loosed,
      "marked"         => Marked,
      "noticed"        => Noticed,
      "over"           => Over,
      "picked_up"      => PickedUp,
      "pile"           => Pile,
      "readied"        => Readied,
      "refused"        => Refused,
      "removed"        => Removed,
      "repaired"       => Repaired,
      "scroll_kept"    => ScrollKept,
      "slain"          => Slain,
      "spilled"        => Spilled,
      "status_end"     => StatusEnd,
      "status_start"   => StatusStart,
      "teleported"     => Teleported,
      "uncursed"       => Uncursed,
      "used"           => Used,
      "waited"         => Waited,
      "welded"         => Welded,
    }

    # The line written beside this event.
    #
    # `Game#say` fills it in. It is for a person reading a log. A client reads
    # the fields. `bots/PROTOCOL.md` section 5.2 asks for it and calls it
    # optional.
    property text : String? = nil

    # One thing, as the character would name it.
    record Thing, item : Int32, name : String do
      include JSON::Serializable
    end

    # One thing and the square it lies on.
    record Found, item : Int32, name : String, at : {Int32, Int32} do
      include JSON::Serializable
    end

    # What the character is standing on, when it is worth a line.
    class Ground < Event
      getter kind : String = "ground"

      getter at : {Int32, Int32}
      getter terrain : String

      def initialize(@at : {Int32, Int32}, @terrain : String)
      end
    end

    # What is lying on the square the character has walked onto.
    #
    # The whole pile, whether the line named one thing or counted several.
    # The character is standing on it, so they can pick any of it up.
    class Pile < Event
      getter kind : String = "pile"

      getter at : {Int32, Int32}
      getter things : Array(Thing)

      def initialize(@at : {Int32, Int32}, @things : Array(Thing))
      end
    end

    # A step that did not happen.
    #
    # *terrain* is what stood in the way, when it was the floor itself.
    # *creature* is what stood in the way, when the character could see it.
    # Both `nil` with *unseen* true means the character walked into something
    # and does not know what.
    class Blocked < Event
      getter kind : String = "blocked"

      @[JSON::Field(converter: Roguelike::Action::Compass)]
      getter dir : Direction

      getter terrain : String?
      getter creature : Int32?
      getter? unseen : Bool

      def initialize(@dir : Direction, @terrain : String? = nil,
                     @creature : Int32? = nil, @unseen : Bool = false)
      end
    end

    # A door the character opened or shut.
    class Door < Event
      getter kind : String = "door"

      getter at : {Int32, Int32}
      getter? open : Bool

      def initialize(@at : {Int32, Int32}, @open : Bool)
      end
    end

    # One blow, landed or missed.
    #
    # *attacker* and *target* are `nil` for the character. *with* names what
    # struck. It is the readied weapon for a swing and the arrow or the bolt
    # for a shot. It is `nil` for a creature's own claws and for bare hands.
    #
    # *damage* is what the blow took off. It is `nil` for a miss. How much
    # the target has left is not here. A creature's hit points are hidden.
    class Attack < Event
      getter kind : String = "attack"

      getter attacker : Int32?
      getter target : Int32?
      getter? hit : Bool
      getter damage : Int32?
      getter with : String?

      def initialize(@hit : Bool, @attacker : Int32? = nil,
                     @target : Int32? = nil, @damage : Int32? = nil,
                     @with : String? = nil)
      end
    end

    # A creature the character killed.
    class Slain < Event
      getter kind : String = "slain"

      getter creature : Int32
      getter species : String

      def initialize(@creature : Int32, @species : String)
      end
    end

    # The end of the run.
    #
    # *killer* and *killer_species* name what killed the character. Both are
    # `nil` for a run that ended any other way.
    class Over < Event
      getter kind : String = "over"

      getter outcome : Outcome
      getter killer : Int32?
      getter killer_species : String?

      def initialize(@outcome : Outcome, @killer : Int32? = nil,
                     @killer_species : String? = nil)
      end
    end

    # The character reached a new experience level.
    class LevelUp < Event
      getter kind : String = "level_up"

      getter level : Int32

      def initialize(@level : Int32)
      end
    end

    # A rule that would not take the action.
    #
    # The action is named in the request. This carries why it was refused and
    # what the refusal was about.
    class Refused < Event
      # Why a rule would not take the action.
      enum Reason
        # Nothing readied to shoot with.
        NothingReadied

        # The quiver is empty.
        QuiverEmpty

        # What is in the quiver does not fit what is readied.
        WrongAmmunition

        # There is not enough light to read by.
        TooDark

        # A curse holds the item in its slot.
        Cursed

        # The item is worn, and comes off before it goes anywhere.
        Worn

        # The pack is full.
        PackFull

        # The item does not burn.
        NotALight

        # The item is not a weapon.
        NotAWeapon

        # The item is not armor.
        NotArmor

        # The item is not a wand.
        NotAWand

        # The item is not of the class the verb takes.
        WrongKind

        # The wand is cracked.
        WandCracked

        # A cursed wand needs a free hand, and both are held.
        HandsFull

        # Something is already in the slot.
        SlotFilled

        # The slot is empty.
        SlotEmpty

        # There is no door that way.
        NoDoor

        # A creature stands in the doorway.
        DoorwayCreature

        # Something is lying in the doorway.
        DoorwayItems
      end

      getter kind : String = "refused"

      getter reason : Reason
      getter item : Int32?
      getter name : String?
      getter creature : Int32?

      def initialize(@reason : Reason, @item : Int32? = nil,
                     @name : String? = nil, @creature : Int32? = nil)
      end
    end

    # Something the character sent across the floor.
    #
    # *thrown* false is a shot from a readied ranged weapon. *at* is the
    # square it was aimed at rather than the square it stopped on.
    class Loosed < Event
      getter kind : String = "loosed"

      getter item : Int32
      getter name : String
      getter at : {Int32, Int32}
      getter? thrown : Bool

      def initialize(@item : Int32, @name : String, @at : {Int32, Int32},
                     @thrown : Bool)
      end
    end

    # Something the character took off the floor.
    class PickedUp < Event
      getter kind : String = "picked_up"

      getter item : Int32
      getter name : String

      def initialize(@item : Int32, @name : String)
      end
    end

    # Everything under one letter, put on the floor.
    class Dropped < Event
      getter kind : String = "dropped"

      getter items : Array(Int32)
      getter name : String

      def initialize(@items : Array(Int32), @name : String)
      end
    end

    # What the pack had no letter left for, put on the floor.
    class Spilled < Event
      getter kind : String = "spilled"

      getter items : Array(Int32)

      def initialize(@items : Array(Int32))
      end
    end

    # Gold the character gained or lost.
    class Gold < Event
      # What happened to it.
      enum Change
        # Taken off the floor.
        Taken

        # Brought to the character by a scroll.
        Gathered

        # Put on the floor.
        Dropped

        # Crumbled by a scroll.
        Ruined
      end

      getter kind : String = "gold"

      getter change : Change
      getter amount : Int32
      getter piles : Int32?

      def initialize(@change : Change, @amount : Int32, @piles : Int32? = nil)
      end
    end

    # Something the character used up or zapped.
    #
    # *spent* true is a wand with no charge left. The turn goes either way.
    class Used < Event
      # What the character did with it.
      enum Verb
        Drink
        Read
        Zap
      end

      getter kind : String = "used"

      getter item : Int32
      getter name : String
      getter verb : Verb
      getter? spent : Bool

      def initialize(@item : Int32, @name : String, @verb : Verb,
                     @spent : Bool = false)
      end
    end

    # A kind of item the character has made out.
    #
    # It holds for every item of that appearance, this one and the next.
    # *news* false means they already knew.
    class Identified < Event
      getter kind : String = "identified"

      getter name : String
      getter appearance : String?
      getter? news : Bool

      def initialize(@name : String, @appearance : String? = nil,
                     @news : Bool = true)
      end
    end

    # A blessing or a curse the character has made out on one item.
    class BlessingKnown < Event
      getter kind : String = "blessing_known"

      getter item : Int32
      getter name : String
      getter blessing : String

      def initialize(@item : Int32, @name : String, @blessing : String)
      end
    end

    # A cursed wand that put itself in the character's hand.
    class Grasped < Event
      getter kind : String = "grasped"

      getter item : Int32
      getter name : String

      @[JSON::Field(converter: Roguelike::Action::Slots)]
      getter slot : Slot

      def initialize(@item : Int32, @name : String, @slot : Slot)
      end
    end

    # A curse that let go.
    class Uncursed < Event
      getter kind : String = "uncursed"

      getter item : Int32
      getter name : String

      def initialize(@item : Int32, @name : String)
      end
    end

    # Something that broke.
    class Cracked < Event
      getter kind : String = "cracked"

      getter item : Int32
      getter name : String

      def initialize(@item : Int32, @name : String)
      end
    end

    # What a status is.
    enum Status
      # Moving faster than usual.
      Hurried

      # Moving slower than usual.
      Dragging

      # Unable to see.
      Blind
    end

    # A status that started.
    #
    # *who* is `nil` for the character. *again* true means it was already
    # running and was extended. How long it lasts is not here. The character
    # is told no number.
    class StatusStart < Event
      getter kind : String = "status_start"

      getter who : Int32?
      getter status : Status
      getter? again : Bool

      def initialize(@status : Status, @who : Int32? = nil,
                     @again : Bool = false)
      end
    end

    # A status that ran out. *who* is `nil` for the character.
    class StatusEnd < Event
      getter kind : String = "status_end"

      getter who : Int32?
      getter status : Status

      def initialize(@status : Status, @who : Int32? = nil)
      end
    end

    # Hit points put back. *amount* zero is a draught that did nothing.
    class Healed < Event
      getter kind : String = "healed"

      getter who : Int32?
      getter amount : Int32

      def initialize(@amount : Int32, @who : Int32? = nil)
      end
    end

    # Something used that came to nothing.
    class Fizzled < Event
      # Why nothing came of it.
      enum Reason
        # The item does nothing at all.
        NoEffect

        # There was nothing where it was aimed.
        NoTarget

        # What it reached was already the way it would leave it.
        NothingToChange

        # It found nothing to write down.
        NothingFound

        # The dark it would make is already there.
        AlreadyDark

        # The character named nothing for it to work on.
        NoChoice
      end

      getter kind : String = "fizzled"

      getter reason : Reason
      getter item : Int32?
      getter name : String?

      def initialize(@reason : Reason, @item : Int32? = nil,
                     @name : String? = nil)
      end
    end

    # What a scroll of detection wrote down.
    class Detected < Event
      getter kind : String = "detected"

      getter found : Array(Found)

      def initialize(@found : Array(Found))
      end
    end

    # Something that no longer exists.
    class Destroyed < Event
      getter kind : String = "destroyed"

      getter item : Int32
      getter name : String

      def initialize(@item : Int32, @name : String)
      end
    end

    # Lights put out nearby.
    #
    # *doused* counts what was burning. *darkened* counts the squares that
    # were glowing on their own. *eaten* true means the scroll destroyed what
    # it put out.
    class LightsOut < Event
      getter kind : String = "lights_out"

      getter doused : Int32
      getter darkened : Int32
      getter? eaten : Bool

      def initialize(@doused : Int32, @darkened : Int32, @eaten : Bool)
      end
    end

    # A scroll that survived being read and went back in the pack.
    class ScrollKept < Event
      getter kind : String = "scroll_kept"

      getter item : Int32
      getter name : String

      def initialize(@item : Int32, @name : String)
      end
    end

    # The shape of the floor, written into what the character remembers.
    #
    # *tiles* counts the squares it added or confirmed. `bots/PROTOCOL.md`
    # section 5.2 calls this `tiles_revealed`. The squares themselves are in
    # the snapshot.
    class FloorMapped < Event
      getter kind : String = "floor_mapped"

      getter tiles : Int32

      def initialize(@tiles : Int32)
      end
    end

    # Squares made to glow for good.
    class FloorLit < Event
      getter kind : String = "floor_lit"

      getter squares : Int32

      def initialize(@squares : Int32)
      end
    end

    # A bolt that stopped against the floor rather than against a creature.
    class BoltStopped < Event
      getter kind : String = "bolt_stopped"

      getter at : {Int32, Int32}
      getter terrain : String

      def initialize(@at : {Int32, Int32}, @terrain : String)
      end
    end

    # The character, moved somewhere else on the floor.
    class Teleported < Event
      getter kind : String = "teleported"

      getter at : {Int32, Int32}

      def initialize(@at : {Int32, Int32})
      end
    end

    # Something large is standing beside the character.
    #
    # It carries no id and no square. The line names neither, and the
    # character may be somewhere they cannot see it.
    class Looming < Event
      getter kind : String = "looming"

      def initialize
      end
    end

    # A band that has noticed the character.
    #
    # *creature* and *species* name the one that noticed, when the character
    # can see it. Both are `nil` when the character only heard it.
    class Noticed < Event
      getter kind : String = "noticed"

      getter creature : Int32?
      getter species : String?

      def initialize(@creature : Int32? = nil, @species : String? = nil)
      end
    end

    # How many things a scroll marked.
    class Marked < Event
      getter kind : String = "marked"

      getter count : Int32

      def initialize(@count : Int32)
      end
    end

    # What a scroll of blessing or of remove curse changed.
    #
    # *curse* true is a curse lifted. *curse* false is a blessing laid on.
    # *item* and *name* are set where one thing was changed.
    class Anointed < Event
      getter kind : String = "anointed"

      getter count : Int32
      getter? curse : Bool
      getter item : Int32?
      getter name : String?

      def initialize(@count : Int32, @curse : Bool, @item : Int32? = nil,
                     @name : String? = nil)
      end
    end

    # What a scroll of repair mended.
    class Repaired < Event
      getter kind : String = "repaired"

      getter count : Int32
      getter item : Int32?
      getter name : String?

      def initialize(@count : Int32, @item : Int32? = nil,
                     @name : String? = nil)
      end
    end

    # Something lit or put out.
    #
    # *item* names a carried light. *at* names a sconce by the square it
    # stands on. Exactly one of the two is set.
    class Kindled < Event
      getter kind : String = "kindled"

      getter item : Int32?
      getter at : {Int32, Int32}?
      getter name : String
      getter? lit : Bool

      def initialize(@name : String, @lit : Bool, @item : Int32? = nil,
                     @at : {Int32, Int32}? = nil)
      end
    end

    # Something put into a slot.
    class Readied < Event
      getter kind : String = "readied"

      @[JSON::Field(converter: Roguelike::Action::Slots)]
      getter slot : Slot

      getter item : Int32
      getter name : String

      def initialize(@slot : Slot, @item : Int32, @name : String)
      end
    end

    # A cursed thing that would not come off again.
    class Welded < Event
      getter kind : String = "welded"

      getter item : Int32
      getter name : String

      def initialize(@item : Int32, @name : String)
      end
    end

    # Something taken out of a slot.
    class Removed < Event
      getter kind : String = "removed"

      @[JSON::Field(converter: Roguelike::Action::Slots)]
      getter slot : Slot

      getter item : Int32
      getter name : String

      def initialize(@slot : Slot, @item : Int32, @name : String)
      end
    end

    # A turn the character spent standing still.
    #
    # No line is written beside it. A line a turn would fill the log, and
    # anything written to the log stops a walk and a rest. A rest is a series
    # of these, and `Game#events` is where a bot reads them.
    class Waited < Event
      getter kind : String = "waited"

      def initialize
      end
    end
  end
end
