require "../spec_helper"
require "../support/drawn_rng"

Spectator.describe "Combat.resolve" do
  alias Chance = Roguelike::Chance
  alias Combat = Roguelike::Combat
  alias Defense = Roguelike::Defense
  alias Fixed = Roguelike::Fixed
  alias Offense = Roguelike::Offense
  alias Outcome = Roguelike::Strike::Outcome
  alias ParryEffect = Roguelike::ParryEffect
  alias Ratio = Roguelike::Ratio
  alias Reach = Roguelike::Reach
  alias Span = Roguelike::Span
  alias Spread = Roguelike::Spread

  # The largest draw a span or a soak takes.
  TOP = Span::STEPS

  # A draw that fails every chance below certainty.
  FAIL = 9_999

  # Accuracy and AC are equal, so the hit chance is 50.0%. Dodge, parry and
  # deflect are 10.0% each, lucky is 1.0% and crit 5.0%.
  let(offense) do
    Offense.new accuracy: Fixed.new(1_000),
      damage: Span.new(Fixed.new(200), Fixed.new(600), Spread::Even),
      crit: Chance.new(500), crit_multiplier: Ratio.new(15_000),
      lucky: Chance.new(100)
  end

  let(defense) do
    Defense.new ac: Fixed.new(1_000), dodge: Chance.new(1_000),
      parry: Chance.new(1_000), deflect: Chance.new(1_000)
  end

  # Resolves an attack on the draws given, and checks every draw was taken.
  def resolved(draws : Array(Int32), offense : Offense = offense,
               defense : Defense = defense, **options) : Roguelike::Strike
    rng = DrawnRng.new draws
    strike = Combat.resolve rng, offense, defense, **options
    expect(rng.left).to eq 0

    strike
  end

  describe "to hit" do
    it "misses on a draw at or above the hit chance" do
      strike = resolved [5_000, FAIL]

      expect(strike.outcome).to eq Outcome::Missed
      expect(strike.landed?).to be_false
      expect(strike.damage).to eq Fixed::ZERO
      expect(strike.hit_chance.value).to eq 5_000
    end

    it "goes on to dodge on a draw below it" do
      expect(resolved([4_999, 999, FAIL]).outcome).to eq Outcome::Dodged
    end
  end

  describe "dodge" do
    it "dodges on a draw below the dodge chance" do
      strike = resolved [0, 999, FAIL]

      expect(strike.outcome).to eq Outcome::Dodged
      expect(strike.dodge_chance.value).to eq 1_000
    end

    it "applies to every reach" do
      Reach.values.each do |reach|
        strike = resolved [0, 0, FAIL], offense.copy_with(reach: reach)

        expect(strike.outcome).to eq Outcome::Dodged
      end
    end
  end

  describe "parry" do
    it "parries a blow on a draw below the parry chance" do
      strike = resolved [0, 1_000, 999, FAIL]

      expect(strike.outcome).to eq Outcome::Parried
      expect(strike.guard_chance.value).to eq 1_000
    end

    it "does not apply to a missile" do
      parrying = defense.copy_with parry: Chance::ALWAYS, deflect: Chance::NEVER
      strike = resolved [0, 1_000, 0, FAIL, 0, 0], offense.copy_with(reach: Reach::Missile), parrying

      expect(strike.outcome).to eq Outcome::Hit
      expect(strike.guard_chance).to eq Chance::NEVER
    end
  end

  describe "deflect" do
    it "deflects a missile on a draw below the deflect chance" do
      strike = resolved [0, 1_000, 999, FAIL], offense.copy_with(reach: Reach::Missile)

      expect(strike.outcome).to eq Outcome::Deflected
    end

    it "does not apply to a blow" do
      deflecting = defense.copy_with parry: Chance::NEVER, deflect: Chance::ALWAYS
      strike = resolved [0, 1_000, 0, FAIL, 0, 0], offense, deflecting

      expect(strike.outcome).to eq Outcome::Hit
    end
  end

  describe "a bolt" do
    it "skips parry and deflect and takes no draw for them" do
      guarded = defense.copy_with parry: Chance::ALWAYS, deflect: Chance::ALWAYS
      strike = resolved [0, 1_000, FAIL, 0, 0], offense.copy_with(reach: Reach::Bolt), guarded

      expect(strike.outcome).to eq Outcome::Hit
      expect(strike.guard_chance).to eq Chance::NEVER
    end
  end

  describe "lucky" do
    it "turns a miss into a hit on a draw below the lucky chance" do
      strike = resolved [5_000, 99, FAIL, 0, 0]

      expect(strike.outcome).to eq Outcome::Missed
      expect(strike.lucky?).to be_true
      expect(strike.landed?).to be_true
      expect(strike.raw.value).to eq 200
    end

    it "lets a failure stand on a draw at or above it" do
      strike = resolved [5_000, 100]

      expect(strike.lucky?).to be_false
      expect(strike.landed?).to be_false
    end

    it "rolls once after any failure" do
      expect(resolved([0, 0, 99, FAIL, 0, 0]).lucky?).to be_true
      expect(resolved([0, 1_000, 0, 99, FAIL, 0, 0]).lucky?).to be_true
    end

    it "is not rolled after a hit" do
      expect(resolved([0, 1_000, 1_000, FAIL, 0, 0]).lucky?).to be_false
    end

    it "lets a lucky hit crit" do
      strike = resolved [5_000, 0, 0, TOP, 0]

      expect(strike.crit?).to be_true
      expect(strike.raw.value).to eq 900
    end

    it "is moved by the defender's shift" do
      shifted = resolved [5_000, 299, FAIL, 0, 0], offense, defense.copy_with(lucky_shift: 200)

      expect(shifted.lucky_chance.value).to eq 300
      expect(shifted.lucky?).to be_true
    end

    it "is never below zero" do
      shifted = resolved [5_000, 0], offense, defense.copy_with(lucky_shift: -300)

      expect(shifted.lucky_chance).to eq Chance::NEVER
      expect(shifted.lucky?).to be_false
    end

    it "is never above certainty" do
      shifted = resolved [5_000, FAIL, FAIL, 0, 0], offense, defense.copy_with(lucky_shift: 20_000)

      expect(shifted.lucky_chance).to eq Chance::ALWAYS
    end
  end

  describe "crit" do
    it "multiplies the rolled damage on a draw below the crit chance" do
      strike = resolved [0, 1_000, 1_000, 499, TOP, 0]

      expect(strike.crit?).to be_true
      expect(strike.raw.value).to eq 900
      expect(strike.crit_chance.value).to eq 500
    end

    it "leaves the damage alone on a draw at or above it" do
      strike = resolved [0, 1_000, 1_000, 500, TOP, 0]

      expect(strike.crit?).to be_false
      expect(strike.raw.value).to eq 600
    end

    it "applies before DR" do
      armored = defense.copy_with dr: Fixed.new(200)
      strike = resolved [0, 1_000, 1_000, 0, TOP, 0], offense, armored

      expect(strike.raw.value).to eq 900
      expect(strike.damage.value).to eq 800
    end

    it "treats a negative multiplier as zero" do
      broken = offense.copy_with crit_multiplier: Ratio.new(-5_000)

      expect(resolved([0, 1_000, 1_000, 0, TOP, 0], broken).raw).to eq Fixed::ZERO
    end
  end

  describe "damage" do
    it "rolls the span on its spread" do
      centered = offense.copy_with damage: Span.new(Fixed.new(200), Fixed.new(600), Spread::Centered)
      strike = resolved [0, 1_000, 1_000, FAIL, TOP, 0, 0], centered

      expect(strike.raw.value).to eq 400
    end

    it "takes the whole roll with no DR" do
      strike = resolved [0, 1_000, 1_000, FAIL, TOP, TOP]

      expect(strike.damage.value).to eq 600
    end
  end

  describe "DR" do
    let(armored) { defense.copy_with dr: Fixed.new(200) }

    it "soaks half of DR on the least draw" do
      expect(resolved([0, 1_000, 1_000, FAIL, TOP, 0], offense, armored).damage.value).to eq 500
    end

    it "soaks one and a half times DR on the largest draw" do
      expect(resolved([0, 1_000, 1_000, FAIL, TOP, TOP], offense, armored).damage.value).to eq 300
    end

    it "lets a fifth of the blow through however much it soaks" do
      plated = defense.copy_with dr: Fixed.new(2_000)

      expect(resolved([0, 1_000, 1_000, FAIL, TOP, 0], offense, plated).damage.value).to eq 120
    end

    it "is lowered by penetration" do
      piercing = offense.copy_with penetration: Chance.new(5_000)

      expect(resolved([0, 1_000, 1_000, FAIL, TOP, 0], piercing, armored).damage.value).to eq 550
    end

    it "is gone at full penetration" do
      piercing = offense.copy_with penetration: Chance::ALWAYS

      expect(resolved([0, 1_000, 1_000, FAIL, TOP, TOP], piercing, armored).damage.value).to eq 600
    end
  end

  describe "parry effects" do
    let(stun) { ParryEffect.new Chance::ALWAYS, stun: 50 }
    let(spikes) do
      ParryEffect.new Chance.new(5_000), damage: Span.new(Fixed.new(100), Fixed.new(300), Spread::Even)
    end
    let(parrying) { defense.copy_with parry_effects: [stun, spikes] }

    # To hit, no dodge, a parry, no lucky hit.
    let(parried) { [0, 1_000, 0, FAIL] }

    it "rolls each effect once the parry stands" do
      strike = resolved parried + [FAIL, 4_999, TOP, 0], offense, parrying

      expect(strike.ripostes.map(&.effect)).to eq [stun, spikes]
      expect(strike.stun).to eq 50
      expect(strike.recoil.value).to eq 300
    end

    it "skips an effect on a draw at or above its chance" do
      strike = resolved parried + [0, 5_000], offense, parrying

      expect(strike.ripostes.map(&.effect)).to eq [stun]
      expect(strike.recoil).to eq Fixed::ZERO
    end

    it "takes riposte damage through the attacker's DR" do
      strike = resolved parried + [0, 0, TOP, 0], offense, parrying, attacker_dr: Fixed.new(100)

      expect(strike.recoil.value).to eq 250
    end

    it "does no damage to an attacker that is not adjacent, and still stuns it" do
      strike = resolved parried + [0, 0], offense, parrying, adjacent: false

      expect(strike.ripostes.size).to eq 2
      expect(strike.stun).to eq 50
      expect(strike.recoil).to eq Fixed::ZERO
    end

    it "is cancelled by a lucky hit" do
      strike = resolved [0, 1_000, 0, 0, FAIL, 0, 0], offense, parrying

      expect(strike.lucky?).to be_true
      expect(strike.ripostes).to be_empty
    end

    it "is not rolled after a dodge" do
      expect(resolved([0, 0, FAIL], offense, parrying).ripostes).to be_empty
    end

    it "is not rolled after a deflect" do
      missile = offense.copy_with reach: Reach::Missile

      expect(resolved([0, 1_000, 0, FAIL], missile, parrying).ripostes).to be_empty
    end
  end

  describe "the largest inputs" do
    let(huge) { Fixed.new Int32::MAX }

    it "resolves without overflow" do
      offense = Offense.new accuracy: huge, damage: Span.new(huge, huge),
        crit: Chance::ALWAYS, crit_multiplier: Ratio::ONE,
        penetration: Chance.new(1), lucky: Chance::ALWAYS
      defense = Defense.new ac: huge, dr: huge,
        lucky_shift: Int32::MAX

      strike = resolved [0, 0, 0, 0, TOP, TOP, TOP], offense, defense

      expect(strike.raw).to eq huge
      expect(strike.damage.value).to eq Int32::MAX // 5
    end

    it "raises rather than wrapping when a crit leaves the range of a quantity" do
      offense = Offense.new accuracy: huge, damage: Span.new(huge, huge),
        crit: Chance::ALWAYS, crit_multiplier: Ratio.new(Int32::MAX)

      expect { Combat.resolve DrawnRng.new([0, 0, 0, 0, 0, 0]), offense, Roguelike::Defense.new }
        .to raise_error OverflowError
    end
  end
end

Spectator.describe "Combat.hit_chance" do
  alias Combat = Roguelike::Combat
  alias Fixed = Roguelike::Fixed

  it "is accuracy over accuracy plus AC" do
    expect(Combat.hit_chance(Fixed.new(1_378), Fixed.new(900)).value).to eq 6_049
  end

  it "gives an unarmored first level character 62.5% against 10.0" do
    expect(Combat.hit_chance(Fixed.new(1_000), Fixed.new(600)).value).to eq 6_250
  end

  it "holds accuracy to 1.0 and AC to 0.1" do
    expect(Combat.hit_chance(Fixed::ZERO, Fixed::ZERO).value).to eq 9_091
    expect(Combat.hit_chance(Fixed.new(-500), Fixed.new(-500)).value).to eq 9_091
  end

  it "never reaches certainty" do
    expect(Combat.hit_chance(Fixed.new(Int32::MAX), Fixed::ZERO).value).to eq 9_999
  end

  it "never reaches zero" do
    expect(Combat.hit_chance(Fixed::ZERO, Fixed.new(Int32::MAX)).value).to eq 1
  end
end

Spectator.describe "Combat.accuracy" do
  alias Combat = Roguelike::Combat
  alias Fixed = Roguelike::Fixed
  alias Ratio = Roguelike::Ratio

  it "multiplies the flat sum by the increase once" do
    expect(Combat.accuracy(Fixed.new(1_300), Ratio.new(600)).value).to eq 1_378
  end

  it "takes a negative increase" do
    expect(Combat.accuracy(Fixed.new(1_000), Ratio.new(-2_100)).value).to eq 790
  end

  it "is zero below a decrease of all of it" do
    expect(Combat.accuracy(Fixed.new(1_000), Ratio.new(-12_000))).to eq Fixed::ZERO
  end

  it "is zero for a negative flat sum" do
    expect(Combat.accuracy(Fixed.new(-100), Ratio.new(600))).to eq Fixed::ZERO
  end
end

# Four hundred attacks with their inputs and every result, written out.
#
# The inputs come from one stream and the attacks from another, both through
# `Rng#below`, so the file is the same on every platform CI builds for. A
# change to the roll order or to any formula shows as a diff. Values are the
# raw stored integers.
Spectator.describe "the combat vectors" do
  alias Chance = Roguelike::Chance
  alias Combat = Roguelike::Combat
  alias Defense = Roguelike::Defense
  alias Fixed = Roguelike::Fixed
  alias Offense = Roguelike::Offense
  alias ParryEffect = Roguelike::ParryEffect
  alias Ratio = Roguelike::Ratio
  alias Reach = Roguelike::Reach
  alias Rng = Roguelike::Rng
  alias Span = Roguelike::Span
  alias Spread = Roguelike::Spread

  # The seed the fixture was written from.
  SEED = 20261124_u64

  # How many attacks it holds.
  COUNT = 400

  # A chance of up to *most* basis points, present one time in *odds*.
  def sometimes(rng : Rng, odds : Int32, most : Int32) : Chance
    rng.below(odds).zero? ? Chance.new(rng.below(most + 1)) : Chance::NEVER
  end

  def span(rng : Rng) : Span
    low = rng.below 500
    Span.new Fixed.new(low), Fixed.new(low + rng.below(1_000)), Spread.values[rng.below(Spread.values.size)]
  end

  def effects(rng : Rng) : Array(ParryEffect)
    Array.new(rng.below(3)) do
      chance = Chance.new rng.below(10_001)
      stun = rng.below(2) * 100
      damage = rng.below(2).zero? ? span(rng) : nil
      ParryEffect.new chance, stun, damage
    end
  end

  def line(index : Int32) : String
    inputs = Rng.new(SEED).derive "vectors", index
    offense = Offense.new accuracy: Fixed.new(300 + inputs.below(2_500)),
      damage: span(inputs),
      crit: Chance.new(inputs.below(2_001)),
      crit_multiplier: Ratio.new(15_000 + inputs.below(10_001)),
      lucky: Chance.new(100 + inputs.below(401)),
      penetration: sometimes(inputs, 3, 5_000),
      reach: Reach.values[inputs.below(Reach.values.size)]
    defense = Defense.new ac: Fixed.new(inputs.below(1_500)),
      dr: inputs.below(4).zero? ? Fixed.new(inputs.below(800)) : Fixed::ZERO,
      dodge: sometimes(inputs, 2, 3_000),
      parry: sometimes(inputs, 2, 8_000),
      parry_effects: effects(inputs),
      deflect: sometimes(inputs, 2, 4_000),
      lucky_shift: inputs.below(601) - 300
    attacker_dr = Fixed.new inputs.below(300)
    adjacent = inputs.below(4) != 0

    rng = Rng.new(SEED).derive "combat", index
    strike = Combat.resolve rng, offense, defense, attacker_dr: attacker_dr, adjacent: adjacent

    String.build do |io|
      io << "%3d " % index << written(offense) << ' ' << written(defense)
      io << " adr " << attacker_dr.value << (adjacent ? " adj" : " far") << "\n    => "
      io << strike.outcome.to_s.downcase
      io << " lucky" if strike.lucky?
      io << " crit" if strike.crit?
      io << " hit " << strike.hit_chance.value << " lk " << strike.lucky_chance.value
      io << " raw " << strike.raw.value << " dmg " << strike.damage.value
      strike.ripostes.each do |riposte|
        io << " [stun " << riposte.effect.stun << " dmg " << riposte.damage.value << ']'
      end
      io << " next " << rng.next_u
    end
  end

  def written(offense : Offense) : String
    "A %d %s cr %d x%d lk %d pen %d %s" % [
      offense.accuracy.value, written(offense.damage), offense.crit.value,
      offense.crit_multiplier.value, offense.lucky.value, offense.penetration.value,
      offense.reach.to_s.downcase,
    ]
  end

  def written(defense : Defense) : String
    effects = defense.parry_effects.map do |effect|
      "%d/%d/%s" % [effect.chance.value, effect.stun, effect.damage.try { |span| written span } || "-"]
    end
    "| AC %d DR %d dg %d pa %d df %d sh %d fx [%s]" % [
      defense.ac.value, defense.dr.value, defense.dodge.value, defense.parry.value,
      defense.deflect.value, defense.lucky_shift, effects.join(' '),
    ]
  end

  def written(span : Span) : String
    "%d-%d%c" % [span.low.value, span.high.value, span.spread.to_s[0].downcase]
  end

  it "resolves what it resolved last time" do
    drawn = Array.new(COUNT) { |index| line index }.join "\n"

    expect(drawn).to eq Fixture.expected("combat/vectors.txt", drawn)
  end

  it "covers every outcome, lucky hits, crits and ripostes" do
    drawn = Array.new(COUNT) { |index| line index }.join "\n"

    ["=> hit", "=> missed", "=> dodged", "=> parried", "=> deflected", " lucky", " crit", "[stun"].each do |mark|
      expect(drawn).to contain mark
    end
  end
end
