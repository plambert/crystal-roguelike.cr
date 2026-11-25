require "json"
require "../roguelike"

module Roguelike
  # Who fights whom.
  #
  # Every faction is hostile to the character. Goblins, orcs and the undead
  # are hostile to every faction but their own. Slimes, ants, jellies,
  # beasts and demons are hostile to everything, another band of their own
  # kind included. Constructs fight the character and nothing else, and
  # nothing else fights them. Members of one band never fight each other.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Faction
    # What an old save calls every band. Hostile to the character and to
    # nothing else.
    Dungeon

    Goblin
    Orc
    Slime
    Ant
    Jelly
    Beast
    Undead
    Demon
    Construct

    # Whether a band of this faction fights a band of *other*.
    #
    # Answers for two different bands. One band never fights itself.
    def hostile?(other : Faction) : Bool
      return false if aloof? || other.aloof?
      return true if wild? || other.wild?

      self != other
    end

    # Whether this faction fights every other band, its own kind included.
    def wild? : Bool
      slime? || ant? || jelly? || beast? || demon?
    end

    # Whether this faction fights the character and no other creature.
    def aloof? : Bool
      dungeon? || construct?
    end

    # What this faction is called.
    def label : String
      to_s.downcase
    end
  end

  # How the members of a band come by what they know.
  #
  # A band always has knowledge of its own: where its members have been,
  # between them, and where they last saw anybody. What each member does with
  # that is what this decides.
  #
  # A member always has knowledge of its own as well. The two are never the
  # same object, even under `Hive`, so that one creature walking into a room
  # can be told apart from the band having been told about it.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Sharing
    # The band's knowledge seeds each member's own, and the two go their own
    # ways after that. This is what most bands are.
    Inherited

    # What one member sees the band knows, and every other member knows it
    # in the same turn.
    Hive

    # Each member keeps its own and passes it to whichever members of the
    # band are near enough to be told.
    Called

    # Whether what one member learns reaches the others in the same turn.
    def instant? : Bool
      hive?
    end

    # Whether a member starts from what the band knows.
    def inherits? : Bool
      !called?
    end

    # What this is called, for a readout.
    def label : String
      to_s.downcase
    end
  end

  # What a band knows about the creatures it is hostile to.
  #
  # This is a band's state rather than a monster's. Waking one member wakes
  # the band, which is how a pack calls out to each other.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Awareness
    # It has noticed nothing. It does not act.
    Asleep

    # It has noticed something it is hostile to and cannot see it now. It
    # knows where it was.
    Alert

    # It can see something it is hostile to.
    Hunting

    # It has heard something and is waking. It takes no step this turn and
    # searches toward the sound after that.
    Stirring

    # It has given up the chase and is walking back to the square it
    # guards. It pays no heed to anything on the way and sleeps when it
    # gets there. Only a kind that `Kind#guards?` does this.
    Returning

    # Whether it acts at all.
    def awake? : Bool
      alert? || hunting? || returning?
    end

    # Whether it is after something it is hostile to.
    def fighting? : Bool
      alert? || hunting?
    end

    # What this is called, for a readout. *you* says the band knows where
    # the character is.
    def label(you : Bool = true) : String
      case self
      in .asleep?    then "asleep"
      in .alert?     then you ? "looking for you" : "searching"
      in .hunting?   then you ? "hunting you" : "hunting"
      in .stirring?  then "stirring"
      in .returning? then "returning to its post"
      end
    end
  end

  # A group of monsters that acts together.
  #
  # A band is the unit that shares what it knows. Nothing reads `#knowledge`
  # or `#sharing` yet: every monster is in a band of one until Phase 19 gives
  # a band a plan. Both are here now because adding a field to a serialized
  # type later means migrating save files.
  class Band
    include JSON::Serializable

    # What this band is called, for as long as the world lasts.
    getter id : String

    # Who it fights.
    getter faction : Faction

    # How its members come by what they know.
    getter sharing : Sharing

    # What the band knows, by floor id.
    #
    # Floors persist, so a band that has walked two of them remembers both.
    @[JSON::Field(converter: Roguelike::Sorted(Hash(String, Roguelike::Knowledge)))]
    getter memory : Hash(String, Knowledge)

    # What it knows about the creatures it is hostile to.
    #
    # A band that has noticed nothing takes no turn. `Game#creatures_notice`
    # is the only method that writes this, apart from being hit, which wakes a
    # band whatever it had noticed, and `Game#make_noise` and
    # `Game#creatures_stir`, which wake a band that hears a sound in two steps.
    property awareness : Awareness

    def initialize(@id : String, @faction : Faction = Faction::Dungeon,
                   @sharing : Sharing = Sharing::Inherited,
                   @memory : Hash(String, Knowledge) = {} of String => Knowledge,
                   @awareness : Awareness = Awareness::Asleep)
    end

    # Whether this band acts at all.
    def awake? : Bool
      @awareness.awake?
    end

    # Whether this band fights *other*.
    def hostile?(other : Band) : Bool
      !same?(other) && @faction.hostile?(other.faction)
    end

    # What the band knows of the floor *id*, empty until it learns something.
    def knowledge(id : String) : Knowledge
      @memory[id] ||= Knowledge.new id
    end

    # :ditto: Answers `nil` for a floor the band has never been on.
    def knowledge?(id : String) : Knowledge?
      @memory[id]?
    end

    def ==(other : Band) : Bool
      @id == other.id && @faction == other.faction &&
        @sharing == other.sharing && @memory == other.memory &&
        @awareness == other.awareness
    end

    def to_s(io : IO) : Nil
      io << "Band(" << @id << ' ' << @faction << ' ' << @sharing
      io << ' ' << @awareness << ')'
    end
  end

  # How big a creature is.
  #
  # This is what somebody makes out when they cannot see the creature itself.
  # A shape against light behind it has a size and nothing else, so the size
  # is what the map draws and what the readouts say.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Size
    Small
    Medium
    Large

    # The glyph a creature of this size draws as when it is only a shape.
    #
    # None of the three is a letter. A letter names a species, and somebody
    # who can only make out a shape has not been told which species it is.
    #
    # None of them is East Asian Ambiguous either. The map is a grid of one
    # cell per square, and a terminal set to draw ambiguous characters two
    # cells wide would tear that grid. `∙` is the bullet operator rather
    # than the bullet for that reason. The two look the same.
    def glyph : Char
      case self
      in .small?  then '∙'
      in .medium? then '▪'
      in .large?  then '◼'
      end
    end

    # What a shape this size is called, for a readout.
    def label : String
      case self
      in .small?  then "a small shape"
      in .medium? then "a shape"
      in .large?  then "a large shape"
      end
    end

    # The word a piece of armor cut for this size carries in its name.
    def word : String
      to_s.downcase
    end

    # What a shape this size is called where there is only a column.
    #
    # `Ui::Naming` shortens an item to fit the sidebar. A creature nobody has
    # made out goes in the same column, so its size is shortened the same
    # way and to the same three letters.
    def short : String
      case self
      in .small?  then "sml shape"
      in .medium? then "med shape"
      in .large?  then "lrg shape"
      end
    end
  end

  # Everything one kind of monster is.
  #
  # No member here carries a style. `Ui::Palette` holds the colour, the same
  # way it does for terrain. A spec reads a monster with no terminal open.
  #
  # *health* is the span a creature placed by the generator rolls its hit
  # points from. `#hit_points` is its midpoint, which is what a creature a
  # floor file or a spec names starts with.
  #
  # *light* is how often one carries something burning, out of a hundred.
  # *weapon* is the one weapon it always carries. A kind with no *weapon*
  # draws from `Loot::WEAPONS` *armed* times in a hundred.
  #
  # *ranged_weapon* is the ranged weapon it carries, and *quiver* is how much
  # ammunition for it. `Loot` rolls both.
  #
  # *depths* is the floors it appears on. `Spawns::TABLE` says how common it
  # is there. *alone* says a room holding one holds nothing else. *swing* is
  # what one of its attacks costs, in energy. *opens_doors* says it opens a
  # shut door by walking into it. *faction* is who a band of them fights.
  # *flees* says it runs when badly hurt.
  # *wields* says it readies a weapon and armor, and picks up better ones it
  # steps on.
  #
  # *sharing* is how a band of them shares what it knows. *surrounds* says
  # one beside its quarry moves round to face a bandmate across it. *splits*
  # says one buds off a copy of itself now and then.
  #
  # *leash* is how many steps from the square it was placed on one chases
  # before it turns back, and zero for a kind that guards nothing.
  # *batters* says it breaks a shut door down rather than opening it.
  # *heals* says it gains back hit points as time passes. *weakness* is the
  # effect of a wand that does it far more harm than it does anything else.
  record KindFacts,
    species : Species,
    mark : Char,
    label : String,
    plural : String,
    description : String,
    health : Span,
    damage : Dice,
    armor : Int32,
    notice : Int32,
    darkvision : Bool,
    paths : Bool,
    experience : Int32,
    attributes : Attributes,
    persistence : Int32,
    depths : Range(Int32, Int32),
    faction : Faction,
    size : Size = Size::Medium,
    speed : Int32 = Pace::NORMAL,
    swing : Int32 = Costs::TURN,
    opens_doors : Bool = false,
    flees : Bool = false,
    verb : String = "hits",
    light : Int32 = 0,
    weapon : ItemKind? = nil,
    armed : Int32 = 0,
    ranged_weapon : ItemKind? = nil,
    quiver : Dice = Dice::NONE,
    alone : Bool = false,
    mends : Bool = false,
    casts : Bool = false,
    wields : Bool = false,
    sharing : Sharing = Sharing::Inherited,
    surrounds : Bool = false,
    splits : Bool = false,
    hide : Bulk = Bulk::Medium,
    garb : ItemKind? = nil,
    remains : Remains? = nil,
    butchery : Butchery? = nil,
    leash : Int32 = 0,
    batters : Bool = false,
    heals : Bool = true,
    weakness : Effect? = nil do
    # Hit points of an average one.
    def hit_points : Fixed
      health.mean
    end
  end

  # What family of creature a monster is.
  #
  # Every `Kind` belongs to one. A save file written before kinds existed
  # names a species and loads as that species' `#default` kind.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Species
    Slime
    Goblin
    Orc
    Ant
    Jelly
    Rat
    Wolf
    Bear
    Boar
    Snake
    Undead
    Imp
    Cube
    Golem

    # The kind a bare species stands for.
    #
    # Each is the creature the species was before it had kinds, with the same
    # numbers, so an old save and a floor file mean what they always meant.
    def default : Kind
      case self
      in .slime?  then Kind::WhiteSlime
      in .goblin? then Kind::GoblinWarrior
      in .orc?    then Kind::Orc
      in .ant?    then Kind::Ant
      in .jelly?  then Kind::Jelly
      in .rat?    then Kind::Rat
      in .wolf?   then Kind::Wolf
      in .bear?   then Kind::Bear
      in .boar?   then Kind::Boar
      in .snake?  then Kind::GiantSnake
      in .undead? then Kind::Zombie
      in .imp?    then Kind::Imp
      in .cube?   then Kind::GelatinousCube
      in .golem?  then Kind::StoneGolem
      end
    end

    # What one of these leaves where it dies.
    #
    # Beasts, goblins, orcs and ants leave a corpse. Slimes, jellies,
    # constructs and imps leave nothing. The undead leave rotten flesh and
    # bones. `Kind#remains` lets a kind say otherwise, and a skeleton does.
    def remains : Remains
      case self
      in .slime?, .jelly?, .imp?, .cube?, .golem? then Remains::Nothing
      in .goblin?, .orc?, .ant?                   then Remains::Corpse
      in .rat?, .wolf?, .bear?, .boar?, .snake?   then Remains::Corpse
      in .undead?                                 then Remains::FleshAndBones
      end
    end

    # Whether a corpse of one of these is cut into meat. `Kind#butchery`
    # lets a kind say otherwise, and a werewolf does.
    def butchery : Butchery
      case self
      in .rat?, .wolf?, .bear?, .boar?, .snake?, .ant?      then Butchery::Beast
      in .goblin?, .orc?                                    then Butchery::Humanoid
      in .slime?, .jelly?, .imp?, .cube?, .golem?, .undead? then Butchery::None
      end
    end

    # Every kind of this species, in the order `Kind` names them.
    def kinds : Array(Kind)
      Kind.values.select &.species.== self
    end

    # What one of these is called, whatever kind it is.
    def label : String
      to_s.downcase
    end

    # The facts of the default kind.
    def facts : KindFacts
      default.facts
    end

    # The default kind's `Kind#mark`.
    def mark : Char
      default.mark
    end

    # The default kind's `Kind#plural`.
    def plural : String
      default.plural
    end

    # The default kind's `Kind#description`.
    def description : String
      default.description
    end

    # The default kind's `Kind#hit_points`.
    def hit_points : Fixed
      default.hit_points
    end

    # The default kind's `Kind#damage`.
    def damage : Dice
      default.damage
    end

    # The default kind's `Kind#armor`.
    def armor : Int32
      default.armor
    end

    # The default kind's `Kind#size`.
    def size : Size
      default.size
    end

    # The default kind's `Kind#notice`.
    def notice : Int32
      default.notice
    end

    # The default kind's `Kind#darkvision?`.
    def darkvision? : Bool
      default.darkvision?
    end

    # The default kind's `Kind#paths?`.
    def paths? : Bool
      default.paths?
    end

    # The default kind's `Kind#experience`.
    def experience : Int32
      default.experience
    end

    # The default kind's `Kind#attributes`.
    def attributes : Attributes
      default.attributes
    end

    # The default kind's `Kind#speed`.
    def speed : Int32
      default.speed
    end

    # The default kind's `Kind#persistence`.
    def persistence : Int32
      default.persistence
    end

    # The default kind's `Kind#clumsiness`.
    def clumsiness : Int32
      default.clumsiness
    end

    # Which species a floor file's *mark* names. `nil` for a character that
    # names none.
    def self.from_mark?(mark : Char) : Species?
      Kinds::MARKS[mark]?.try &.species
    end
  end

  # What sort of creature a monster is: a species and a variant of it.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Kind
    WhiteSlime
    BlueSlime
    RedSlime
    GreenSlime
    GoblinScout
    GoblinWarrior
    GoblinShaman
    Orc
    OrcArcher
    Ant
    Jelly
    Rat
    GiantRat
    Wolf
    Werewolf
    Bear
    Boar
    GiantSnake
    Skeleton
    Zombie
    Imp
    GelatinousCube
    StoneGolem
    IronGolem
    OrcWarlord
    GoblinSkirmisher

    # What this kind is. Every method below reads one field of it.
    def facts : KindFacts
      Kinds::FACTS[self]
    end

    # The family it belongs to.
    def species : Species
      facts.species
    end

    # What one of these leaves where it dies. Its species decides, unless
    # the kind says otherwise.
    def remains : Remains
      facts.remains || species.remains
    end

    # Whether a corpse of this kind is cut into meat. Its species decides,
    # unless the kind says otherwise.
    def butchery : Butchery
      facts.butchery || species.butchery
    end

    # The character it draws as. Every kind of a species shares the letter.
    def mark : Char
      facts.mark
    end

    # What one of these is called.
    def label : String
      facts.label
    end

    # What several are called.
    def plural : String
      facts.plural
    end

    # A sentence about it, for the examine pane.
    def description : String
      facts.description
    end

    # The span a placed one rolls its hit points from.
    def health : Span
      facts.health
    end

    # Hit points of an average one.
    def hit_points : Fixed
      facts.hit_points
    end

    # What it does to whatever it hits.
    def damage : Dice
      facts.damage
    end

    # The word for its blow landing: "The blue slime chills you for 3."
    def verb : String
      facts.verb
    end

    # How much an attack on one is reduced by, before its dexterity.
    #
    # This is hide and scraps rather than a worn piece.
    def armor : Int32
      facts.armor
    end

    # How big one is. What somebody who can only make out a shape sees.
    def size : Size
      facts.size
    end

    # How far one notices a character of average stealth on a square with no
    # light on it, before `Notice` adjusts either.
    def notice : Int32
      facts.notice
    end

    # Whether one sees without light.
    #
    # A kind with darkvision reads the same reach in a lit room and in a dark
    # corridor. One without it sees by the light on what it looks at, and
    # notices a character standing in the dark only in arm's reach.
    def darkvision? : Bool
      facts.darkvision
    end

    # Whether one works out a way round a wall.
    #
    # A kind that paths descends its band's `Descent`. One that does not
    # walks straight at whatever it is after.
    def paths? : Bool
      facts.paths
    end

    # Whether one opens a shut door by walking into it.
    #
    # Opening takes its turn, the same as it does for the character, and it
    # steps through on the next. A band whose members open doors paths
    # through a door it remembers as shut.
    def opens_doors? : Bool
      facts.opens_doors
    end

    # Whether one runs from the character when it is badly hurt.
    #
    # Below a quarter of its hit points it runs, and it turns back once it
    # has more than half. A slime has no sense of danger and never does.
    def flees? : Bool
      facts.flees
    end

    # What killing one is worth.
    def experience : Int32
      facts.experience
    end

    # What one is made of.
    def attributes : Attributes
      facts.attributes
    end

    # What one of these gains in a tick.
    #
    # `Pace::NORMAL` is the character's own speed. `--trial-speed` replaces
    # every kind's speed with its own.
    def speed : Int32
      Kinds.override || facts.speed
    end

    # What one of its attacks costs, in energy.
    def swing : Int32
      facts.swing
    end

    # How many turns one goes on looking after it has lost the character.
    #
    # It walks to the square it last saw them on and casts about there until
    # this runs out. An orc follows a cold trail for a long time and a goblin
    # gives up quickly.
    def persistence : Int32
      facts.persistence
    end

    # How often one steps somewhere other than the best square, as a
    # percentage of its steps.
    #
    # Falls as intelligence rises, so a slime blunders about and a goblin
    # rarely puts a foot wrong.
    def clumsiness : Int32
      (Kinds::CLUMSY - attributes.intelligence).clamp 0, 100
    end

    # The floors it appears on, shallowest first.
    def depths : Range(Int32, Int32)
      facts.depths
    end

    # Whether it appears on the floor at *depth*.
    def appears_at?(depth : Int32) : Bool
      depths.includes? depth
    end

    # Whether a room holding one holds nothing else.
    def alone? : Bool
      facts.alone
    end

    # How often one carries something burning, out of a hundred.
    def light : Int32
      facts.light
    end

    # The weapon it always carries. `nil` for one that draws or has none.
    def weapon : ItemKind?
      facts.weapon
    end

    # How often one without a `#weapon` carries one, out of a hundred.
    def armed : Int32
      facts.armed
    end

    # Whether it readies a weapon and armor, and picks up better ones.
    def wields? : Bool
      facts.wields
    end

    # The ranged weapon it carries. `nil` for one that shoots nothing.
    def ranged_weapon : ItemKind?
      facts.ranged_weapon
    end

    # How much ammunition for its `#ranged_weapon` it carries.
    def quiver : Dice
      facts.quiver
    end

    # Who a band of these fights.
    def faction : Faction
      facts.faction
    end

    # Whether it heals a hurt neighbour of its own species.
    def mends? : Bool
      facts.mends
    end

    # Whether it throws a bolt. `Game#cast_bolt` is where that happens.
    def casts? : Bool
      facts.casts
    end

    # How a band of these shares what it knows.
    def sharing : Sharing
      facts.sharing
    end

    # Whether one beside its quarry moves to face a bandmate across it.
    def surrounds? : Bool
      facts.surrounds
    end

    # Whether one buds off a copy of itself. `Game#split` is where.
    def splits? : Bool
      facts.splits
    end

    # What its own body counts as, for the cost of a step, when it wears no
    # body armor. Body armor it puts on counts instead.
    #
    # Medium walks at a normal pace, which is what every kind did before
    # armor had a weight. A hide adds nothing to a blow.
    def hide : Bulk
      facts.hide
    end

    # The body armor it always wears. `nil` for one that draws or has none.
    def garb : ItemKind?
      facts.garb
    end

    # How many steps from its post one chases before it turns back. Zero
    # for a kind that guards nothing.
    #
    # The steps are walked, not counted across rock. `Game#keep_post` reads
    # them.
    def leash : Int32
      facts.leash
    end

    # Whether one sleeps on a post, wakes only when somebody is beside it,
    # and walks back to the post when a chase takes it past `#leash`.
    def guards? : Bool
      leash > 0
    end

    # Whether one breaks a shut door down rather than opening it.
    def batters? : Bool
      facts.batters
    end

    # Whether one gains back hit points as time passes.
    def heals? : Bool
      facts.heals
    end

    # The effect of a wand that does one far more harm than it does anything
    # else. `nil` for a kind with no such weakness.
    def weakness : Effect?
      facts.weakness
    end

    # Which kind a floor file's *mark* names: the default kind of the species
    # with that letter. `nil` for a character that names none.
    def self.from_mark?(mark : Char) : Kind?
      Kinds::MARKS[mark]?
    end
  end

  # The table behind `Kind`. An enum body cannot hold it.
  module Kinds
    # What every kind moves at instead of its own speed, or `nil`.
    #
    # `--trial-speed` sets this and nothing else does. A run with this set is
    # a measurement rather than a game.
    class_property override : Int32? = nil

    # The intelligence at which a creature stops putting a foot wrong.
    CLUMSY = 18

    # How many steps from its post a golem chases before it turns back.
    #
    # Far enough to cross a room and come out the other side, and short
    # enough that a character can lead one away and lose it.
    LEASH = 8

    SLIMY = Attributes.new(strength: 8, dexterity: 4, constitution: 12,
      intelligence: 3, stealth: 6)

    FACTS = {
      Kind::WhiteSlime => KindFacts.new(Species::Slime, 'j', "white slime",
        "white slimes", "a pale puddle of acid that moves on its own",
        health: Span.whole(3, 9, Spread::Centered), damage: Dice.new(1, 4), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 3,
        persistence: 4, speed: 80, attributes: SLIMY,
        depths: 1..3, faction: Faction::Slime),

      Kind::BlueSlime => KindFacts.new(Species::Slime, 'j', "blue slime",
        "blue slimes", "a slow blue ooze, cold as meltwater, that numbs what it touches",
        health: Span.whole(6, 16, Spread::Centered), damage: Dice.new(1, 4), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 5,
        persistence: 4, speed: 80, attributes: SLIMY, verb: "chills",
        depths: 1..5, faction: Faction::Slime),

      Kind::RedSlime => KindFacts.new(Species::Slime, 'j', "red slime",
        "red slimes", "a steaming red ooze that scalds what it touches",
        health: Span.whole(3, 9, Spread::Centered), damage: Dice.new(1, 8), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 6,
        persistence: 4, speed: 80, attributes: SLIMY, verb: "scalds",
        depths: 2..7, faction: Faction::Slime),

      Kind::GreenSlime => KindFacts.new(Species::Slime, 'j', "green slime",
        "green slimes", "a bubbling green acid that eats through leather and skin",
        health: Span.whole(4, 14, Spread::Centered), damage: Dice.new(2, 6), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 10,
        persistence: 4, speed: 80, attributes: SLIMY, verb: "eats at",
        depths: 3..8, faction: Faction::Slime),

      Kind::GoblinScout => KindFacts.new(Species::Goblin, 'g', "goblin scout",
        "goblin scouts", "a wiry goblin with a sling and a dagger, alone and quick on its feet",
        health: Span.whole(4, 10, Spread::Centered), damage: Dice.new(1, 4), armor: -2,
        notice: 10, darkvision: false, paths: true, experience: 5,
        size: Size::Small, persistence: 8, speed: 110,
        weapon: ItemKind::Dagger, light: 40, alone: true, opens_doors: true,
        flees: true, wields: true,
        ranged_weapon: ItemKind::Sling, quiver: Dice.new(1, 4, 1),
        depths: 1..2, faction: Faction::Goblin, garb: ItemKind::LeatherArmor,
        attributes: Attributes.new(strength: 8, dexterity: 14, constitution: 9,
          intelligence: 8, stealth: 15)),

      # The member keeps its old name so that saves and replays still load.
      Kind::GoblinWarrior => KindFacts.new(Species::Goblin, 'g', "goblin fighter",
        "goblin fighters", "a stocky goblin in chain mail with a mace, slow to strike and slow to fall",
        health: Span.whole(8, 14, Spread::Centered), damage: Dice.new(1, 6), armor: -2,
        notice: 8, darkvision: false, paths: true, experience: 7,
        size: Size::Small, persistence: 6, opens_doors: true, flees: true, wields: true,
        weapon: ItemKind::Mace, light: 25,
        depths: 2..6, faction: Faction::Goblin, garb: ItemKind::ChainMail,
        attributes: Attributes.new(strength: 10, dexterity: 13, constitution: 10,
          intelligence: 7, stealth: 13)),

      Kind::GoblinShaman => KindFacts.new(Species::Goblin, 'g', "goblin shaman",
        "goblin shamans", "a hunched goblin in bone charms who mends its kin",
        health: Span.whole(4, 10, Spread::Centered), damage: Dice.new(1, 3), armor: 1,
        notice: 9, darkvision: false, paths: true, experience: 12,
        size: Size::Small, persistence: 8, light: 50,
        mends: true, casts: true, opens_doors: true, flees: true, wields: true,
        depths: 3..7, faction: Faction::Goblin,
        attributes: Attributes.new(strength: 7, dexterity: 11, constitution: 9,
          intelligence: 12, stealth: 11)),

      Kind::Orc => KindFacts.new(Species::Orc, 'o', "orc", "orcs",
        "a heavy gray brute with a notched blade",
        health: Span.whole(9, 19, Spread::Centered), damage: Dice.new(1, 8), armor: 4,
        notice: 8, darkvision: true, paths: true, experience: 14,
        size: Size::Medium, persistence: 30, speed: 95, swing: 120,
        armed: 90, light: 20, depths: 3..10, opens_doors: true,
        flees: true, wields: true, faction: Faction::Orc,
        attributes: Attributes.new(strength: 14, dexterity: 10, constitution: 13,
          intelligence: 10, stealth: 8)),

      Kind::OrcArcher => KindFacts.new(Species::Orc, 'o', "orc archer",
        "orc archers", "a lean orc with a bow and a quiver of arrows",
        health: Span.whole(6, 16, Spread::Centered), damage: Dice.new(1, 6), armor: 3,
        notice: 10, darkvision: true, paths: true, experience: 16,
        size: Size::Medium, persistence: 24, speed: 95, swing: 120,
        light: 10, depths: 4..10, opens_doors: true, flees: true, wields: true,
        ranged_weapon: ItemKind::Bow, quiver: Dice.new(3, 6),
        faction: Faction::Orc,
        attributes: Attributes.new(strength: 12, dexterity: 14, constitution: 12,
          intelligence: 10, stealth: 9)),

      Kind::Ant => KindFacts.new(Species::Ant, 'a', "giant ant", "giant ants",
        "a dog-sized ant that hunts with its nestmates and comes at you from every side",
        health: Span.whole(1, 6, Spread::Centered), damage: Dice.new(1, 3), armor: 2,
        notice: 7, darkvision: false, paths: true, experience: 3,
        size: Size::Small, persistence: 12, speed: 130, verb: "bites",
        sharing: Sharing::Hive, surrounds: true,
        depths: 2..7, faction: Faction::Ant,
        attributes: Attributes.new(strength: 10, dexterity: 11, constitution: 8,
          intelligence: 6, stealth: 14)),

      Kind::Jelly => KindFacts.new(Species::Jelly, 'J', "violet jelly",
        "violet jellies", "a quivering violet mass that buds off copies of itself",
        health: Span.whole(3, 12, Spread::Centered), damage: Dice.new(1, 6), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 6,
        size: Size::Large, persistence: 4, speed: 60, verb: "stings",
        alone: true, splits: true,
        depths: 3..9, faction: Faction::Jelly,
        attributes: Attributes.new(strength: 10, dexterity: 6, constitution: 14,
          intelligence: 2, stealth: 4)),

      Kind::Rat => KindFacts.new(Species::Rat, 'r', "rat", "rats",
        "a gray rat as long as your forearm, never alone and quick to run",
        health: Span.whole(1, 6, Spread::Centered), damage: Dice.new(1, 3), armor: 0,
        notice: 8, darkvision: false, paths: true, experience: 2,
        size: Size::Small, persistence: 6, speed: 120, verb: "bites",
        flees: true, depths: 1..3, faction: Faction::Beast, hide: Bulk::None,
        attributes: Attributes.new(strength: 6, dexterity: 13, constitution: 8,
          intelligence: 5, stealth: 15)),

      Kind::GiantRat => KindFacts.new(Species::Rat, 'r', "giant rat",
        "giant rats", "a rat the size of a small dog, with yellow teeth and a filthy bite",
        health: Span.whole(4, 10, Spread::Centered), damage: Dice.new(1, 4), armor: 1,
        notice: 8, darkvision: false, paths: true, experience: 4,
        size: Size::Small, persistence: 8, speed: 115, verb: "bites",
        flees: true, depths: 2..4, faction: Faction::Beast, hide: Bulk::None,
        attributes: Attributes.new(strength: 9, dexterity: 13, constitution: 10,
          intelligence: 5, stealth: 13)),

      Kind::Wolf => KindFacts.new(Species::Wolf, 'd', "wolf", "wolves",
        "a lean gray wolf that hunts with its pack and circles to your back",
        health: Span.whole(2, 12, Spread::Centered), damage: Dice.new(1, 4), armor: 1,
        notice: 11, darkvision: true, paths: true, experience: 8,
        persistence: 20, speed: 120, verb: "bites",
        flees: true, surrounds: true, sharing: Sharing::Called,
        depths: 3..6, faction: Faction::Beast, hide: Bulk::None,
        attributes: Attributes.new(strength: 11, dexterity: 14, constitution: 12,
          intelligence: 8, stealth: 14)),

      Kind::Werewolf => KindFacts.new(Species::Wolf, 'd', "werewolf", "werewolves",
        "a wolf too large and too clever to be only a wolf, that leads the pack",
        health: Span.whole(11, 33, Spread::Centered), damage: Dice.new(2, 4), armor: 4,
        notice: 12, darkvision: true, paths: true, experience: 40,
        persistence: 40, speed: 125, verb: "bites",
        opens_doors: true, surrounds: true, sharing: Sharing::Called,
        depths: 6..10, faction: Faction::Beast, hide: Bulk::Light,
        butchery: Butchery::Humanoid,
        attributes: Attributes.new(strength: 15, dexterity: 14, constitution: 14,
          intelligence: 10, stealth: 13)),

      Kind::Bear => KindFacts.new(Species::Bear, 'B', "bear", "bears",
        "a huge brown bear that does not like being woken",
        health: Span.whole(13, 35, Spread::Centered), damage: Dice.new(2, 6), armor: 3,
        notice: 9, darkvision: false, paths: true, experience: 30,
        size: Size::Large, persistence: 15, swing: 120, verb: "mauls",
        alone: true, depths: 5..8, faction: Faction::Beast, hide: Bulk::Heavy,
        attributes: Attributes.new(strength: 18, dexterity: 9, constitution: 16,
          intelligence: 5, stealth: 8)),

      Kind::Boar => KindFacts.new(Species::Boar, 'q', "boar", "boars",
        "a bristling wild boar with tusks like knives, that fights until it drops",
        health: Span.whole(4, 23, Spread::Centered), damage: Dice.new(1, 6), armor: 3,
        notice: 7, darkvision: false, paths: true, experience: 14,
        size: Size::Large, persistence: 10, speed: 110, verb: "gores",
        depths: 3..6, faction: Faction::Beast, hide: Bulk::Medium,
        attributes: Attributes.new(strength: 13, dexterity: 10, constitution: 14,
          intelligence: 4, stealth: 9)),

      Kind::GiantSnake => KindFacts.new(Species::Snake, 'S', "giant snake",
        "giant snakes", "a snake as thick as your leg that lies still until you are close",
        health: Span.whole(8, 24, Spread::Centered), damage: Dice.new(1, 8), armor: 3,
        notice: 8, darkvision: false, paths: true, experience: 20,
        size: Size::Large, persistence: 8, speed: 90, verb: "bites",
        alone: true, depths: 4..7, faction: Faction::Beast, hide: Bulk::Light,
        attributes: Attributes.new(strength: 14, dexterity: 12, constitution: 14,
          intelligence: 4, stealth: 16)),

      Kind::Skeleton => KindFacts.new(Species::Undead, 'Z', "skeleton",
        "skeletons", "a rattling skeleton that walks without a mind and often carries an old blade",
        health: Span.whole(4, 14, Spread::Centered), damage: Dice.new(1, 6), armor: 3,
        notice: 6, darkvision: true, paths: false, experience: 8,
        persistence: 50, speed: 90, verb: "claws",
        armed: 50, wields: true, depths: 2..5, faction: Faction::Undead, hide: Bulk::Light,
        remains: Remains::Bones,
        attributes: Attributes.new(strength: 11, dexterity: 11, constitution: 10,
          intelligence: 3, stealth: 10)),

      Kind::Zombie => KindFacts.new(Species::Undead, 'Z', "zombie", "zombies",
        "a shambling corpse that is slow, hard to stop and never gives up",
        health: Span.whole(7, 22, Spread::Centered), damage: Dice.new(1, 8), armor: 1,
        notice: 5, darkvision: true, paths: false, experience: 9,
        persistence: 60, speed: 70, swing: 120, verb: "claws",
        depths: 2..5, faction: Faction::Undead, hide: Bulk::Heavy,
        attributes: Attributes.new(strength: 14, dexterity: 6, constitution: 16,
          intelligence: 2, stealth: 6)),

      Kind::Imp => KindFacts.new(Species::Imp, 'i', "imp", "imps",
        "a tiny red devil with leathery wings, quick, spiteful and hard to hit",
        health: Span.whole(5, 11, Spread::Centered), damage: Dice.new(1, 4), armor: 3,
        notice: 10, darkvision: true, paths: true, experience: 10,
        size: Size::Small, persistence: 12, speed: 140, verb: "claws",
        opens_doors: true, flees: true, alone: true,
        depths: 4..7, faction: Faction::Demon, hide: Bulk::None,
        attributes: Attributes.new(strength: 8, dexterity: 17, constitution: 10,
          intelligence: 12, stealth: 15)),

      Kind::GelatinousCube => KindFacts.new(Species::Cube, 'C', "gelatinous cube",
        "gelatinous cubes", "a clear quivering block that fills the passage, with old things floating inside it",
        health: Span.whole(19, 47, Spread::Centered), damage: Dice.new(2, 6), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 20,
        size: Size::Large, persistence: 10, speed: 55, verb: "burns",
        alone: true, depths: 5..8, faction: Faction::Jelly, hide: Bulk::VeryHeavy,
        attributes: Attributes.new(strength: 14, dexterity: 6, constitution: 18,
          intelligence: 1, stealth: 16)),

      Kind::StoneGolem => KindFacts.new(Species::Golem, 'G', "stone golem",
        "stone golems", "a slow giant of carved stone that guards this place and nothing else",
        health: Span.whole(20, 52, Spread::Centered), damage: Dice.new(2, 8), armor: 6,
        notice: 10, darkvision: true, paths: true, experience: 45,
        size: Size::Large, persistence: 100, speed: 60, swing: 120, verb: "pounds",
        alone: true, depths: 6..10, faction: Faction::Construct, hide: Bulk::VeryHeavy,
        leash: Kinds::LEASH, batters: true, heals: false,
        attributes: Attributes.new(strength: 18, dexterity: 10, constitution: 18,
          intelligence: 1, stealth: 6)),

      Kind::IronGolem => KindFacts.new(Species::Golem, 'G', "iron golem",
        "iron golems", "a towering figure of black iron that walks with a sound like a forge",
        health: Span.whole(28, 60, Spread::Centered), damage: Dice.new(2, 8), armor: 8,
        notice: 10, darkvision: true, paths: true, experience: 80,
        size: Size::Large, persistence: 100, speed: 55, swing: 130, verb: "pounds",
        alone: true, depths: 8..10, faction: Faction::Construct, hide: Bulk::VeryHeavy,
        leash: Kinds::LEASH, batters: true, heals: false, weakness: Effect::Strike,
        attributes: Attributes.new(strength: 20, dexterity: 10, constitution: 20,
          intelligence: 1, stealth: 4)),
      Kind::OrcWarlord => KindFacts.new(Species::Orc, 'o', "orc warlord",
        "orc warlords", "a huge orc in black iron who guards the amulet with a sworn band",
        health: Span.whole(47, 83, Spread::Centered), damage: Dice.new(1, 10), armor: 5,
        notice: 12, darkvision: true, paths: true, experience: 250,
        size: Size::Large, persistence: 80, speed: 100, swing: 120,
        weapon: ItemKind::LongSword, light: 100, opens_doors: true, wields: true,
        depths: World::VAULT..World::VAULT, faction: Faction::Orc,
        attributes: Attributes.new(strength: 18, dexterity: 12, constitution: 16,
          intelligence: 12, stealth: 8)),

      # Labeled "goblin warrior". `Loot::GARBS` rolls what it wears.
      Kind::GoblinSkirmisher => KindFacts.new(Species::Goblin, 'g', "goblin warrior",
        "goblin warriors", "a wiry goblin with a dagger, quick to close and quick to stab, and easy to hurt",
        health: Span.whole(3, 9, Spread::Centered), damage: Dice.new(1, 4), armor: -2,
        notice: 9, darkvision: false, paths: true, experience: 5,
        size: Size::Small, persistence: 8, speed: 110,
        weapon: ItemKind::Dagger, light: 30, opens_doors: true, flees: true, wields: true,
        depths: 1..4, faction: Faction::Goblin,
        attributes: Attributes.new(strength: 11, dexterity: 15, constitution: 8,
          intelligence: 7, stealth: 14)),
    }

    # Every character a floor file may hold for a monster, and the kind it
    # names. A letter names the default kind of its species.
    MARKS = begin
      table = {} of Char => Kind
      Species.each { |species| table[species.default.mark] = species.default }
      table
    end
  end
end
