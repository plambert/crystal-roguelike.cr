require "../roguelike"

module Roguelike
  # One part a beast can leave where it dies.
  #
  # *one_in* is the chance it is left, as one in that many deaths. *value*
  # is what one is worth, for a sort. *buff* and *power* are what eating a
  # fresh one gives. Both are empty on a part nothing eats.
  record PartFacts,
    kind : ItemKind,
    one_in : Int32,
    value : Int32,
    buff : Event::Status? = nil,
    power : Int32 = 0 do
    # Whether this part is eaten.
    def edible? : Bool
      kind.item_class.delicacy?
    end
  end

  # The parts each beast leaves beside its corpse, by chance.
  #
  # Only a beast leaves any. A humanoid is never butchered, so a goblin, an
  # orc and a werewolf leave none. Each species has one edible part at most
  # and one inedible part at most. The edible parts stand in for the cook's
  # recipes until there is a cook, so each buff is larger and lasts longer
  # than a buff from ordinary food.
  module Parts
    # How long a buff from a part lasts, in turns.
    BUFF_TURNS = 600

    TABLE = {
      Species::Wolf => [
        PartFacts.new(ItemKind::WolfLiver, 4, 20, Event::Status::Mending, 2),
        PartFacts.new(ItemKind::WolfFang, 4, 10),
      ],
      Species::Bear => [
        PartFacts.new(ItemKind::BearHeart, 4, 30, Event::Status::Mighty, 2),
        PartFacts.new(ItemKind::BearClaw, 4, 15),
      ],
      Species::Boar => [
        PartFacts.new(ItemKind::BoarLiver, 4, 20, Event::Status::Mending, 2),
        PartFacts.new(ItemKind::BoarTusk, 4, 15),
      ],
      Species::Snake => [
        PartFacts.new(ItemKind::SnakeEyes, 4, 25, Event::Status::NightEyes, 4),
        PartFacts.new(ItemKind::SnakeSkin, 4, 12),
      ],
      Species::Ant => [
        PartFacts.new(ItemKind::AntJelly, 4, 20, Event::Status::Quickened, 10),
        PartFacts.new(ItemKind::AntMandible, 4, 10),
      ],
      Species::Rat => [
        PartFacts.new(ItemKind::RatTail, 10, 3),
      ],
    }

    # The parts a creature of *kind* can leave. None for anything that is
    # not a beast.
    def self.of(kind : Kind) : Array(PartFacts)
      return [] of PartFacts unless kind.butchery.beast?

      TABLE[kind.species]? || [] of PartFacts
    end

    # The facts of the part *kind*. `nil` for anything that is not a part.
    def self.facts?(kind : ItemKind) : PartFacts?
      TABLE.each_value do |parts|
        parts.each { |part| return part if part.kind == kind }
      end
      nil
    end

    # The parts one death of *kind* leaves, rolled on *rng*.
    #
    # Every part the species has is rolled, the edible one first, so one
    # death can leave both or neither.
    def self.roll(kind : Kind, rng : Rng) : Array(Item)
      found = [] of Item
      of(kind).each do |part|
        next unless rng.rand(part.one_in).zero?

        found << Item.new(part.kind, blessing_known: true)
      end
      found
    end
  end
end
