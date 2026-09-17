require "json"
require "./attributes"
require "./dice"
require "./knowledge"

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

  # Everything one kind of monster is.
  #
  # No member here carries a glyph or a style. `Ui::Palette` holds both, the
  # same way it does for terrain. A theme changes that table. A spec reads a
  # monster with no terminal open.
  record SpeciesFacts,
    mark : Char,
    label : String,
    plural : String,
    description : String,
    hit_points : Int32,
    damage : Dice,
    armour : Int32,
    notice : Int32,
    darkvision : Bool,
    paths : Bool,
    experience : Int32,
    attributes : Attributes,
    persistence : Int32,
    size : Size = Size::Medium

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
  end

  # What sort of creature a monster is.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum Species
    Slime
    Goblin
    Orc

    # What this species is. Every method below reads one field of it.
    def facts : SpeciesFacts
      Kinds::FACTS[self]
    end

    # The character a floor file writes for one of these.
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

    # How much punishment one takes before it dies.
    def hit_points : Int32
      facts.hit_points
    end

    # What it does to whatever it hits.
    def damage : Dice
      facts.damage
    end

    # How much an attack on one is reduced by, before its dexterity.
    #
    # This is hide and scraps rather than a worn piece. Phase 20 gives a
    # monster armour it carries, and that adds to this.
    def armour : Int32
      facts.armour
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
    # A species with darkvision reads the same reach in a lit room and in a
    # dark corridor. One without it sees by the light on what it looks at,
    # and notices a character standing in the dark only in arm's reach.
    def darkvision? : Bool
      facts.darkvision
    end

    # Whether one works out a way round a wall.
    #
    # A species that paths descends its band's `Descent`. One that does not
    # walks straight at whatever it is after and comes up against whatever is
    # in the way.
    def paths? : Bool
      facts.paths
    end

    # What killing one is worth.
    def experience : Int32
      facts.experience
    end

    # What one is made of.
    def attributes : Attributes
      facts.attributes
    end

    # How many turns one goes on looking after it has lost the character.
    #
    # It walks to the square it last saw them on and casts about there until
    # this runs out, and then it gives up and goes back to sleep. This is what
    # decides whether a person can run away: an orc follows a cold trail for a
    # long time and a goblin gives up quickly.
    #
    # This is not intelligence. A goblin is quicker than an orc and knows
    # perfectly well where you went; it would simply rather not follow you.
    def persistence : Int32
      facts.persistence
    end

    # How often one steps somewhere other than the best square, as a
    # percentage of its steps.
    #
    # Inversely proportional to intelligence, so a slime blunders about and a
    # goblin rarely puts a foot wrong. Nothing is perfect: a creature that
    # never made a mistake would be a creature nobody could ever shake off in
    # open ground, whatever its persistence.
    def clumsiness : Int32
      (Kinds::CLUMSY - attributes.intelligence).clamp 0, 100
    end

    # Which species a floor file's *mark* names. `nil` for a character that
    # names none.
    def self.from_mark?(mark : Char) : Species?
      Kinds::MARKS[mark]?
    end
  end

  # The table behind `Species`. An enum body cannot hold it.
  module Kinds
    # The intelligence at which a creature stops putting a foot wrong.
    #
    # This lives here rather than in the enum because a name in an enum body
    # with a number after it is a member of the enum, not a constant.
    CLUMSY = 18

    FACTS = {
      Species::Slime => SpeciesFacts.new('j', "slime", "slimes",
        "a puddle of acid that moves on its own",
        hit_points: 6, damage: Dice.new(1, 4), armour: 0,
        notice: 4, darkvision: false, paths: false, experience: 3,
        size: Size::Medium, persistence: 4,
        attributes: Attributes.new(strength: 8, dexterity: 4, constitution: 12,
          intelligence: 3, stealth: 6)),

      Species::Goblin => SpeciesFacts.new('g', "goblin", "goblins",
        "a small green thing with a large knife",
        hit_points: 9, damage: Dice.new(1, 6), armour: 2,
        notice: 8, darkvision: false, paths: true, experience: 7,
        size: Size::Small, persistence: 6,
        attributes: Attributes.new(strength: 10, dexterity: 13, constitution: 10,
          intelligence: 7, stealth: 13)),

      Species::Orc => SpeciesFacts.new('o', "orc", "orcs",
        "a heavy grey brute with a notched blade",
        hit_points: 14, damage: Dice.new(1, 8), armour: 4,
        notice: 8, darkvision: true, paths: true, experience: 14,
        size: Size::Large, persistence: 30,
        attributes: Attributes.new(strength: 14, dexterity: 10, constitution: 13,
          intelligence: 10, stealth: 8)),
    }

    # Every character a floor file may hold for a monster.
    MARKS = begin
      table = {} of Char => Species
      FACTS.each { |species, facts| table[facts.mark] = species }
      table
    end
  end
end
