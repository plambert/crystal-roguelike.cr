require "../../spec_helper"

Spectator.describe "UI command catalog" do
  alias Commands = Roguelike::Ui::Commands
  alias Command = Roguelike::Ui::Command
  alias CommandContext = Roguelike::Ui::CommandContext
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Floor = Roguelike::Floor
  alias Player = Roguelike::Player
  alias Slot = Roguelike::Slot
  alias Vision = Roguelike::Vision
  alias World = Roguelike::World

  SEED = 20261028_u64
  MAP  = [
    "#######",
    "#.....#",
    "#.....#",
    "#.....#",
    "#######",
  ]

  def bare_game(ambient : Int32 = 1) : Game
    floor = Floor.parse "catalog", MAP
    floor.ambient = ambient
    game = Game.new World.new(SEED, {floor.id => floor}), Player.new(floor.id, 2, 2)
    game.enroll
    game
  end

  def context(game : Game, viewing : Bool = false,
              item_id : Int32? = nil,
              slot : Slot? = nil,
              coordinate : {Int32, Int32}? = nil,
              vision : Vision? = nil) : CommandContext
    CommandContext.new game, viewing, false, item_id, slot, coordinate, vision
  end

  describe ".all" do
    it "gives every command a unique, ordered, key-free metadata record" do
      entries = Commands.all(debug: true)
      entries.concat Commands.all(debug: true, viewing: true)
      entries.uniq!(&.id)
      entries.sort_by!(&.order)

      expect(entries.map(&.id).size).to eq Command.values.size
      expect(entries.map(&.id).to_set).to eq Command.values.to_set
      expect(entries.map(&.order)).to eq (0...entries.size).to_a
      categories = entries.map(&.category.to_i)
      categories.sort!
      expect(entries.map(&.category.to_i)).to eq categories
      expect(entries.all? { |entry| !entry.label.empty? && !entry.description.empty? }).to be_true
    end

    it "keeps commands with empty targets discoverable in the live catalog" do
      entries = Commands.all

      expect(entries.map(&.id)).to contain Command::Read
      expect(entries.map(&.id)).to contain Command::Wait
      expect(entries.map(&.id)).not_to contain Command::DebugConsole
      expect(entries.map(&.id)).not_to contain Command::ReplayToggle
    end

    it "limits replay viewing to read-only commands and replay transport" do
      entries = Commands.all(viewing: true)
      ids = entries.map(&.id)

      expect(ids).not_to contain Command::Wait
      expect(ids).not_to contain Command::Rest
      expect(ids).not_to contain Command::Walk
      expect(ids).not_to contain Command::Explore
      expect(ids).not_to contain Command::PickUp
      expect(ids).not_to contain Command::Equip
      expect(ids).to contain Command::Inventory
      expect(ids).to contain Command::Examine
      expect(ids).to contain Command::Options
      expect(ids).to contain Command::ReplayToggle
      expect(ids).not_to contain Command::DebugConsole
    end
  end

  describe ".available" do
    it "omits Read without scrolls but keeps target-free Wait" do
      game = bare_game
      available = Commands.available(game, vision: Vision.lit(game.floor, *game.player.at))

      expect(Commands.all.map(&.id)).to contain Command::Read
      expect(available.map(&.id)).not_to contain Command::Read
      expect(available.map(&.id)).to contain Command::Wait
    end

    it "keeps wands available without exposing unknown charges or curses" do
      game = bare_game
      wand = Item.new ItemKind::LightWand, charges: 0,
        blessing: Roguelike::Blessing::Cursed, blessing_known: false
      game.player.inventory.add wand
      game.enroll

      available = Commands.available(game, vision: Vision.lit(game.floor, *game.player.at))

      expect(wand.charges).to eq 0
      expect(wand.blessing_known?).to be_false
      expect(available.map(&.id)).to contain Command::Zap
    end

    it "does not hide removal of an item with an unknown curse" do
      game = bare_game
      cursed = Item.new ItemKind::Dagger,
        blessing: Roguelike::Blessing::Cursed, blessing_known: false
      letter = game.player.inventory.add cursed
      raise "no inventory slot" unless letter
      game.player.equipment.put Slot::Melee, letter
      game.enroll
      selected = context game, item_id: cursed.id,
        vision: Vision.lit(game.floor, *game.player.at)

      available = Commands.available selected

      expect(available.map(&.id)).to contain Command::Remove
      expect(Commands.reason(Command::Remove, selected)).to be_nil
    end

    it "filters selected item actions by the selected item's known type" do
      game = bare_game
      potion = Item.new ItemKind::MinorHealingPotion
      game.player.inventory.add potion
      game.player.inventory.add Item.new ItemKind::Dagger
      game.enroll
      selected = context game, item_id: potion.id,
        vision: Vision.lit(game.floor, *game.player.at)

      available = Commands.available selected
      ids = available.map(&.id)

      expect(ids).to contain Command::Drink
      expect(ids).to contain Command::Drop
      expect(ids).to contain Command::Throw
      expect(ids).not_to contain Command::Equip
      expect(ids).not_to contain Command::Read
      expect(ids).not_to contain Command::Inventory
    end

    it "returns the representative ID for an entire inventory group" do
      game = bare_game
      letter = game.player.inventory.add Item.new(ItemKind::Arrow, count: 4)
      raise "no inventory slot" unless letter
      game.enroll
      group = game.carried letter
      raise "no carried group" unless group
      selected = context game, item_id: group.id,
        vision: Vision.lit(game.floor, *game.player.at)

      targets = Commands.targets(Command::Drop, selected)

      expect(group.count).to eq 4
      expect(targets.map(&.item_id)).to eq [group.id]
    end

    it "uses remembered door knowledge instead of hidden floor terrain" do
      floor = Floor.parse "doors", [
        "#######",
        "#.....#",
        "#.+...#",
        "#.....#",
        "#######",
      ]
      game = Game.new World.new(SEED, {floor.id => floor}), Player.new(floor.id, 1, 2)
      game.player.inventory.add Item.new ItemKind::Spike
      game.enroll
      seen = Vision.blind game.player.at
      hidden = context game, vision: seen

      expect(Commands.available?(Command::OpenDoor, hidden)).to be_false
      expect(Commands.available?(Command::SpikeDoor, hidden)).to be_false

      game.player.knowledge.see game.floor, 2, 2, game.turn
      known = context game, vision: seen

      expect(Commands.available?(Command::OpenDoor, known)).to be_true
      expect(Commands.available?(Command::SpikeDoor, known)).to be_true
      expect(Commands.targets(Command::OpenDoor, known).map(&.coordinate)).to eq [{2, 2}]
      expect(Commands.targets(Command::SpikeDoor, known).map(&.coordinate)).to eq [{2, 2}]
    end

    it "restricts viewer availability to read-only commands and replay transport" do
      game = bare_game
      viewer = context game, viewing: true,
        vision: Vision.lit(game.floor, *game.player.at)
      ids = Commands.available(viewer).map(&.id)

      expect(ids).not_to contain Command::Wait
      expect(ids).not_to contain Command::Rest
      expect(ids).not_to contain Command::Walk
      expect(ids).not_to contain Command::Explore
      expect(ids).not_to contain Command::PickUp
      expect(ids).not_to contain Command::Equip
      expect(ids).to contain Command::Inventory
      expect(ids).to contain Command::Examine
      expect(ids).to contain Command::Options
      expect(ids).to contain Command::ReplayToggle
    end

    it "leaves the game fingerprint, turn, random counters, and knowledge unchanged" do
      game = bare_game
      vision = Vision.lit game.floor, *game.player.at
      before = {
        game.fingerprint,
        game.turn,
        game.blows,
        game.uses,
        game.wanders,
        game.handled,
        game.player.memory.to_json,
        game.events.size,
      }

      Commands.all
      Commands.available context(game, vision: vision)
      Commands.status Command::Read, context(game, vision: vision)

      after = {
        game.fingerprint,
        game.turn,
        game.blows,
        game.uses,
        game.wanders,
        game.handled,
        game.player.memory.to_json,
        game.events.size,
      }

      expect(after).to eq before
    end
  end
end
