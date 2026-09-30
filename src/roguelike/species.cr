require "json"
require "../roguelike"

module Roguelike
  # Who fights whom.
  #
  # A faction is the unit that decides that. Every monster on a floor is
  # `Dungeon` for now, which is hostile to the character and to nothing else.
  # Goblins turning on slimes is a second member and a rule, not a rewrite.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Faction
    # Everything that lives down here. Hostile to the character.
    Dungeon

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

  # What a band knows about the character.
  #
  # This is a band's state rather than a monster's. Waking one member wakes
  # the band, which is how a pack calls out to each other. Every band holds
  # one creature for now, so waking a band and waking a monster come to the
  # same thing today.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Awareness
    # It has noticed nothing. It does not act.
    Asleep

    # It has noticed the character and cannot see them now. It knows where
    # they were.
    Alert

    # It can see the character.
    Hunting

    # Whether it acts at all.
    def awake? : Bool
      !asleep?
    end

    # What this is called, for a readout.
    def label : String
      case self
      in .asleep?  then "asleep"
      in .alert?   then "looking for you"
      in .hunting? then "hunting you"
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
    getter memory : Hash(String, Knowledge)

    # What it knows about the character.
    #
    # A band that has noticed nothing takes no turn. `Game#creatures_notice`
    # is the only method that writes this, apart from being hit, which wakes a
    # band whatever it had noticed.
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
  # *hit_dice* is what a creature placed by the generator rolls for its hit
  # points. `#hit_points` is their average, which is what a creature a floor
  # file or a spec names starts with.
  #
  # *light* is how often one carries something burning, out of a hundred.
  # *weapon* is the one weapon it always carries. A kind with no *weapon*
  # draws from `Loot::WEAPONS` *armed* times in a hundred.
  #
  # *depths* is the floors it appears on. `Spawns::TABLE` says how common it
  # is there. *alone* says a room holding one holds nothing else. *swing* is
  # what one of its attacks costs, in energy. *opens_doors* says it opens a
  # shut door by walking into it.
  record KindFacts,
    species : Species,
    mark : Char,
    label : String,
    plural : String,
    description : String,
    hit_dice : Dice,
    damage : Dice,
    armor : Int32,
    notice : Int32,
    darkvision : Bool,
    paths : Bool,
    experience : Int32,
    attributes : Attributes,
    persistence : Int32,
    depths : Range(Int32, Int32),
    size : Size = Size::Medium,
    speed : Int32 = Pace::NORMAL,
    swing : Int32 = Costs::TURN,
    opens_doors : Bool = false,
    verb : String = "hits",
    light : Int32 = 0,
    weapon : ItemKind? = nil,
    armed : Int32 = 0,
    alone : Bool = false,
    mends : Bool = false,
    casts : Bool = false do
    # Hit points of an average one.
    def hit_points : Int32
      hit_dice.average.round.to_i
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

    # The kind a bare species stands for.
    #
    # Each is the creature the species was before it had kinds, with the same
    # numbers, so an old save and a floor file mean what they always meant.
    def default : Kind
      case self
      in .slime?  then Kind::WhiteSlime
      in .goblin? then Kind::GoblinWarrior
      in .orc?    then Kind::Orc
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
    def hit_points : Int32
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

    # What this kind is. Every method below reads one field of it.
    def facts : KindFacts
      Kinds::FACTS[self]
    end

    # The family it belongs to.
    def species : Species
      facts.species
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

    # What a placed one rolls for its hit points.
    def hit_dice : Dice
      facts.hit_dice
    end

    # Hit points of an average one.
    def hit_points : Int32
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

    # Whether it heals a hurt neighbour of its own species.
    def mends? : Bool
      facts.mends
    end

    # Whether it throws a bolt. `Game#cast_bolt` is where that happens.
    def casts? : Bool
      facts.casts
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

    SLIMY = Attributes.new(strength: 8, dexterity: 4, constitution: 12,
      intelligence: 3, stealth: 6)

    FACTS = {
      Kind::WhiteSlime => KindFacts.new(Species::Slime, 'j', "white slime",
        "white slimes", "a pale puddle of acid that moves on its own",
        hit_dice: Dice.new(2, 4, 1), damage: Dice.new(1, 4), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 3,
        persistence: 4, speed: 80, attributes: SLIMY,
        depths: 1..3),

      Kind::BlueSlime => KindFacts.new(Species::Slime, 'j', "blue slime",
        "blue slimes", "a slow blue ooze, cold as meltwater, that numbs what it touches",
        hit_dice: Dice.new(2, 6, 4), damage: Dice.new(1, 4), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 5,
        persistence: 4, speed: 80, attributes: SLIMY, verb: "chills",
        depths: 1..4),

      Kind::RedSlime => KindFacts.new(Species::Slime, 'j', "red slime",
        "red slimes", "a steaming red ooze that scalds what it touches",
        hit_dice: Dice.new(2, 4, 1), damage: Dice.new(1, 8), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 6,
        persistence: 4, speed: 80, attributes: SLIMY, verb: "scalds",
        depths: 2..5),

      Kind::GreenSlime => KindFacts.new(Species::Slime, 'j', "green slime",
        "green slimes", "a bubbling green acid that eats through leather and skin",
        hit_dice: Dice.new(2, 6, 2), damage: Dice.new(2, 6), armor: 0,
        notice: 4, darkvision: false, paths: false, experience: 10,
        persistence: 4, speed: 80, attributes: SLIMY, verb: "eats at",
        depths: 3..5),

      Kind::GoblinScout => KindFacts.new(Species::Goblin, 'g', "goblin scout",
        "goblin scouts", "a wiry goblin with a dagger, alone and quick on its feet",
        hit_dice: Dice.new(2, 4, 2), damage: Dice.new(1, 4), armor: 0,
        notice: 10, darkvision: false, paths: true, experience: 5,
        size: Size::Small, persistence: 8, speed: 110,
        weapon: ItemKind::Dagger, light: 40, alone: true, opens_doors: true,
        depths: 1..2,
        attributes: Attributes.new(strength: 8, dexterity: 14, constitution: 9,
          intelligence: 8, stealth: 15)),

      Kind::GoblinWarrior => KindFacts.new(Species::Goblin, 'g', "goblin warrior",
        "goblin warriors", "a small green thing with a short sword",
        hit_dice: Dice.new(2, 4, 4), damage: Dice.new(1, 6), armor: 2,
        notice: 8, darkvision: false, paths: true, experience: 7,
        size: Size::Small, persistence: 6, opens_doors: true,
        weapon: ItemKind::ShortSword, light: 25,
        depths: 2..4,
        attributes: Attributes.new(strength: 10, dexterity: 13, constitution: 10,
          intelligence: 7, stealth: 13)),

      Kind::GoblinShaman => KindFacts.new(Species::Goblin, 'g', "goblin shaman",
        "goblin shamans", "a hunched goblin in bone charms who mends its kin",
        hit_dice: Dice.new(2, 4, 2), damage: Dice.new(1, 3), armor: 1,
        notice: 9, darkvision: false, paths: true, experience: 12,
        size: Size::Small, persistence: 8, light: 50,
        mends: true, casts: true, opens_doors: true,
        depths: 3..5,
        attributes: Attributes.new(strength: 7, dexterity: 11, constitution: 9,
          intelligence: 12, stealth: 11)),

      Kind::Orc => KindFacts.new(Species::Orc, 'o', "orc", "orcs",
        "a heavy gray brute with a notched blade",
        hit_dice: Dice.new(2, 6, 7), damage: Dice.new(1, 8), armor: 4,
        notice: 8, darkvision: true, paths: true, experience: 14,
        size: Size::Large, persistence: 30, speed: 95, swing: 120,
        armed: 90, light: 20, depths: 3..5, opens_doors: true,
        attributes: Attributes.new(strength: 14, dexterity: 10, constitution: 13,
          intelligence: 10, stealth: 8)),

      Kind::OrcArcher => KindFacts.new(Species::Orc, 'o', "orc archer",
        "orc archers", "a lean orc with a quiver and a long reach",
        hit_dice: Dice.new(2, 6, 4), damage: Dice.new(1, 6), armor: 3,
        notice: 10, darkvision: true, paths: true, experience: 16,
        size: Size::Large, persistence: 24, speed: 95, swing: 120,
        light: 10, depths: 4..5, opens_doors: true,
        attributes: Attributes.new(strength: 12, dexterity: 14, constitution: 12,
          intelligence: 10, stealth: 9)),
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
