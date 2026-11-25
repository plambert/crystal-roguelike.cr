require "json"
require "../roguelike"

module Roguelike
  # What one swing did.
  #
  # A blow is the record of a roll. It changes nobody. `Game` reads one and
  # takes the hit points off. A spec reads one and asserts the maths.
  struct Blow
    include JSON::Serializable

    # The face the die came up.
    getter roll : Int32

    # What the attacker added to the face.
    getter bonus : Int32

    # The armor class the swing was against.
    getter against : Int32

    # Whether it landed.
    getter? hit : Bool

    # Hit points taken off. Zero on a miss.
    getter damage : Int32

    def initialize(@roll : Int32, @bonus : Int32, @against : Int32,
                   @hit : Bool, @damage : Int32)
    end

    # `#damage` in the unit hit points are kept in.
    def harm : Fixed
      Fixed.whole @damage
    end

    # The face and the bonus together.
    def total : Int32
      @roll + @bonus
    end

    # Whether the die came up on the face that always lands.
    def critical? : Bool
      @roll >= Combat::CRITICAL
    end

    # Whether it came up on the face that never lands.
    def fumble? : Bool
      @roll <= Combat::FUMBLE
    end

    def to_s(io : IO) : Nil
      io << "Blow(d" << Combat::SIDES << ' ' << @roll
      io << '+' << @bonus if @bonus > 0
      io << @bonus if @bonus < 0
      io << " vs " << @against << ' '
      io << (@hit ? "hit #{@damage}" : "miss")
      io << ')'
    end
  end

  # How a swing is decided.
  #
  # One twenty sided die, plus what the attacker adds, against the defender's
  # armor class. `TARGET` is the number a swing at an unarmored defender has
  # to reach. Armor class is added to it, so a better defended creature needs
  # a higher face.
  #
  # Two faces decide on their own. `CRITICAL` always lands and `FUMBLE` never
  # does. Without them a well armored creature is unhittable by a weak
  # attacker, and an unarmored one is unmissable by a strong one.
  #
  # Nothing here holds state. Every value the maths needs is an argument, so a
  # spec asserts a swing without building a game around it.
  module Combat
    # How many sides the die has.
    SIDES = 20

    # The number a swing at an unarmored defender has to reach.
    TARGET = 10

    # The face that always lands.
    CRITICAL = 20

    # The face that never lands.
    FUMBLE = 1

    # The least damage a landed swing does.
    LEAST = 1

    # What an attacker adds to its swing when the target is flanked.
    FLANKING = 2

    # The square across *target* from *attacker*.
    #
    # It is *attacker*'s square reflected through *target*'s, so a diagonal
    # neighbour's opposite is the other end of that diagonal.
    def self.opposite(attacker : {Int32, Int32},
                      target : {Int32, Int32}) : {Int32, Int32}
      {2 * target[0] - attacker[0], 2 * target[1] - attacker[1]}
    end

    # Whether an attacker at *attacker* flanks the target at *target*.
    #
    # It does when the square across the target holds another creature that
    # is fighting the same target. The block answers that for a square. The
    # rule is the same whoever the target is, so the character and a
    # monster are flanked alike.
    def self.flanks?(attacker : {Int32, Int32}, target : {Int32, Int32},
                     & : {Int32, Int32} -> Bool) : Bool
      yield opposite(attacker, target)
    end

    # What *attacker* adds to a swing at *target* for flanking it.
    def self.flanking(attacker : {Int32, Int32}, target : {Int32, Int32},
                      & : {Int32, Int32} -> Bool) : Int32
      flanks?(attacker, target) { |spot| yield spot } ? FLANKING : 0
    end

    # Whether a face of *roll* plus *bonus* lands on armor class *against*.
    def self.lands?(roll : Int32, bonus : Int32, against : Int32) : Bool
      return true if roll >= CRITICAL
      return false if roll <= FUMBLE

      roll + bonus >= TARGET + against
    end

    # One swing, rolled on *rng*.
    #
    # The face is rolled first and the damage second. A miss rolls no damage,
    # so a miss and a hit draw a different count of values. Each swing is
    # given a generator of its own, so that difference shifts nothing after
    # it.
    def self.swing(rng : Rng, bonus : Int32, against : Int32,
                   damage : Dice) : Blow
      roll = rng.rand 1..SIDES
      return Blow.new roll, bonus, against, false, 0 unless lands? roll, bonus, against

      Blow.new roll, bonus, against, true, damage(rng, damage)
    end

    # What a blow that lands with *damage* takes off. Never less than
    # `LEAST`.
    #
    # A blow at a door rolls this alone. A door does not dodge.
    def self.damage(rng : Rng, damage : Dice) : Int32
      Math.max damage.roll(rng), LEAST
    end

    # The armor class a damage rate is worked out against when there is no
    # creature to read one from. A goblin in small leather armor.
    REFERENCE = 2

    # The chance that a swing adding *bonus* lands on armor class *against*,
    # from 0 to 1. It counts the faces `#lands?` lets through.
    def self.hit_chance(bonus : Int32, against : Int32) : Float64
      (1..SIDES).count { |roll| lands? roll, bonus, against } / SIDES
    end

    # What a blow of *dice* takes off when it lands, on average.
    #
    # Every total is counted, with `LEAST` for any below it, so a 1d2-1 fist
    # averages one and not a half.
    def self.mean_damage(dice : Dice) : Float64
      totals = {0 => 1_i64}
      dice.count.times do
        rolled = Hash(Int32, Int64).new 0_i64
        totals.each do |total, ways|
          (1..dice.sides).each { |face| rolled[total + face] += ways }
        end
        totals = rolled
      end

      ways = totals.values.sum
      totals.sum { |total, count| Math.max(total + dice.bonus, LEAST) * count } / ways
    end

    # What an attacker does in one turn of the world: the chance to land,
    # times what a landed blow takes off, times the blows a turn gives.
    #
    # *cost* is what one blow costs in energy, with the armor in it. This is
    # what the game shows as "dps".
    def self.per_turn(bonus : Int32, against : Int32, dice : Dice, cost : Int32) : Float64
      hit_chance(bonus, against) * mean_damage(dice) * Costs::TURN / cost
    end

    # What a shooter adds to a shot from *weapon* with *ammunition*.
    #
    # *modifier* is the shooter's dexterity modifier. What each of the two
    # adds goes on top. A masterwork bow and a bent arrow both count, and so
    # does a blessing on either. The character and a monster aim alike.
    def self.aim(modifier : Int32, weapon : Item, ammunition : Item) : Int32
      modifier + weapon.aim + ammunition.aim
    end

    # What a shot of *ammunition* from *weapon* hits for.
    #
    # The ammunition's dice, which already carry its own enchantment and its
    # condition, plus the weapon's enchantment and condition. Strength adds
    # nothing. The bow throws the arrow, not the arm.
    def self.shot(weapon : Item, ammunition : Item) : Dice
      ammunition.damage.with_bonus weapon.enchantment + weapon.condition.modifier
    end

    # The least accuracy the hit curve reads.
    LEAST_ACCURACY = Fixed.new 100

    # The least AC the hit curve reads.
    LEAST_AC = Fixed.new 10

    # The share of a blow that always gets through DR.
    SOAK_FLOOR = Ratio.new 2_000

    # Accuracy from a flat sum and an increased sum, `flat × (1 + increased)`.
    def self.accuracy(flat : Fixed, increased : Ratio) : Fixed
      flat.clamp_positive * Ratio.new(Math.max(Ratio::SCALE + increased.value, 0))
    end

    # The chance that *accuracy* hits *ac*, `A / (A + AC)`.
    #
    # Both are held to their floors, and the result to 1 to 9,999 basis
    # points, so a hit is never certain or impossible.
    def self.hit_chance(accuracy : Fixed, ac : Fixed) : Chance
      reach = Math.max(accuracy, LEAST_ACCURACY).value.to_i64
      guard = Math.max(ac, LEAST_AC).value.to_i64
      odds = FixedPoint.divide reach * Chance::SCALE, reach + guard

      Chance.new odds.clamp(1_i64, Chance::SCALE - 1_i64).to_i32
    end

    # Whether *chance* comes up on one draw from *rng*.
    def self.rolls?(rng : Rng, chance : Chance) : Bool
      rng.below(Chance::SCALE) < chance.value
    end

    # What a blow of *blow* takes off through *dr*, with *penetration*.
    #
    # Penetration leaves `R = DR × (1 - penetration)`. One even draw soaks
    # from `R / 2` to `3R / 2`. At least `SOAK_FLOOR` of the blow gets
    # through. The draw is taken even when `R` is zero.
    def self.soak(rng : Rng, blow : Fixed, dr : Fixed, penetration : Chance) : Fixed
      blow = blow.clamp_positive
      left = FixedPoint.divide dr.clamp_positive.value.to_i64 * penetration.complement.value,
        Chance::SCALE.to_i64
      steps = Span::STEPS.to_i64
      soaked = FixedPoint.divide left * (steps + Spread::Even.draw(rng) * 2), steps * 2

      through = Fixed.new (blow.value - soaked).to_i32
      Math.max through, blow * SOAK_FLOOR
    end

    # One attack of *offense* on *defense*, rolled on *rng*.
    #
    # The rolls run in order: to hit, dodge, then parry for a blow or deflect
    # for a missile. The first that fails the attack settles the outcome. A
    # failed attack then rolls lucky once, and a lucky hit goes on as a hit.
    # A hit rolls crit, then damage, then soak. A parry that stood rolls each
    # of the defender's parry effects.
    #
    # Every step that applies takes its draw, whatever its chance. An attack
    # that stops early draws fewer values.
    #
    # *attacker_dr* soaks riposte damage. A riposte does damage only when the
    # attacker is *adjacent*. Its stun reaches the attacker regardless.
    def self.resolve(rng : Rng, offense : Offense, defense : Defense, *,
                     attacker_dr : Fixed = Fixed::ZERO, adjacent : Bool = true) : Strike
      hit = hit_chance offense.accuracy, defense.ac
      guard = guard_chance offense.reach, defense
      lucky = Chance.clamped offense.lucky.value.to_i64 + defense.lucky_shift

      outcome = defend rng, hit, defense.dodge, guard, offense.reach
      lucky_hit = !outcome.hit? && rolls?(rng, lucky)

      unless outcome.hit? || lucky_hit
        ripostes = outcome.parried? ? riposte(rng, defense, attacker_dr, adjacent) : [] of Riposte
        return Strike.new outcome, false, false, hit, defense.dodge, guard, lucky,
          offense.crit, Fixed::ZERO, Fixed::ZERO, ripostes
      end

      crit = rolls? rng, offense.crit
      raw = offense.damage.roll rng
      raw *= Ratio.new(Math.max(offense.crit_multiplier.value, 0)) if crit
      damage = soak rng, raw, defense.dr, offense.penetration

      Strike.new outcome, lucky_hit, crit, hit, defense.dodge, guard, lucky,
        offense.crit, raw, damage, [] of Riposte
    end

    # One attack with today's numbers, `#swing`'s *bonus*, *against* and
    # *damage*, rolled on the new rules. See `StandIn`.
    def self.stand_in(rng : Rng, bonus : Int32, against : Int32, damage : Dice,
                      reach : Reach = Reach::Melee) : Strike
      resolve rng, StandIn.offense(bonus, against, damage, reach), StandIn.defense
    end

    # Today's d20 numbers carried onto `Offense` and `Defense`, until kinds
    # and items have stats of their own.
    #
    # The chance to land and the mean damage of every attack match the d20
    # swing. The lucky roll stands in for the natural 20, which is one face
    # in twenty. Every defender has the same AC. The attacker's accuracy is
    # set from the faces that land against the defender's armor class, so
    # the hit curve passes the share of the other nineteen faces that land.
    # Nothing dodges, parries, deflects, crits or soaks.
    module StandIn
      # The AC every defender has. It is large, so the accuracy floor of 1.0
      # hits it on one basis point.
      AC = Fixed.whole 10_000

      # The natural 20.
      LUCKY = Chance.new Chance::SCALE // SIDES

      # The attack of a d20 swing with *bonus* on armor class *against*,
      # hitting for *damage*.
      def self.offense(bonus : Int32, against : Int32, damage : Dice,
                       reach : Reach = Reach::Melee) : Offense
        Offense.new accuracy(bonus, against), span(damage), lucky: LUCKY, reach: reach
      end

      # What every defender brings.
      def self.defense : Defense
        Defense.new ac: AC
      end

      # The accuracy that hits `AC` as often as the faces from 2 to 19 that
      # land, out of those eighteen, `AC × (faces − 1) / (20 − faces)`.
      def self.accuracy(bonus : Int32, against : Int32) : Fixed
        faces = (1..SIDES).count { |roll| Combat.lands? roll, bonus, against }
        Fixed.new FixedPoint.divide(AC.value.to_i64 * (faces - 1), (SIDES - faces).to_i64).to_i32
      end

      # A span with the mean of *dice*, `LEAST` included.
      #
      # Dice whose lowest total is at least `LEAST` keep their range. One die
      # is `Even` and more than one is `Centered`. Dice that can roll below
      # `LEAST` keep their highest total and move the low end to match the
      # mean.
      def self.span(dice : Dice) : Span
        spread = dice.count > 1 ? Spread::Centered : Spread::Even
        return Span.whole(dice.minimum, dice.maximum, spread) if dice.minimum >= LEAST
        return Span.whole(LEAST, LEAST, spread) if dice.maximum <= LEAST

        mean = mean(dice).value
        high = Fixed.whole(dice.maximum).value
        low = 2 * mean - high
        return Span.new(Fixed::ZERO, Fixed.new(2 * mean), spread) if low < 0

        Span.new Fixed.new(low), Fixed.new(high), spread
      end

      # The mean of *dice*, with `LEAST` for any total below it.
      def self.mean(dice : Dice) : Fixed
        totals = {0 => 1_i64}
        dice.count.times do
          rolled = Hash(Int32, Int64).new 0_i64
          totals.each do |total, ways|
            (1..dice.sides).each { |face| rolled[total + face] += ways }
          end
          totals = rolled
        end

        ways = totals.values.sum
        sum = totals.sum { |total, count| Math.max(total + dice.bonus, LEAST).to_i64 * count }
        Fixed.new FixedPoint.divide(sum * Fixed::SCALE, ways).to_i32
      end
    end

    # The parry chance for a blow, the deflect chance for a missile, and
    # none for a bolt.
    private def self.guard_chance(reach : Reach, defense : Defense) : Chance
      case reach
      in .melee?   then defense.parry
      in .missile? then defense.deflect
      in .bolt?    then Chance::NEVER
      end
    end

    # Steps 1 to 3 of the roll order, stopping at the first failure.
    private def self.defend(rng : Rng, hit : Chance, dodge : Chance,
                            guard : Chance, reach : Reach) : Strike::Outcome
      return Strike::Outcome::Missed unless rolls? rng, hit
      return Strike::Outcome::Dodged if rolls? rng, dodge
      return Strike::Outcome::Hit if reach.bolt?
      return Strike::Outcome::Hit unless rolls? rng, guard

      reach.melee? ? Strike::Outcome::Parried : Strike::Outcome::Deflected
    end

    # The defender's parry effects that fire, each rolled in turn.
    private def self.riposte(rng : Rng, defense : Defense, attacker_dr : Fixed,
                             adjacent : Bool) : Array(Riposte)
      fired = [] of Riposte
      defense.parry_effects.each do |effect|
        next unless rolls? rng, effect.chance

        damage = Fixed::ZERO
        if adjacent && (span = effect.damage)
          damage = soak rng, span.roll(rng), attacker_dr, Chance::NEVER
        end
        fired << Riposte.new effect, damage
      end

      fired
    end
  end
end
