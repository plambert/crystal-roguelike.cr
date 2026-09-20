require "../spec_helper"

Spectator.describe "the scrolls that detect, darken, blind and move" do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Blessing = Roguelike::Blessing
  alias Species = Roguelike::Species
  alias Monster = Roguelike::Monster

  # A lit hall, twenty across and eleven down, with the character in the
  # middle of the left end. Wide enough for the detection oval to leave
  # something out.
  HALL = ["######################",
          "#....................#",
          "#....................#",
          "#....................#",
          "#....................#",
          "#..<.................#",
          "#....................#",
          "#....................#",
          "#....................#",
          "#....................#",
          "######################"]

  def bare(seed : UInt64 = Playing::SEED) : Roguelike::Game
    floor = Roguelike::Floor.parse "hall", HALL.join('\n')
    floor.ambient = 1

    Roguelike::Game.new Roguelike::World.new(seed, {"hall" => floor}),
      Roguelike::Player.new("hall", 3, 5)
  end

  def reading(game : Roguelike::Game, kind : Kind,
              blessing : Blessing = Blessing::Uncursed) : Char
    letter = game.player.inventory.add Item.new(kind, blessing: blessing)
    raise "no room" unless letter
    letter
  end

  describe "a scroll of treasure detection" do
    it "writes down where the gold is" do
      game = bare
      game.floor.drop 18, 8, Item.new(Kind::Gold, count: 40)
      expect(game.knowledge.seen? 18, 8).to be_false

      game.read reading(game, Kind::TreasureScroll)

      expect(game.knowledge[18, 8].try &.item.try &.kind).to eq Kind::Gold
    end

    it "leaves the gold where it lies" do
      game = bare
      game.floor.drop 18, 8, Item.new(Kind::Gold, count: 40)

      game.read reading(game, Kind::TreasureScroll)

      expect(game.player.gold).to eq 0
      expect(game.floor.items?(18, 8)).to be_true
    end

    it "says so when there is none" do
      game = bare

      game.read reading(game, Kind::TreasureScroll)

      expect(game.log.last?.to_s).to contain "worth anything"
    end

    it "brings it all in when it is blessed" do
      game = bare
      game.floor.drop 18, 8, Item.new(Kind::Gold, count: 40)
      game.floor.drop 6, 2, Item.new(Kind::Gold, count: 12)

      game.read reading(game, Kind::TreasureScroll, Blessing::Blessed)

      expect(game.player.gold).to eq 52
      expect(game.floor.items?(18, 8)).to be_false
      expect(game.floor.items?(6, 2)).to be_false
      expect(game.log.last?.to_s).to contain "2 piles of gold teleport"
      expect(game.log.last?.to_s).to contain "52 gp"
    end

    it "ruins some of it when it is cursed" do
      game = bare
      20.times { |index| game.floor.drop 1 + index, 8, Item.new(Kind::Gold, count: 40) }

      game.read reading(game, Kind::TreasureScroll, Blessing::Cursed)

      left = 0
      game.floor.each_pile { |_column, _row, pile| pile.each { |item| left += item.count } }

      expect(left).to be < 800
      expect(left).to be > 0
      expect(game.log.last?.to_s).to contain "crumble"
    end

    it "leaves a single coin where it ruined a pile" do
      game = bare
      20.times { |index| game.floor.drop 1 + index, 8, Item.new(Kind::Gold, count: 40) }

      game.read reading(game, Kind::TreasureScroll, Blessing::Cursed)

      counts = [] of Int32
      game.floor.each_pile { |_column, _row, pile| pile.each { |item| counts << item.count } }

      expect(counts).to contain 1
      expect(counts.all? { |found| found == 1 || found == 40 }).to be_true
    end
  end

  describe "a scroll of item detection" do
    it "writes down what is near" do
      game = bare
      game.floor.drop 4, 5, Item.new(Kind::LongSword)

      game.read reading(game, Kind::DetectionScroll)

      expect(game.knowledge[4, 5].try &.item.try &.kind).to eq Kind::LongSword
    end

    # The oval is a quarter of the floor across and a quarter down, so it
    # reaches an eighth of each way from the character.
    it "leaves what is far off alone" do
      game = bare
      game.floor.drop 20, 1, Item.new(Kind::LongSword)

      game.read reading(game, Kind::DetectionScroll)

      expect(game.knowledge.seen? 20, 1).to be_false
    end

    it "reaches the whole floor when it is blessed" do
      game = bare
      game.floor.drop 20, 1, Item.new(Kind::LongSword)

      game.read reading(game, Kind::DetectionScroll, Blessing::Blessed)

      expect(game.knowledge[20, 1].try &.item.try &.kind).to eq Kind::LongSword
    end

    it "says nothing about the gold" do
      game = bare
      game.floor.drop 4, 5, Item.new(Kind::Gold, count: 40)

      game.read reading(game, Kind::DetectionScroll, Blessing::Blessed)

      expect(game.knowledge.seen? 4, 5).to be_false
      expect(game.log.last?.to_s).to contain "Nothing is lying"
    end

    it "names what it found, nearest first" do
      game = bare
      game.floor.drop 5, 5, Item.new(Kind::Mace)
      game.floor.drop 4, 5, Item.new(Kind::LongSword)

      game.read reading(game, Kind::DetectionScroll)

      lines = game.log.lines.select &.starts_with?("You feel")
      expect(lines.size).to eq 2
      expect(lines[0]).to contain "long sword"
      expect(lines[1]).to contain "mace"
    end

    describe "cursed" do
      # A sword does not stack, so ten of them on one square are ten
      # entries.
      it "destroys a fifth of what it found, rounded up" do
        game = bare
        10.times { game.floor.drop 4, 5, Item.new(Kind::LongSword) }

        game.read reading(game, Kind::DetectionScroll, Blessing::Cursed)

        left = 0
        game.floor.each_pile { |_column, _row, pile| left += pile.size }

        expect(left).to eq 8
      end

      it "destroys something even when it found one thing" do
        game = bare
        game.floor.drop 4, 5, Item.new(Kind::LongSword)

        game.read reading(game, Kind::DetectionScroll, Blessing::Cursed)

        expect(game.floor.items?(4, 5)).to be_false
      end

      # A thing that no longer exists has no secret left to keep.
      it "names what it destroyed in full" do
        game = bare
        game.floor.drop 4, 5, Item.new(Kind::HealingPotion,
          blessing: Blessing::Blessed)

        game.read reading(game, Kind::DetectionScroll, Blessing::Cursed)

        expect(game.log.lines.any? do |line|
          line.includes?("blessed potion of healing") && line.includes?("destroyed")
        end).to be_true
      end

      # Naming it teaches nothing. The colour that kind comes in still means
      # nothing for the rest of the run.
      it "teaches the character nothing by naming it" do
        game = bare
        game.floor.drop 4, 5, Item.new(Kind::HealingPotion)

        game.read reading(game, Kind::DetectionScroll, Blessing::Cursed)

        expect(game.lore.known? Kind::HealingPotion).to be_false
      end

      it "says nothing about where a destroyed thing was" do
        game = bare
        game.floor.drop 4, 5, Item.new(Kind::LongSword)

        game.read reading(game, Kind::DetectionScroll, Blessing::Cursed)

        expect(game.knowledge[4, 5].try &.item).to be_nil
      end
    end
  end

  describe "a scroll of darkness" do
    it "puts out a carried torch" do
      game = bare
      torch = Item.new Kind::Torch, lit: true
      game.player.inventory.add torch

      game.read reading(game, Kind::DarknessScroll)

      expect(torch.lit?).to be_false
    end

    it "puts out a sconce in reach" do
      game = bare
      fitting = Roguelike::Fixture.new Roguelike::FixtureKind::Sconce, true
      game.floor.set_fixture 6, 5, fitting

      game.read reading(game, Kind::DarknessScroll)

      expect(fitting.lit?).to be_false
      expect(game.floor.fixture 6, 5).not_to be_nil
    end

    it "takes the glow off the squares" do
      game = bare
      game.floor.set_glow 6, 5, 4

      game.read reading(game, Kind::DarknessScroll)

      expect(game.floor.glow_at 6, 5).to eq 0
    end

    it "says so when there is nothing to put out" do
      game = bare

      game.read reading(game, Kind::DarknessScroll)

      expect(game.log.lines.any? &.includes?("already as deep")).to be_true
    end

    describe "cursed" do
      it "burns a carried torch away" do
        game = bare
        game.player.inventory.add Item.new(Kind::Torch, lit: true)

        game.read reading(game, Kind::DarknessScroll, Blessing::Cursed)

        expect(game.player.inventory.items.any? &.last.kind.torch?).to be_false
      end

      it "leaves a blessed one alone" do
        game = bare
        game.player.inventory.add Item.new(Kind::Torch, lit: true,
          blessing: Blessing::Blessed)

        game.read reading(game, Kind::DarknessScroll, Blessing::Cursed)

        expect(game.player.inventory.items.any? &.last.kind.torch?).to be_true
      end

      it "takes a sconce off the wall" do
        game = bare
        game.floor.set_fixture 6, 5,
          Roguelike::Fixture.new(Roguelike::FixtureKind::Sconce, true)

        game.read reading(game, Kind::DarknessScroll, Blessing::Cursed)

        expect(game.floor.fixture 6, 5).to be_nil
      end
    end

    # The only scroll that survives being read.
    it "is sometimes still there when it was blessed" do
      kept = 0

      40.times do |index|
        game = bare Playing::SEED + index.to_u64
        game.player.inventory.add Item.new(Kind::Torch, lit: true)
        letter = reading game, Kind::DarknessScroll, Blessing::Blessed

        game.read letter
        kept += 1 if game.player.inventory.items.any? &.last.kind.darkness_scroll?
      end

      expect(kept).to be > 5
      expect(kept).to be < 35
    end
  end

  describe "a scroll of blindness" do
    def goblin(game : Roguelike::Game, at : {Int32, Int32}) : Monster
      creature = Monster.new Species::Goblin, at[0], at[1], "band-one"
      game.floor.place creature
      creature
    end

    # Reading takes a turn, so the creature has moved by the time the square
    # is asked for. The square is where it is standing then.
    it "blinds what it was aimed at" do
      game = bare
      creature = goblin game, {6, 5}
      scroll = game.start_aiming_read reading(game, Kind::BlindnessScroll)
      raise "no scroll" unless scroll

      game.aim_reading scroll, creature.at

      expect(creature.blind?).to be_true
    end

    it "settles on nothing when it was aimed at nothing" do
      game = bare
      scroll = game.start_aiming_read reading(game, Kind::BlindnessScroll)
      raise "no scroll" unless scroll

      game.aim_reading scroll, {9, 5}

      expect(game.log.last?.to_s).to contain "settles on nothing"
    end

    it "blinds the reader when it is cursed" do
      game = bare

      game.read reading(game, Kind::BlindnessScroll, Blessing::Cursed)

      expect(game.player.blind?).to be_true
      expect(game.player.blinded).to be >= 2
      expect(game.player.blinded).to be <= 12
    end

    it "blinds everything in sight when it is blessed" do
      game = bare
      near = goblin game, {6, 5}
      far = goblin game, {8, 7}

      game.read reading(game, Kind::BlindnessScroll, Blessing::Blessed)

      expect(near.blind?).to be_true
      expect(far.blind?).to be_true
    end

    it "asks for a square only when it needs one" do
      asks = ->(blessing : Blessing) do
        game = bare
        game.target_needed? reading(game, Kind::BlindnessScroll, blessing)
      end

      expect(asks.call Blessing::Uncursed).to be_true
      expect(asks.call Blessing::Cursed).to be_false
      expect(asks.call Blessing::Blessed).to be_false
    end
  end

  describe "being blind" do
    it "leaves the character seeing their own square and no more" do
      game = bare
      game.player.blind 5

      expect(game.sight.size).to eq 1
      expect(game.can_see? 3, 5).to be_true
      expect(game.can_see? 6, 5).to be_false
    end

    it "wears off" do
      game = bare
      game.player.blind 3

      3.times { game.wait }

      expect(game.player.blind?).to be_false
      expect(game.log.lines.any? &.includes?("see again")).to be_true
    end

    it "keeps a blind creature from noticing the character" do
      game = bare
      creature = Monster.new Species::Orc, 5, 5, "band-one"
      game.floor.place creature
      creature.blind 20

      10.times { game.wait }

      expect(game.awake? creature).to be_false
    end
  end

  describe "a scroll of minor teleport" do
    it "puts the character somewhere far off" do
      game = bare
      before = game.player.at

      game.read reading(game, Kind::TeleportScroll)

      expect(game.player.at).not_to eq before
      expect(Roguelike::Notice.within? before, game.player.at, 14).to be_false
    end

    it "puts them where they chose when it is blessed" do
      game = bare
      scroll = game.start_aiming_read reading(game, Kind::TeleportScroll,
        Blessing::Blessed)
      raise "no scroll" unless scroll

      game.aim_reading scroll, {18, 2}

      expect(game.player.at).to eq({18, 2})
    end

    it "refuses a square nothing could stand on when it is blessed" do
      game = bare
      before = game.player.at
      scroll = game.start_aiming_read reading(game, Kind::TeleportScroll,
        Blessing::Blessed)
      raise "no scroll" unless scroll

      game.aim_reading scroll, {0, 0}

      expect(game.player.at).to eq before
      expect(game.log.last?.to_s).to contain "nowhere to go"
    end

    it "puts them beside the worst thing on the floor when it is cursed" do
      game = bare
      slime = Monster.new Species::Slime, 8, 2, "band-one"
      orc = Monster.new Species::Orc, 18, 8, "band-two"
      game.floor.place slime
      game.floor.place orc

      game.read reading(game, Kind::TeleportScroll, Blessing::Cursed)

      expect(Roguelike::Notice.touching? game.player.at, orc.at).to be_true
    end

    it "does nothing when it is cursed and the floor is empty" do
      game = bare
      before = game.player.at

      game.read reading(game, Kind::TeleportScroll, Blessing::Cursed)

      expect(game.player.at).to eq before
      expect(game.log.last?.to_s).to contain "nothing to fear"
    end

    it "asks for a square only when it is blessed" do
      asks = ->(blessing : Blessing) do
        game = bare
        game.target_needed? reading(game, Kind::TeleportScroll, blessing)
      end

      expect(asks.call Blessing::Uncursed).to be_false
      expect(asks.call Blessing::Cursed).to be_false
      expect(asks.call Blessing::Blessed).to be_true
    end
  end
end
