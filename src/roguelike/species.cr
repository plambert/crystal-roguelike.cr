require "json"
require "./attributes"
require "./dice"

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

  # A group of monsters that acts together.
  #
  # A band is the unit that shares what it knows. Nothing reads that yet:
  # every monster is in a band of one until Phase 19 gives a band a
  # `Knowledge` and a plan. The field is here now because adding it to a
  # serialized type later means migrating save files.
  class Band
    include JSON::Serializable

    # What this band is called, for as long as the world lasts.
    getter id : String

    # Who it fights.
    getter faction : Faction

    def initialize(@id : String, @faction : Faction = Faction::Dungeon)
    end

    def ==(other : Band) : Bool
      @id == other.id && @faction == other.faction
    end

    def to_s(io : IO) : Nil
      io << "Band(" << @id << ' ' << @faction << ')'
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
    experience : Int32,
    attributes : Attributes

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

    # What killing one is worth.
    def experience : Int32
      facts.experience
    end

    # What one is made of.
    def attributes : Attributes
      facts.attributes
    end

    # Which species a floor file's *mark* names. `nil` for a character that
    # names none.
    def self.from_mark?(mark : Char) : Species?
      Kinds::MARKS[mark]?
    end
  end

  # The table behind `Species`. An enum body cannot hold it.
  module Kinds
    FACTS = {
      Species::Slime => SpeciesFacts.new('j', "slime", "slimes",
        "a puddle of acid that moves on its own",
        hit_points: 6, damage: Dice.new(1, 4), experience: 3,
        attributes: Attributes.new(strength: 8, dexterity: 4, constitution: 12,
          intelligence: 3, stealth: 6)),

      Species::Goblin => SpeciesFacts.new('g', "goblin", "goblins",
        "a small green thing with a large knife",
        hit_points: 9, damage: Dice.new(1, 6), experience: 7,
        attributes: Attributes.new(strength: 10, dexterity: 13, constitution: 10,
          intelligence: 9, stealth: 13)),

      Species::Orc => SpeciesFacts.new('o', "orc", "orcs",
        "a heavy grey brute with a notched blade",
        hit_points: 14, damage: Dice.new(1, 8), experience: 14,
        attributes: Attributes.new(strength: 14, dexterity: 10, constitution: 13,
          intelligence: 8, stealth: 8)),
    }

    # Every character a floor file may hold for a monster.
    MARKS = begin
      table = {} of Char => Species
      FACTS.each { |species, facts| table[facts.mark] = species }
      table
    end
  end
end
