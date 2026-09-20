require "../spec_helper"

Spectator.describe "the potion and the two scrolls that change a speed" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Blessing = Roguelike::Blessing
  alias Species = Roguelike::Species
  alias Monster = Roguelike::Monster
  alias Pace = Roguelike::Pace

  # A lit hall with the character at the west end and room to see down it.
  HALL = ["######################",
          "#....................#",
          "#..<.................#",
          "#....................#",
          "######################"]

  def bare : Roguelike::Game
    floor = Roguelike::Floor.parse "hall", HALL.join('\n')
    floor.ambient = 1

    Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"hall" => floor}),
      Roguelike::Player.new("hall", 3, 2)
  end

  # Puts *kind* in the pack and answers its letter.
  def carrying(game : Roguelike::Game, kind : Kind,
               blessing : Blessing = Blessing::Uncursed) : Char
    letter = game.player.inventory.add Item.new(kind, blessing: blessing)
    raise "no room" unless letter
    letter
  end

  # Puts a creature of *species* at *x*, *y* and answers it.
  def creature(game : Roguelike::Game, species : Species,
               x : Int32, y : Int32) : Monster
    found = Monster.new species, x, y, "band-#{x}-#{y}"
    game.floor.place found
    found
  end

  # Tells the band *creature* belongs to that it has seen the character.
  def rouse(game : Roguelike::Game, creature : Monster) : Nil
    band = game.floor.band creature.band
    raise "the floor has lost the band" unless band

    knowledge = band.knowledge game.floor.id
    game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
    knowledge.saw Roguelike::Knowledge::PLAYER, game.player.x, game.player.y, game.turn
    band.awareness = Roguelike::Awareness::Hunting
  end

  # Takes *actions* actions without the character going anywhere. They step
  # east and back again, so neither step is ever blocked.
  def mark_time(game : Roguelike::Game, actions : Int32) : Nil
    actions.times do |taken|
      game.step taken.even? ? Roguelike::Direction::East : Roguelike::Direction::West
    end
  end

  describe "a potion of haste" do
    it "speeds the character up" do
      game = bare

      game.quaff carrying(game, Kind::HastePotion)

      expect(game.player.pace.hurried?).to be_true
      expect(game.player.pace.speed).to eq Pace::NORMAL + Pace::HASTE
    end

    it "says so" do
      game = bare

      game.quaff carrying(game, Kind::HastePotion)

      expect(game.log.last?.to_s).to eq "You speed up."
    end

    # The dice are 3d6+12, so fifteen ticks at the least and thirty at the
    # most before the blessing is read.
    it "lasts between fifteen and thirty turns" do
      game = bare

      game.quaff carrying(game, Kind::HastePotion)

      expect(game.player.pace.hasted).to be >= 15 - 1
      expect(game.player.pace.hasted).to be <= 30
    end

    it "lasts longer blessed and less time cursed" do
      blessed = bare
      cursed = bare

      blessed.quaff carrying(blessed, Kind::HastePotion, Blessing::Blessed)
      cursed.quaff carrying(cursed, Kind::HastePotion, Blessing::Cursed)

      expect(blessed.player.pace.hasted).to be > cursed.player.pace.hasted * 2
    end

    # A second potion is more time, not more speed.
    it "runs on rather than stacking" do
      game = bare
      first = carrying game, Kind::HastePotion
      carrying game, Kind::HastePotion
      game.quaff first
      held = game.player.pace.hasted

      game.quaff first

      expect(game.player.pace.speed).to eq Pace::NORMAL + Pace::HASTE
      expect(game.player.pace.hasted).to be > held
      expect(game.log.last?.to_s).to eq "The hurry in you runs on."
    end

    # Fifteen actions of a hurried character are ten ticks of the world, so a
    # goblin keeping up with them gets ten.
    it "takes three actions for a goblin's two" do
      game = bare
      goblin = creature game, Species::Goblin, 18, 2
      rouse game, goblin
      game.quaff carrying(game, Kind::HastePotion)
      before = game.turn

      mark_time game, 15

      expect(game.turn - before).to eq 10
    end

    it "wears off and says so" do
      game = bare
      game.quaff carrying(game, Kind::HastePotion)
      held = game.player.pace.hasted

      mark_time game, 2 * held

      expect(game.player.pace.hurried?).to be_false
      expect(game.log.lines).to contain "You slow down again."
    end
  end

  describe "a scroll of slow monster" do
    it "asks for a square when nothing has touched it" do
      game = bare
      letter = carrying game, Kind::SlowScroll

      expect(game.target_needed? letter).to be_true
    end

    # Reading the scroll spends a turn, and a goblin that notices the
    # character walks a square in it, so the cursor goes where it ends up.
    it "holds back what it was aimed at" do
      game = bare
      goblin = creature game, Species::Goblin, 10, 2
      scroll = game.start_aiming_read carrying(game, Kind::SlowScroll)
      raise "the scroll was not read" unless scroll

      game.aim_reading scroll, goblin.at

      expect(goblin.pace.dragging?).to be_true
      expect(goblin.pace.speed).to eq Species::Goblin.speed - Pace::SLOW
      expect(game.log.last?.to_s).to eq "The goblin slows to a crawl."
    end

    it "settles on nothing when it is aimed at nothing" do
      game = bare
      scroll = game.start_aiming_read carrying(game, Kind::SlowScroll)
      raise "the scroll was not read" unless scroll

      game.aim_reading scroll, {10, 2}

      expect(game.log.last?.to_s).to eq "The words settle on nothing."
    end

    it "holds back everything in sight when it is blessed" do
      game = bare
      near = creature game, Species::Goblin, 8, 2
      far = creature game, Species::Orc, 14, 3

      game.read carrying(game, Kind::SlowScroll, Blessing::Blessed)

      expect(near.pace.dragging?).to be_true
      expect(far.pace.dragging?).to be_true
    end

    it "holds the reader back when it is cursed" do
      game = bare

      game.read carrying(game, Kind::SlowScroll, Blessing::Cursed)

      expect(game.player.pace.dragging?).to be_true
      expect(game.player.pace.speed).to eq Pace::NORMAL - Pace::SLOW
      expect(game.log.last?.to_s).to eq "Your own feet drag."
    end

    it "tells the character when their feet come free" do
      game = bare
      game.read carrying(game, Kind::SlowScroll, Blessing::Cursed)
      held = game.player.pace.slowed

      mark_time game, held + 2

      expect(game.player.pace.dragging?).to be_false
      expect(game.log.lines).to contain "Your feet come free."
    end
  end

  describe "a scroll of haste monster" do
    it "hurries what it was aimed at" do
      game = bare
      goblin = creature game, Species::Goblin, 10, 2
      scroll = game.start_aiming_read carrying(game, Kind::HasteScroll)
      raise "the scroll was not read" unless scroll

      game.aim_reading scroll, goblin.at

      expect(goblin.pace.hurried?).to be_true
      expect(goblin.pace.speed).to eq Species::Goblin.speed + Pace::HASTE
      expect(game.log.last?.to_s).to eq "The goblin speeds up."
    end

    # A god turns the words on the reader instead.
    it "hurries the reader when it is blessed" do
      game = bare
      goblin = creature game, Species::Goblin, 10, 2

      game.read carrying(game, Kind::HasteScroll, Blessing::Blessed)

      expect(game.player.pace.hurried?).to be_true
      expect(goblin.pace.hurried?).to be_false
    end

    it "asks for no square when it is blessed" do
      game = bare
      letter = carrying game, Kind::HasteScroll, Blessing::Blessed

      expect(game.target_needed? letter).to be_false
    end

    it "hurries everything in sight when it is cursed" do
      game = bare
      near = creature game, Species::Goblin, 8, 2
      far = creature game, Species::Orc, 14, 3

      game.read carrying(game, Kind::HasteScroll, Blessing::Cursed)

      expect(near.pace.hurried?).to be_true
      expect(far.pace.hurried?).to be_true
      expect(game.player.pace.hurried?).to be_false
    end
  end

  describe "what a creature at another speed does" do
    # Counted from the energy: ten ticks at half again the speed is fifteen
    # actions, however many of them the creature turned into ground.
    it "takes three actions for the character's two while it is hurried" do
      game = bare
      goblin = creature game, Species::Goblin, 18, 2
      rouse game, goblin
      goblin.pace.hurry 1000
      before = goblin.pace.energy

      mark_time game, 10

      earned = before + 10 * goblin.pace.speed
      expect((earned - goblin.pace.energy) // Pace::TICK).to be_within(1).of(15)
    end
  end
end
