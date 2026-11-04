require "json"
require "../roguelike"

module Roguelike
  # Which family a food belongs to. The family sets the buff eating it gives.
  #
  # A member is never removed and never reordered. A save file holds the
  # member name.
  enum FoodCategory
    # Fresh and dried meat, sausage and a corpse. Eating it adds pace.
    Meat

    # Apples, berries and dried fruit. Thirst builds at half rate.
    Fruit

    # Rations, bread and oatcakes. The most filling, with no buff.
    Grain

    # Nuts and cheese. A steadier hand with a bow or a sling.
    NutsAndCheese

    # Roots, herbs and mushrooms. A steadier hand in melee.
    RootsAndHerbs

    # Rotten flesh. Nothing eats it.
    Refuse

    # A part of a beast. Each kind gives a buff of its own, which
    # `Parts::TABLE` holds.
    Delicacy

    # What the family is called, for a readout and a sort.
    def label : String
      case self
      in .meat?            then "meat"
      in .fruit?           then "fruit"
      in .grain?           then "grain"
      in .nuts_and_cheese? then "nuts and cheese"
      in .roots_and_herbs? then "roots and herbs"
      in .refuse?          then "refuse"
      in .delicacy?        then "delicacy"
      end
    end

    # The buff eating a fresh one gives. `nil` for a family with none.
    def buff : Event::Status?
      case self
      in .meat?            then Event::Status::WellFed
      in .fruit?           then Event::Status::Refreshed
      in .grain?           then nil
      in .nuts_and_cheese? then Event::Status::SteadyAim
      in .roots_and_herbs? then Event::Status::SteadyHand
      in .refuse?          then nil
      in .delicacy?        then nil
      end
    end
  end

  # How far a food has gone off.
  enum Freshness
    Fresh
    Stale
    Rotten

    # The word that goes in a name. `nil` for fresh food.
    def label : String?
      case self
      in .fresh?  then nil
      in .stale?  then "stale"
      in .rotten? then "rotten"
      end
    end

    # The word for this freshness, fresh included. It takes the place of
    # "fresh" in a name that holds it.
    def word : String
      to_s.downcase
    end

    # What a bite of food this fresh is worth, as a percentage.
    def worth : Int32
      case self
      in .fresh?  then 100
      in .stale?  then 50
      in .rotten? then 25
      end
    end
  end

  # What a dead creature leaves where it fell.
  #
  # A member is never removed and never reordered.
  enum Remains
    # Nothing. A slime, a construct and an imp.
    Nothing

    # A corpse that can be eaten or cut up.
    Corpse

    # Rotten flesh and bones. An undead creature with flesh on it.
    FleshAndBones

    # Bones. An undead creature without flesh.
    Bones
  end

  # Whether a creature's corpse is cut into meat.
  #
  # A member is never removed and never reordered.
  enum Butchery
    # Cuts into meat. Rats, wolves, bears, boars, snakes and ants.
    Beast

    # Never cut. Goblins and orcs, and any human, elf, dwarf, gnome or
    # primate. Its corpse can be eaten where it lies, at the cost of a
    # point of maximum hit points for each meal.
    Humanoid

    # Leaves no corpse to cut. Slimes, jellies, imps, constructs and the
    # undead.
    None
  end

  # Everything one kind of food is.
  #
  # *satiety* is how much one feeds, in the points `Sustenance#eat` takes.
  # *keeps* is how many turns it stays fresh. It turns stale then, and
  # rotten at twice that. Zero means it never spoils. *value* is what it is
  # worth, for a sort.
  record FoodFacts,
    category : FoodCategory,
    satiety : Int32,
    keeps : Int32,
    value : Int32 do
    # Whether this kind ever spoils.
    def spoils? : Bool
      keeps > 0
    end

    # How fresh one of these is at *age* turns.
    def freshness(age : Int32) : Freshness
      return Freshness::Fresh unless spoils?
      return Freshness::Fresh if age < keeps
      return Freshness::Stale if age < keeps * 2

      Freshness::Rotten
    end
  end

  # The facts of every food, and the rules that read them.
  module Food
    # How long a buff from food lasts, in turns.
    BUFF_TURNS = 300

    # How long eating rotten food makes the character sick, in turns.
    SICK_TURNS = 300

    # What the meat buff adds to the character's speed.
    PACE = 5

    # What the aim buffs add to a swing or a shot landing.
    AIM = 1

    # What being sick takes off a swing or a shot landing.
    SICK_AIM = 1

    # How many turns a corpse on the floor stays fresh. It turns stale then,
    # and rots away at twice that.
    CORPSE_KEEPS = 150

    FACTS = {
      ItemKind::Ration  => FoodFacts.new(FoodCategory::Grain, 1500, 0, 12),
      ItemKind::Bread   => FoodFacts.new(FoodCategory::Grain, 1200, 1500, 6),
      ItemKind::Oatcake => FoodFacts.new(FoodCategory::Grain, 800, 4000, 5),

      ItemKind::FreshMeat => FoodFacts.new(FoodCategory::Meat, 900, 300, 8),
      ItemKind::DriedMeat => FoodFacts.new(FoodCategory::Meat, 700, 5000, 10),
      ItemKind::Sausage   => FoodFacts.new(FoodCategory::Meat, 800, 1500, 8),

      ItemKind::Apple      => FoodFacts.new(FoodCategory::Fruit, 400, 2000, 3),
      ItemKind::DriedFruit => FoodFacts.new(FoodCategory::Fruit, 500, 6000, 6),
      ItemKind::Berries    => FoodFacts.new(FoodCategory::Fruit, 250, 600, 2),

      ItemKind::Nuts   => FoodFacts.new(FoodCategory::NutsAndCheese, 500, 8000, 5),
      ItemKind::Cheese => FoodFacts.new(FoodCategory::NutsAndCheese, 700, 3000, 7),

      ItemKind::Turnip   => FoodFacts.new(FoodCategory::RootsAndHerbs, 500, 4000, 2),
      ItemKind::Herbs    => FoodFacts.new(FoodCategory::RootsAndHerbs, 150, 800, 4),
      ItemKind::Mushroom => FoodFacts.new(FoodCategory::RootsAndHerbs, 300, 1200, 3),

      ItemKind::Corpse      => FoodFacts.new(FoodCategory::Meat, 1000, CORPSE_KEEPS, 0),
      ItemKind::RottenFlesh => FoodFacts.new(FoodCategory::Refuse, 0, 0, 0),

      ItemKind::WolfLiver => FoodFacts.new(FoodCategory::Delicacy, 250, 300, 20),
      ItemKind::BearHeart => FoodFacts.new(FoodCategory::Delicacy, 300, 300, 30),
      ItemKind::BoarLiver => FoodFacts.new(FoodCategory::Delicacy, 250, 300, 20),
      ItemKind::SnakeEyes => FoodFacts.new(FoodCategory::Delicacy, 100, 300, 25),
      ItemKind::AntJelly  => FoodFacts.new(FoodCategory::Delicacy, 150, 600, 20),
    }

    # What lies about a floor, by weight. Fresh meat comes from corpses and
    # is not here.
    LITTER = {
      ItemKind::Ration     => 10,
      ItemKind::Bread      => 12,
      ItemKind::Oatcake    => 8,
      ItemKind::DriedMeat  => 10,
      ItemKind::Sausage    => 6,
      ItemKind::Apple      => 10,
      ItemKind::DriedFruit => 6,
      ItemKind::Berries    => 6,
      ItemKind::Nuts       => 8,
      ItemKind::Cheese     => 6,
      ItemKind::Turnip     => 8,
      ItemKind::Herbs      => 6,
      ItemKind::Mushroom   => 6,
    }

    # How many food items a floor starts with, per ten thousand squares of
    # open floor. A floor of 8000 squares, which is about the mean, holds
    # four, and about 2800 points of satiety between them. Every floor holds
    # one at least.
    PER_TEN_THOUSAND = 5

    # What a corpse of each size feeds, eaten where it lies.
    CORPSE_SATIETY = {
      Size::Small  => 400,
      Size::Medium => 1000,
      Size::Large  => 1600,
    }

    # How many pieces of fresh meat a corpse of each size cuts into.
    CUTS = {
      Size::Small  => 1,
      Size::Medium => 2,
      Size::Large  => 4,
    }

    # What a corpse of each size weighs. No corpse fits in the bag.
    CORPSE_WEIGHT = {
      Size::Small  => 50,
      Size::Medium => 150,
      Size::Large  => 400,
    }

    # The facts of *kind*. `nil` for anything that is not food.
    def self.facts?(kind : ItemKind) : FoodFacts?
      FACTS[kind]?
    end

    # :ditto:
    def self.facts(kind : ItemKind) : FoodFacts
      FACTS[kind]
    end

    # The buff eating a fresh *kind* gives. A part of a beast gives its own,
    # and other food gives its family's. `nil` for food with none.
    def self.buff(kind : ItemKind) : Event::Status?
      Parts.facts?(kind).try(&.buff) || facts(kind).category.buff
    end
  end
end
