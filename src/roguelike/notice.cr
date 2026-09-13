require "./attributes"
require "./species"

module Roguelike
  # Whether a creature notices the character.
  #
  # Nothing here holds state and nothing here reads a floor. Every number the
  # rule needs is an argument, so a spec asserts a species against a light
  # level without building a game around it.
  #
  # Four things decide it. Whether there is anything in the way, how far off
  # the character is, how much light is on the character's own square, and
  # how quietly the character moves. What the species is decides how the last
  # three are read.
  module Notice
    # Arm's reach: one square, diagonals counted.
    #
    # A reach never falls below this, and a creature notices a character
    # standing this close whatever their stealth, as long as there is light
    # on them.
    TOUCH = 1

    # How many squares of reach one point of light on the character adds.
    #
    # A torch lights the square its carrier stands on brightly, so carrying
    # one roughly triples how far a goblin notices them, and a creature
    # across a dark room picks the flame out at once. Somebody at the edge of
    # a sconce's pool is lit by one or two and is that much easier to see.
    # Somebody in the dark is not lit at all, and a species without
    # darkvision does not see them however close they stand.
    REACH_PER_LIGHT = 1

    # How far *species* notices a character of *stealth* standing on a square
    # lit to *light*.
    #
    # Stealth takes squares off: the modifier from `Attributes`, so a
    # character of average stealth standing in the dark is noticed at the
    # species' own reach. Light puts squares on, for a species that needs
    # light to see by, and a lit character is what such a species is looking
    # for. A species with darkvision reads the same reach in a lit room and
    # in a dark corridor, because the light is not what it is looking with.
    def self.reach(species : Species, stealth : Int32, light : Int32) : Int32
      found = species.notice - Attributes.modifier(stealth)
      found += light * REACH_PER_LIGHT unless species.darkvision?

      Math.max found, TOUCH
    end

    # Whether a creature of *species* standing at *from* notices a character
    # at *to*.
    #
    # *line* says whether the two have a line to each other. A creature
    # notices nothing through a wall.
    #
    # A species without darkvision sees by the light on what it is looking
    # at. A character standing on an unlit square is not noticed at all,
    # however close, so a goblin in a dark corridor can be walked past and
    # can be stabbed before it knows anything is there. Being hit wakes it,
    # which is `Game#wake` rather than a rule here.
    #
    # A character with light on them is noticed at arm's reach whatever
    # their stealth.
    def self.notices?(species : Species, stealth : Int32, light : Int32,
                      from : {Int32, Int32}, to : {Int32, Int32},
                      line : Bool = true) : Bool
      return false unless line
      return false if light <= 0 && !species.darkvision?
      return true if light > 0 && touching? from, to

      within? from, to, reach(species, stealth, light)
    end

    # Whether *from* and *to* are touching.
    #
    # One king move apart, or the same square. A diagonal counts, because a
    # creature standing diagonally beside the character can hit them.
    def self.touching?(from : {Int32, Int32}, to : {Int32, Int32}) : Bool
      Math.max((to[0] - from[0]).abs, (to[1] - from[1]).abs) <= TOUCH
    end

    # Whether *to* is within *reach* of *from*.
    #
    # Straight line distance, so a reach is round. That is how `FieldOfView`
    # cuts a radius and how a pool of light falls off, and a third shape
    # would be a third rule to keep track of.
    def self.within?(from : {Int32, Int32}, to : {Int32, Int32},
                     reach : Int32) : Bool
      across = to[0] - from[0]
      down = to[1] - from[1]

      across * across + down * down <= reach * reach
    end
  end
end
