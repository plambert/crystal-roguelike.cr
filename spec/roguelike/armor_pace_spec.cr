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

  # How many squares east the character gets in *ticks* ticks.
  def walked_in(game : Game, ticks : Int32) : Int32
    start = game.player.x
    while game.turn < ticks
      game.step Roguelike::Direction::East
    end
    game.player.x - start
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
    it "slows a step by nothing, a tenth and a quarter" do
      expect(Bulk::Light.step).to eq 0
      expect(Bulk::Medium.step).to eq 10
      expect(Bulk::Heavy.step).to eq 25
    end

    it "slows a blow only in heavy armor" do
      expect(Bulk::Light.blow).to eq 0
      expect(Bulk::Medium.blow).to eq 0
      expect(Bulk::Heavy.blow).to eq 20
    end

    it "makes chain mail heavy and everything else light" do
      armor = Kind.values.select &.item_class.armor?
      heavy = armor.select &.bulk.heavy?

      expect(heavy).to eq [Kind::ChainMail]
      expect(Kind::LeatherArmor.bulk).to eq Bulk::Light
      expect(Kind::ShortSword.bulk).to eq Bulk::Light
    end

    it "costs a step in what is worn" do
      expect(Costs.step([] of Item)).to eq 100
      expect(Costs.step([Item.new(Kind::LeatherArmor), Item.new(Kind::Cap)])).to eq 100
      expect(Costs.step([Item.new(Kind::ChainMail)])).to eq 125
      expect(Costs.step([Item.new(Kind::ChainMail), Item.new(Kind::Shield)])).to eq 125
    end

    it "adds to a blow for chain mail and for a shield" do
      expect(Costs.blow_drag([Item.new(Kind::LeatherArmor)])).to eq 0
      expect(Costs.blow_drag([Item.new(Kind::Shield)])).to eq 10
      expect(Costs.blow_drag([Item.new(Kind::ChainMail)])).to eq 20
      expect(Costs.blow_drag([Item.new(Kind::ChainMail), Item.new(Kind::Shield)])).to eq 30
    end

    it "words a part of a turn" do
      expect(Costs.share 10).to eq "a tenth"
      expect(Costs.share 20).to eq "a fifth"
      expect(Costs.share 25).to eq "a quarter"
      expect(Costs.share 35).to eq "35 in a hundred"
    end
  end

  describe "the character" do
    it "walks a square a turn in light armor" do
      game = hall [Kind::LeatherArmor, Kind::Cap, Kind::Shield]

      expect(game.player.stride).to eq 100
      expect(walked_in game, 20).to eq 20
    end

    it "walks four squares in five turns in heavy armor" do
      game = hall [Kind::ChainMail]

      expect(game.player.stride).to eq 125
      expect(walked_in game, 20).to eq 16
    end

    it "swings slower in chain mail and with a shield" do
      expect(hall.player.swing).to eq Costs::BARE
      expect(hall([Kind::Shield]).player.swing).to eq Costs::BARE + 10
      expect(hall([Kind::ChainMail, Kind::Shield]).player.swing).to eq Costs::BARE + 30
    end

    it "says what chain mail does when it goes on and comes off" do
      game = hall
      letter = game.player.inventory.add(Item.new(Kind::ChainMail)) || raise "pack full"

      game.wear letter
      expect(game.log.lines.last).to eq "You are now wearing chain mail. Walking takes a " \
                                        "quarter longer in it, and each blow a fifth of a turn more."
      expect(game.player.stride).to eq 125

      game.take_off Slot::Body
      expect(game.log.lines.last).to eq "You are no longer wearing chain mail. " \
                                        "You walk and swing more freely without it."
      expect(game.player.stride).to eq 100
    end

    it "says what a shield does to a blow" do
      game = hall
      letter = game.player.inventory.add(Item.new(Kind::Shield)) || raise "pack full"

      game.wear letter
      expect(game.log.lines.last).to eq "You are now wearing a shield. " \
                                        "Each blow takes a tenth of a turn more with it."
    end

    it "says nothing more about light armor" do
      game = hall
      letter = game.player.inventory.add(Item.new(Kind::LeatherArmor)) || raise "pack full"

      game.wear letter
      expect(game.log.lines.last).to eq "You are now wearing leather armor."
    end
  end

  describe "the description" do
    it "says light armor does not slow walking" do
      expect(Roguelike::Ui::Detail.about hall, Item.new(Kind::LeatherArmor))
        .to contain "light: does not slow your walking"
    end

    it "says how much chain mail slows walking and blows" do
      lines = Roguelike::Ui::Detail.about hall, Item.new(Kind::ChainMail)

      expect(lines).to contain "heavy: walking takes a quarter longer"
      expect(lines).to contain "blows take a fifth of a turn more"
    end

    it "says how much a shield slows a blow" do
      lines = Roguelike::Ui::Detail.about hall, Item.new(Kind::Shield)

      expect(lines).to contain "light: does not slow your walking"
      expect(lines).to contain "blows take a tenth of a turn more"
    end
  end

  describe "a creature" do
    around_each do |example|
      Kinds.override = 100
      example.run
    ensure
      Kinds.override = nil
    end

    it "costs its steps and blows by the same rule" do
      plain = Monster.new Roguelike::Kind::Orc, 1, 1, "band"
      armored = Monster.new Roguelike::Kind::Orc, 1, 1, "band"
      armored.outfit [Item.new(Kind::ChainMail), Item.new(Kind::Shield)]

      expect(plain.stride).to eq 100
      expect(armored.stride).to eq 125
      expect(armored.swing).to eq plain.swing + 30
    end

    it "walks slower in chain mail" do
      plain = hall
      bare = steps_of plain, orc(plain)

      heavy = hall
      mailed = steps_of heavy, orc(heavy, [Kind::ChainMail])

      expect(bare).to eq 20
      expect(mailed).to eq 16
    end
  end
end
