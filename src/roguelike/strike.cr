require "../roguelike"

module Roguelike
  # How an attack travels, which decides the defenses that apply to it.
  enum Reach
    # A blow in hand. Dodge and parry apply.
    Melee

    # A shot or a throw. Dodge and deflect apply.
    Missile

    # A wand bolt. Only dodge applies.
    Bolt
  end

  # What a defender's gear or kind does to an attacker whose blow it parried.
  record ParryEffect,
    # Rolled once the parry has stood.
    chance : Chance,
    # Energy the attacker loses.
    stun : Int32 = 0,
    # What the attacker takes, through its own DR.
    damage : Span? = nil

  # What an attacker brings to one attack.
  #
  # The builder folds flat and increased bonuses into `accuracy` and
  # `damage`, stacks `penetration`, and caps `crit` and `lucky`.
  record Offense,
    accuracy : Fixed,
    damage : Span,
    crit : Chance = Chance::NEVER,
    crit_multiplier : Ratio = Ratio::ONE,
    lucky : Chance = Chance::NEVER,
    penetration : Chance = Chance::NEVER,
    reach : Reach = Reach::Melee

  # What a defender brings to one attack.
  #
  # The builder stacks `dodge`, `parry` and `deflect`. `parry_effects` are
  # rolled in the order given.
  record Defense,
    ac : Fixed = Fixed::ZERO,
    dr : Fixed = Fixed::ZERO,
    dodge : Chance = Chance::NEVER,
    parry : Chance = Chance::NEVER,
    parry_effects : Array(ParryEffect) = [] of ParryEffect,
    deflect : Chance = Chance::NEVER,
    # Added to the attacker's lucky chance, in basis points.
    lucky_shift : Int32 = 0

  # One parry effect that fired.
  record Riposte,
    effect : ParryEffect,
    # What the attacker takes after its DR. Zero for an effect without
    # damage, or when the attacker is not adjacent.
    damage : Fixed

  # What one attack did, from `Combat.resolve`.
  #
  # It changes nobody. The game reads it and applies the damage and the
  # ripostes.
  struct Strike
    # What the to-hit, dodge, parry and deflect rolls settled.
    enum Outcome
      Hit
      Missed
      Dodged
      Parried
      Deflected
    end

    # What the to-hit, dodge, parry and deflect rolls settled. A lucky hit
    # keeps the reason it would have failed.
    getter outcome : Outcome

    # Whether the lucky roll turned a failure into a hit.
    getter? lucky : Bool

    # Whether the hit was a crit.
    getter? crit : Bool

    # The chance to hit, from accuracy and AC.
    getter hit_chance : Chance

    # The dodge chance it faced.
    getter dodge_chance : Chance

    # The parry chance for a blow, the deflect chance for a missile, and
    # nothing for a bolt.
    getter guard_chance : Chance

    # The lucky chance, after the defender's shift.
    getter lucky_chance : Chance

    # The crit chance.
    getter crit_chance : Chance

    # The damage rolled, times the crit multiplier. Zero when nothing landed.
    getter raw : Fixed

    # What the defender takes after DR.
    getter damage : Fixed

    # The defender's parry effects that fired.
    getter ripostes : Array(Riposte)

    def initialize(@outcome : Outcome, @lucky : Bool, @crit : Bool,
                   @hit_chance : Chance, @dodge_chance : Chance,
                   @guard_chance : Chance, @lucky_chance : Chance,
                   @crit_chance : Chance, @raw : Fixed, @damage : Fixed,
                   @ripostes : Array(Riposte))
    end

    # Whether the attack did damage, by passing every defense or by luck.
    def landed? : Bool
      @outcome.hit? || @lucky
    end

    # The energy the attacker loses to ripostes.
    def stun : Int32
      @ripostes.sum &.effect.stun
    end

    # The damage the attacker takes from ripostes.
    def recoil : Fixed
      @ripostes.reduce(Fixed::ZERO) { |total, riposte| total + riposte.damage }
    end
  end
end
