require "../spec_helper"

Spectator.describe "a fountain" do
  alias Generator = Roguelike::Generator
  alias Rng = Roguelike::Rng
  alias Terrain = Roguelike::Terrain
  alias World = Roguelike::World
  alias Library = Roguelike::Ui::ThemeLibrary
  alias Palette = Roguelike::Ui::Palette

  # How many seeds the share of watered floors is measured over.
  SEEDS = 2000

  describe "the terrain" do
    it "is walked through and seen through" do
      expect(Terrain::Fountain.passable?).to be_true
      expect(Terrain::Fountain.blocks_sight?).to be_false
    end

    it "is written in a floor file as {" do
      expect(Terrain::Fountain.mark).to eq '{'
      expect(Terrain.from_mark '{').to eq Terrain::Fountain
    end

    it "is not bare floor, so nothing else is put down on it" do
      expect(Terrain::Fountain.floor?).to be_false
    end

    it "reads at 4.5 to 1 on the ground in every built-in theme" do
      Library::BUILT_INS.each do |named|
        theme = named.theme
        ratio = Palette.contrast theme["fountain"], theme["ground"]
        expect(ratio).to be >= 4.5, "#{named.name}: the fountain is #{ratio.round 2} to 1"
      end
    end
  end

  describe "where the generator puts one" do
    it "is never on floor 1 or in the chamber under the last floor" do
      (1_u64..200_u64).each do |seed|
        rng = Rng.new seed
        expect(Generator.fountain?(rng, World.id(1))).to be_false
        expect(Generator.fountain?(rng, World.id(World::VAULT))).to be_false
      end
    end

    it "is decided by the seed alone" do
      (1_u64..50_u64).each do |seed|
        first = Generator::WATERED.map { |depth| Generator.fountain? Rng.new(seed), World.id(depth) }
        again = Generator::WATERED.map { |depth| Generator.fountain? Rng.new(seed), World.id(depth) }
        expect(again).to eq first
      end
    end

    it "is on about 60 floors in a hundred" do
      watered = 0
      total = 0
      (1_u64..SEEDS.to_u64).each do |seed|
        rng = Rng.new seed
        Generator::WATERED.each do |depth|
          total += 1
          watered += 1 if Generator.fountain? rng, World.id(depth)
        end
      end

      share = watered * 100.0 / total
      expect(share).to be_within(3.0).of(Generator::FOUNTAIN)
    end

    it "leaves two floors in a row dry in most runs" do
      dry = (1_u64..SEEDS.to_u64).count do |seed|
        rng = Rng.new seed
        flags = Generator::WATERED.map { |depth| Generator.fountain? rng, World.id(depth) }
        flags.each_cons_pair.any? { |one, two| !one && !two }
      end

      expect(dry * 100.0 / SEEDS).to be >= 50.0
    end

    it "puts one fountain in a room of each floor that has one, and none elsewhere" do
      (1_u64..60_u64).each do |seed|
        depth = 2 + (seed % 9).to_i
        id = World.id depth
        rng = Rng.new seed
        dug = Generator.dug rng, id, depth
        found = [] of {Int32, Int32}
        dug.floor.each { |column, row, tile| found << {column, row} if tile.terrain.fountain? }

        unless Generator.fountain? rng, id
          expect(found).to be_empty, "seed #{seed} floor #{depth}"
          next
        end

        expect(found.size).to eq(1), "seed #{seed} floor #{depth}"
        expect(dug.zones.any? &.holds?(*found.first)).to be_true
      end
    end

    it "is not in the chamber under the last floor" do
      chamber = Generator.chamber
      expect(chamber.find Terrain::Fountain).to be_nil
    end
  end

  describe "drawing water" do
    alias Action = Roguelike::Action
    alias Event = Roguelike::Event
    alias Halt = Roguelike::Halt
    alias Sustenance = Roguelike::Sustenance

    # A lit hall with a fountain at its east end. The character starts on
    # the up staircase at its west end.
    WELL = ["#############",
            "#...........#",
            "#.<......{..#",
            "#...........#",
            "#############"]

    # Where the fountain is.
    BASIN = {9, 2}

    # A game in the hall, the character on the fountain when *on* is true.
    def hall(on : Bool = false) : Roguelike::Game
      floor = Playing.daylight Roguelike::Floor.parse("well", WELL.join('\n'))
      at = on ? BASIN : {2, 2}
      Roguelike::Game.new(
        Roguelike::World.new(Playing::SEED, {"well" => floor}),
        Playing.dressed(Roguelike::Player.new("well", at[0], at[1])))
    end

    # Ticks *sustenance* until the skin holds *units*.
    def drain(sustenance : Sustenance, units : Int32 = 0) : Nil
      held = sustenance.water
      while held > units
        sustenance.tick
        held = sustenance.water
      end
    end

    # Ticks *sustenance* until thirst has climbed *turns* past a dry skin.
    def parch(sustenance : Sustenance, turns : Int32) : Nil
      drain sustenance
      turns.times { sustenance.tick }
    end

    it "puts one unit in the skin and takes a turn" do
      game = hall on: true
      drain game.player.sustenance, 4
      turn = game.turn

      verdict = game.perform Action::Refill.new

      expect(verdict.refused?).to be_false
      expect(game.player.sustenance.water).to eq 5
      expect(game.turn).to eq turn + 1
      refilled = game.events.compact_map(&.as?(Event::Refilled))
      expect(refilled.map &.units).to eq [1]
    end

    it "is refused off a fountain, and no turn passes" do
      game = hall
      drain game.player.sustenance, 4
      turn = game.turn

      game.perform Action::Refill.new

      expect(game.player.sustenance.water).to eq 4
      expect(game.turn).to eq turn
      expect(game.log.last?).to eq "There is no fountain here."
    end

    it "fills the skin a turn a unit, and stops when it is full" do
      game = hall on: true
      drain game.player.sustenance, 3
      turn = game.turn

      fill = game.fill

      expect(fill.halt).to eq Halt::Filled
      expect(fill.turns).to eq Sustenance::WATER_MAX - 3
      expect(game.turn).to eq turn + Sustenance::WATER_MAX - 3
      expect(game.player.sustenance.water).to eq Sustenance::WATER_MAX
      expect(game.log.last?).to eq "Your waterskin is full."
    end

    it "will not start a fill with a creature in sight" do
      game = hall on: true
      drain game.player.sustenance, 3
      game.floor.place Roguelike::Monster.new(Roguelike::Species::Goblin, 3, 1, "band-watching")

      expect(game.filling.halt).to eq Halt::InSight
    end

    it "is offered only on a fountain with room in the skin" do
      game = hall on: true
      expect(game.legal.any?(Action::Refill)).to be_false

      drain game.player.sustenance, 9
      expect(game.legal.any?(Action::Refill)).to be_true

      elsewhere = hall
      drain elsewhere.player.sustenance, 9
      expect(elsewhere.legal.any?(Action::Refill)).to be_false
    end

    it "quenches a thirsty character for free" do
      game = hall on: true
      parch game.player.sustenance, 600
      turn = game.turn

      game.perform Action::Quench.new

      expect(game.player.sustenance.quenched?).to be_true
      expect(game.turn).to eq turn
      drank = game.events.compact_map(&.as?(Event::Drank))
      expect(drank.map &.source).to eq ["fountain"]
    end

    it "is refused to a character who is not thirsty" do
      game = hall on: true

      game.perform Action::Quench.new

      expect(game.log.last?).to eq "You are not thirsty."
      expect(game.legal.any?(Action::Quench)).to be_false
    end

    it "quenches a character who drinks a potion" do
      game = hall
      parch game.player.sustenance, 600
      letter = game.player.inventory.add(Roguelike::Item.new(Roguelike::ItemKind::MinorHealingPotion))
      raise "pack full" unless letter

      game.quaff letter

      # The skin is still dry, so thirst climbs again on the turn the
      # potion took.
      expect(game.player.sustenance.thirst).to be <= 1

      drank = game.events.compact_map(&.as?(Event::Drank))
      expect(drank.map { |event| {event.units, event.source} }).to eq [{1, "potion"}]
    end

    it "writes no drank event for a potion drunk by a character who is not thirsty" do
      game = hall
      letter = game.player.inventory.add(Roguelike::Item.new(Roguelike::ItemKind::MinorHealingPotion))
      raise "pack full" unless letter

      game.quaff letter

      expect(game.events.any?(Event::Drank)).to be_false
    end

    it "sends an explore to a known fountain once the skin is dry, and fills it there" do
      game = hall
      drain game.player.sustenance

      game.explore

      expect(game.player.at).to eq BASIN
      expect(game.player.sustenance.water).to eq Sustenance::WATER_MAX
      expect(game.player.sustenance.thirst_stage).to eq Roguelike::ThirstStage::Quenched
    end

    it "lists filling and drinking among the available commands only on a fountain" do
      commands = Roguelike::Ui::Commands
      wanted = [Roguelike::Ui::Command::FillSkin, Roguelike::Ui::Command::DrinkFountain]

      game = hall on: true
      parch game.player.sustenance, 600
      expect(commands.available(game).map(&.id) & wanted).to eq wanted

      elsewhere = hall
      parch elsewhere.player.sustenance, 600
      expect(commands.available(elsewhere).map(&.id) & wanted).to be_empty
    end

    it "leaves a known fountain alone while the skin holds water" do
      game = hall
      drain game.player.sustenance, 5

      game.explore

      expect(game.player.sustenance.water).to eq 5
      expect(game.player.at).not_to eq BASIN
    end
  end
end
