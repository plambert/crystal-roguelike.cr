require "../spec_helper"

Spectator.describe "ammunition beside a scattered ranged weapon" do
  alias Game = Roguelike::Game
  alias Kind = Roguelike::ItemKind
  alias Rng = Roguelike::Rng

  # How many floors the distribution examples generate.
  RUNS = 200

  # The first seed they generate from. A failure names a run somebody can
  # start.
  FIRST = 1_u64

  # One ranged weapon and where it lies.
  record Found, spot : {Int32, Int32}, kind : Kind

  # Everything lying on *game*'s floor, with the square it lies on.
  def lying(game : Game) : Array(Found)
    found = [] of Found

    game.floor.each_pile do |column, row, pile|
      pile.each { |item| found << Found.new({column, row}, item.kind) }
    end

    found
  end

  # How far apart two squares are, squared.
  def squared(here : {Int32, Int32}, there : {Int32, Int32}) : Int32
    across = there[0] - here[0]
    down = there[1] - here[1]

    across * across + down * down
  end

  # The furthest a square within `Game::NEARBY` can be, squared.
  def within : Int32
    2 * Game::NEARBY * Game::NEARBY
  end

  # Whether *weapon* has ammunition it fires within `Game::NEARBY`.
  def supplied?(found : Array(Found), weapon : Found) : Bool
    wanted = weapon.kind.ammunition

    found.any? do |lying|
      lying.kind == wanted && squared(weapon.spot, lying.spot) <= within
    end
  end

  # Every ranged weapon on every floor from `RUNS` seeds, and what was near it.
  def scattered : {Int32, Int32}
    weapons = 0
    supplied = 0

    RUNS.times do |index|
      found = lying Game.start(Rng.new FIRST + index)

      found.select(&.kind.item_class.ranged_weapon?).each do |weapon|
        weapons += 1
        supplied += 1 if supplied? found, weapon
      end
    end

    {weapons, supplied}
  end

  describe "ItemKind#ammunition" do
    it "names what a ranged weapon fires" do
      expect(Kind::Bow.ammunition).to eq Kind::Arrow
      expect(Kind::Sling.ammunition).to eq Kind::Stone
    end

    it "names nothing for anything that is not a ranged weapon" do
      Kind.values.reject(&.item_class.ranged_weapon?).each do |kind|
        expect(kind.ammunition).to be_nil
      end
    end

    it "is the other way round from ItemKind#ranged_weapon" do
      Kind.values.select(&.item_class.ranged_weapon?).each do |ranged_weapon|
        fired = ranged_weapon.ammunition
        expect(fired.try &.ranged_weapon).to eq ranged_weapon
      end
    end
  end

  describe "Game#scatter" do
    # How far from the stated chance a share of two hundred may land.
    #
    # Six points. The standard error of a share of a couple of hundred draws
    # is about two and a half, so this is somewhat over two of them.
    TOLERANCE = 6.0

    it "puts ammunition near most ranged weapons it scatters" do
      weapons, supplied = scattered

      expect(weapons).to be > 0
      expect(supplied * 100.0 / weapons).to be_close Game::QUIVERED, TOLERANCE
    end

    it "puts the right ammunition near each one" do
      RUNS.times do |index|
        found = lying Game.start(Rng.new FIRST + index)

        found.select(&.kind.item_class.ammunition?).each do |shot|
          expect(shot.kind.ranged_weapon).not_to be_nil
        end
      end
    end

    it "never puts it in rock" do
      RUNS.times do |index|
        game = Game.start Rng.new(FIRST + index)

        game.floor.each_pile do |column, row, _pile|
          expect(game.floor.terrain(column, row).floor?).to be_true
        end
      end
    end

    it "puts down a few pieces rather than one" do
      RUNS.times do |index|
        game = Game.start Rng.new(FIRST + index)

        game.floor.each_pile do |_column, _row, pile|
          pile.each do |item|
            next unless item.kind.item_class.ammunition?

            expect(item.count).to be >= Roguelike::Items::STACKS[item.kind].begin
          end
        end
      end
    end

    it "scatters the same ammunition from the same seed" do
      first = Game.start Rng.new(FIRST)
      again = Game.start Rng.new(FIRST)

      expect(again.floor.litter).to eq first.floor.litter
    end

    # The supply rolls on a stream named by the square rather than on the
    # litter's own. Everything else falls where it always fell, and this
    # fixture is what says so: a change to either stream shows as a diff.
    it "scatters what it scattered last time" do
      game = Game.start Rng.new(FIRST)
      lines = [] of String

      lying(game).sort_by { |found| {found.spot[1], found.spot[0], found.kind.to_s} }
        .each do |found|
          lines << "%3d,%-3d %s" % [found.spot[0], found.spot[1], found.kind.label]
        end

      scattered = lines.join "\n"
      expect(scattered).to eq Fixture.expected("items/scattered.txt", scattered)
    end
  end
end
