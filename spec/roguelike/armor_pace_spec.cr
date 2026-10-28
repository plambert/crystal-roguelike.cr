require "../spec_helper"

Spectator.describe "what armor costs in pace" do
  alias Bulk = Roguelike::Bulk
  alias Costs = Roguelike::Costs
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Kinds = Roguelike::Kinds
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Slot = Roguelike::Slot

  HALL = ["########################################",
          "#......................................#",
          "#......................................#",
          "#......................................#",
          "########################################"]

  # Enough hit points that nothing in a spec ends the run.
  PLENTY = 100_000

  # A long hall with the character at its west end wearing *kinds*.
  def hall(kinds : Array(Kind) = [] of Kind) : Game
    floor = Roguelike::Floor.parse "hall", HALL.join('\n')
    floor.ambient = 1

    player = Player.new "hall", 1, 2, hit_points: PLENTY
    kinds.each do |kind|
      item = Item.new kind, blessing_known: true
      letter = player.inventory.add(item) || raise "pack full"
      player.equipment.put(Slot.for(item) || raise("no slot"), letter)
    end

    Game.new Roguelike::World.new(20261028_u64, {"hall" => floor}), player
  end

  # How many turns the character takes to walk *squares* squares east.
  def turns_for(game : Game, squares : Int32) : Int32
    squares.times { game.step Roguelike::Direction::East }
    game.turn
  end

  # A hunting orc at the far end of *game*'s hall, wearing *kinds*.
  def orc(game : Game, kinds : Array(Kind) = [] of Kind) : Monster
    creature = Monster.new Roguelike::Kind::Orc, 38, 2, "band", hit_points: PLENTY
    creature.outfit kinds.map { |kind| Item.new kind }
    game.floor.place creature

    band = game.floor.band(creature.band) || raise "no band"
    band.awareness = Roguelike::Awareness::Hunting
    knowledge = band.knowledge game.floor.id
    game.floor.each { |column, row, _tile| knowledge.see game.floor, column, row }
    knowledge.saw Roguelike::Knowledge::PLAYER, 1, 2, game.turn
    creature
  end

  # How many steps *creature* takes while the character waits from tick 5 to
  # tick 25. The first ticks go on the band taking stock, so the count
  # starts after them.
  def steps_of(game : Game, creature : Monster) : Int32
    while game.turn < 5
      game.wait
    end

    steps = 0
    while game.turn < 25
      was = {creature.x, creature.y}
      game.wait
      steps += 1 unless {creature.x, creature.y} == was
    end
    steps
  end

  describe "the table" do
    it "costs a step 90, 95, 100, 105 and 110 by class" do
      expect(Bulk.values.map &.step).to eq [90, 95, 100, 105, 110]
    end

    it "adds 0, 5, 10, 20 and 30 to a blow by class" do
      expect(Bulk.values.map &.blow).to eq [0, 5, 10, 20, 30]
    end

    it "classes the body armor and leaves the rest out" do
      expect(Kind::PaddedJacket.bulk).to eq Bulk::Light
      expect(Kind::LeatherArmor.bulk).to eq Bulk::Medium
      expect(Kind::ChainMail.bulk).to eq Bulk::Heavy
      expect(Kind::PaddedJacket.armor).to be < Kind::LeatherArmor.armor
    end

    it "reads the class from the body armor alone" do
      expect(Costs.body([] of Item)).to eq Bulk::None
      expect(Costs.body([Item.new(Kind::Cap), Item.new(Kind::Shield)])).to eq Bulk::None
      expect(Costs.body([Item.new(Kind::Cap), Item.new(Kind::ChainMail)])).to eq Bulk::Heavy
    end

    it "adds the body armor's blow cost and a shield's" do
      expect(Costs.blow_drag([Item.new(Kind::Cap), Item.new(Kind::Boots)])).to eq 0
      expect(Costs.blow_drag([Item.new(Kind::Shield)])).to eq 10
      expect(Costs.blow_drag([Item.new(Kind::LeatherArmor)])).to eq 10
      expect(Costs.blow_drag([Item.new(Kind::ChainMail), Item.new(Kind::Shield)])).to eq 30
    end

    it "words a part of a turn" do
      expect(Costs.share 5).to eq "a twentieth"
      expect(Costs.share 10).to eq "a tenth"
      expect(Costs.share 20).to eq "a fifth"
      expect(Costs.share 35).to eq "35%"
    end
  end

  describe "the character" do
    it "walks twenty squares in eighteen turns in nothing" do
      game = hall [Kind::Cap, Kind::Shield]

      expect(game.player.stride).to eq 90
      expect(turns_for game, 20).to eq 18
    end

    it "walks a square a turn in leather armor" do
      game = hall [Kind::LeatherArmor]

      expect(game.player.stride).to eq 100
      expect(turns_for game, 20).to eq 20
    end

    it "walks slower in chain mail" do
      game = hall [Kind::ChainMail]

      expect(game.player.stride).to eq 105
      expect(turns_for game, 20).to eq 21
    end

    it "steps 95 in a padded jacket" do
      expect(hall([Kind::PaddedJacket]).player.stride).to eq 95
    end

    it "swings slower in body armor and with a shield" do
      expect(hall.player.swing).to eq Costs::BARE
      expect(hall([Kind::Shield]).player.swing).to eq Costs::BARE + 10
      expect(hall([Kind::ChainMail, Kind::Shield]).player.swing).to eq Costs::BARE + 30
    end

    it "says what chain mail does when it goes on and comes off" do
      game = hall
      letter = game.player.inventory.add(Item.new(Kind::ChainMail)) || raise "pack full"

      game.wear letter
      expect(game.log.lines.last).to eq "You are now wearing chain mail. " \
                                        "You walk 15% slower and swing a fifth slower now."

      game.take_off Slot::Body
      expect(game.log.lines.last).to eq "You are no longer wearing chain mail. " \
                                        "You walk 15% faster and swing a fifth faster now."
    end

    it "says what a shield does to a blow" do
      game = hall
      letter = game.player.inventory.add(Item.new(Kind::Shield)) || raise "pack full"

      game.wear letter
      expect(game.log.lines.last).to eq "You are now wearing a shield. You swing a tenth slower now."
    end

    it "says nothing more about a cap" do
      game = hall
      letter = game.player.inventory.add(Item.new(Kind::Cap)) || raise "pack full"

      game.wear letter
      expect(game.log.lines.last).to eq "You are now wearing a cap."
    end
  end

  describe "the description" do
    def about(kind : Kind) : Array(String)
      Roguelike::Ui::Detail.about hall, Item.new(kind)
    end

    it "says what leather armor does to a step and a blow" do
      expect(about Kind::LeatherArmor).to contain "medium: steps at a normal pace"
      expect(about Kind::LeatherArmor).to contain "attacks a tenth slower (+10%)"
    end

    it "says how much quicker a padded jacket steps" do
      expect(about Kind::PaddedJacket).to contain "light: steps a twentieth quicker (-5%)"
    end

    it "says how much chain mail slows a step and a blow" do
      expect(about Kind::ChainMail).to contain "heavy: steps a twentieth slower (+5%)"
      expect(about Kind::ChainMail).to contain "attacks a fifth slower (+20%)"
    end

    it "says a shield slows a blow and not a step" do
      expect(about Kind::Shield).to contain "does not slow a step"
      expect(about Kind::Shield).to contain "attacks a tenth slower (+10%)"
    end

    it "says a cap does not change the pace" do
      expect(about Kind::Cap).to contain "does not change your pace"
    end
  end

  describe "a creature" do
    around_each do |example|
      Kinds.override = 100
      example.run
    ensure
      Kinds.override = nil
    end

    it "walks in its hide when it wears no body armor" do
      Roguelike::Kind.each do |kind|
        expect(kind.hide).to eq Bulk::Medium
        expect(Monster.new(kind, 1, 1, "band").stride).to eq 100
      end
    end

    it "costs its steps and blows by the same rule as the character" do
      plain = Monster.new Roguelike::Kind::Orc, 1, 1, "band"
      armored = Monster.new Roguelike::Kind::Orc, 1, 1, "band"
      armored.outfit [Item.new(Kind::ChainMail), Item.new(Kind::Shield)]

      expect(armored.stride).to eq 105
      expect(armored.swing).to eq plain.swing + 30
    end

    it "walks slower in chain mail" do
      plain = hall
      bare = steps_of plain, orc(plain)

      heavy = hall
      mailed = steps_of heavy, orc(heavy, [Kind::ChainMail])

      expect(bare).to eq 20
      expect(mailed).to eq 19
    end
  end

  describe "a goblin scout" do
    it "wears small leather armor and keeps its armor class" do
      kind = Roguelike::Kind::GoblinScout
      scout = Monster.new kind, 1, 1, "band"
      scout.outfit Roguelike::Loot.for(kind, Roguelike::Rng.new(7_u64), 1)
      body = scout.in_slot(Slot::Body) || raise "no body armor"

      expect(body.kind).to eq Kind::LeatherArmor
      expect(body.size).to eq Roguelike::Size::Small
      expect(body.fits? Player::SIZE).to be_false
      expect(scout.stride).to eq 100
    end
  end
end
