require "../roguelike"

module Roguelike
  # Which creatures live how deep, and how many of them.
  #
  # `Generator` reads this and nothing else to decide what a room holds. The
  # table is data. A new kind is a new row.
  module Spawns
    # One kind of creature and how common it is.
    #
    # *weight* is relative to every other row whose kind appears on the same
    # floor. Which floors those are is the kind's own `Kind#depths`.
    #
    # *crowd* is how many a room holds when this kind is the first one
    # rolled. `nil` reads the floor's `Density#crowd`.
    #
    # *first_floor* is its weight on floor 1 in place of *weight*. `nil`
    # keeps *weight* there too.
    record Row, kind : Kind, weight : Int32, crowd : Range(Int32, Int32)? = nil,
      first_floor : Int32? = nil do
      # Its weight on the floor at *depth*.
      def weight_at(depth : Int32) : Int32
        depth == 1 ? @first_floor || @weight : @weight
      end
    end

    # Every creature the generator may put on a floor.
    #
    # Floor 1 holds white and blue slimes, rat packs and goblin scouts.
    # Goblin scouts and rats are rarer on floor 1 than below it. Ants come in
    # bands of three to five from floor 2. Giant rats, skeletons and zombies
    # join them on floor 2. Orcs, wolves, boars and a lone jelly come from
    # floor 3, the orc archer, imps and giant snakes from floor 4, and bears
    # and gelatinous cubes from floor 5.
    #
    # The slimes, goblins, ants and the shallow beasts give out between
    # floors 5 and 9. Werewolves and stone golems hold floors 6 to 9, and
    # iron golems floors 8 to 10. Floor 10 holds orcs, orc archers and iron
    # golems. The iron golem's weight is high so that floor 10 is not left
    # to the orcs alone.
    #
    # The orc warlord appears only in the amulet chamber, which is built
    # rather than dug, so its row is never rolled.
    TABLE = [
      Row.new(Kind::WhiteSlime, 40),
      Row.new(Kind::BlueSlime, 20),
      Row.new(Kind::RedSlime, 20),
      Row.new(Kind::GreenSlime, 15),
      Row.new(Kind::GoblinScout, 30, first_floor: 10),
      Row.new(Kind::GoblinWarrior, 45),
      Row.new(Kind::GoblinShaman, 15),
      Row.new(Kind::Orc, 15),
      Row.new(Kind::OrcArcher, 10),
      Row.new(Kind::Ant, 20, crowd: 3..5),
      Row.new(Kind::Jelly, 10),
      Row.new(Kind::Rat, 20, crowd: 2..4, first_floor: 10),
      Row.new(Kind::GiantRat, 15, crowd: 2..3),
      Row.new(Kind::Wolf, 12, crowd: 2..3),
      Row.new(Kind::Werewolf, 8),
      Row.new(Kind::Bear, 8),
      Row.new(Kind::Boar, 12, crowd: 1..2),
      Row.new(Kind::GiantSnake, 10),
      Row.new(Kind::Skeleton, 12),
      Row.new(Kind::Zombie, 12),
      Row.new(Kind::Imp, 10),
      Row.new(Kind::GelatinousCube, 8),
      Row.new(Kind::StoneGolem, 10),
      Row.new(Kind::IronGolem, 24),
      Row.new(Kind::OrcWarlord, 1),
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
      Density.new(55, 2..3),
      Density.new(55, 2..3),
      Density.new(65, 2..4),
      Density.new(65, 2..4),
      Density.new(60, 3..5),
      Density.new(65, 3..5),
    ]

    # What each kind is worth on the floor at *depth*.
    #
    # *species* keeps only that species. *alone* false keeps only the kinds
    # that go about in company. Empty for a depth no kind appears at.
    def self.weights(depth : Int32, species : Species? = nil,
                     alone : Bool? = nil) : Hash(Kind, Int32)
      found = Hash(Kind, Int32).new 0

      TABLE.each do |row|
        kind = row.kind
        next unless kind.appears_at? depth
        next if species && kind.species != species
        next if !alone.nil? && kind.alone? != alone

        found[kind] += row.weight_at depth
      end

      found
    end

    # One kind for the floor at *depth*, rolled on *rng*.
    def self.pick(rng : Rng, depth : Int32) : Kind
      Items.pick rng, weights(depth)
    end

    # How many creatures a room whose first creature is *kind* holds, on the
    # floor at *depth*.
    def self.crowd(kind : Kind, depth : Int32) : Range(Int32, Int32)
      TABLE.find(&.kind.== kind).try(&.crowd) || density(depth).crowd
    end

    # How full the floor at *depth* is.
    def self.density(depth : Int32) : Density
      DENSITY[(depth - 1).clamp(0, DENSITY.size - 1)]
    end
  end
end
