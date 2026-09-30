require "../roguelike"

module Roguelike
  # Which creatures live how deep, and how many of them.
  #
  # `Generator` reads this and nothing else to decide what a room holds. The
  # table is data. A new species, or a variant of one, is a new row.
  module Spawns
    # One kind of creature and the floors it lives on.
    #
    # *weight* is how common it is on each of those floors, relative to every
    # other row that covers the same floor. A species may have several rows,
    # one per stretch of depths, when it grows commoner the deeper it is.
    # Rows for one species on one floor add up.
    record Row, species : Species, depths : Range(Int32, Int32), weight : Int32

    # Every creature the generator may put on a floor.
    #
    # Floor 1 is slimes and goblins. Orcs start on floor 2 and grow common
    # from floor 4.
    TABLE = [
      Row.new(Species::Slime, 1..5, 40),
      Row.new(Species::Goblin, 1..5, 45),
      Row.new(Species::Orc, 2..3, 12),
      Row.new(Species::Orc, 4..5, 25),
    ]

    # How often a room holds a creature, and how many it holds.
    #
    # *inhabited* is out of a hundred. *crowd* is how many creatures such a
    # room holds.
    record Density, inhabited : Int32, crowd : Range(Int32, Int32)

    # How full each floor is, from floor 1 down. A floor deeper than the
    # last entry reads the last entry.
    DENSITY = [
      Density.new(40, 1..2),
      Density.new(45, 1..2),
      Density.new(50, 1..2),
      Density.new(50, 1..3),
      Density.new(55, 1..3),
    ]

    # What each species is worth on the floor at *depth*.
    #
    # Empty for a depth no row covers.
    def self.weights(depth : Int32) : Hash(Species, Int32)
      found = Hash(Species, Int32).new 0
      TABLE.each do |row|
        found[row.species] += row.weight if row.depths.includes? depth
      end
      found
    end

    # One species for the floor at *depth*, rolled on *rng*.
    def self.pick(rng : Rng, depth : Int32) : Species
      Items.pick rng, weights(depth)
    end

    # How full the floor at *depth* is.
    def self.density(depth : Int32) : Density
      DENSITY[(depth - 1).clamp(0, DENSITY.size - 1)]
    end
  end
end
