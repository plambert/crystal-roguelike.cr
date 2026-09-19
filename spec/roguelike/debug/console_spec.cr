require "../../spec_helper"

Spectator.describe Roguelike::Debug::Console do
  alias Blessing = Roguelike::Blessing
  alias Console = Roguelike::Debug::Console
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Rng = Roguelike::Rng
  alias Species = Roguelike::Species
  alias Terrain = Roguelike::Terrain

  # The seed every example here runs on. A failure names a run somebody can
  # start.
  SEED = 20260914_u64

  # A game on one open room, and a console over it.
  def playing : {Game, Console}
    {Playing.field(20, 12, SEED), Console.new}
  end

  # What the console wrote after running each of *commands*.
  def after(*commands : String) : Array(String)
    game, console = playing
    commands.each { |line| console.run line, game }

    console.lines
  end

  # The last line the console wrote after running each of *commands*.
  def last(*commands : String) : String
    after(*commands).last
  end

  describe "#run" do
    it "echoes what was typed" do
      expect(after "help").to contain "> help"
    end

    it "does nothing at all with a blank line" do
      game, console = playing
      console.run "   ", game

      expect(console.lines).to be_empty
    end

    it "says so when the command is not one it has" do
      expect(last "trombone").to eq "no such command: trombone. Type help."
    end

    it "takes a command in any case" do
      expect(last "HELP").not_to contain "no such command"
    end
  end

  describe "help" do
    it "lists every command" do
      written = after "help"

      Console::TABLE.each do |command|
        expect(written.any? &.includes?(command.usage)).to be_true
      end
    end
  end

  describe "heal and hurt" do
    it "puts hit points back" do
      game, console = playing
      game.player.hurt 5
      console.run "heal 3", game

      expect(console.lines.last).to contain "healed 3"
    end

    it "fills up when it is given no number" do
      game, console = playing
      game.player.hurt 5
      console.run "heal", game

      expect(game.player.hit_points).to eq game.player.max_hit_points
    end

    it "takes hit points off" do
      game, console = playing
      before = game.player.hit_points
      console.run "hurt 4", game

      expect(game.player.hit_points).to eq before - 4
    end

    # Ending a run belongs to the blow that killed the character. The console
    # deals no blows, so it stops at one hit point.
    it "leaves one hit point rather than killing" do
      game, console = playing
      console.run "hurt 1000", game

      expect(game.player.hit_points).to eq 1
      expect(game.player.alive?).to be_true
    end

    it "says so when it was given no number to hurt for" do
      expect(last "hurt").to contain "how much"
    end
  end

  describe "spawn" do
    it "puts what it made in the pack" do
      game, console = playing
      console.run "spawn +1 bow", game

      carried = game.player.inventory.entries
      expect(carried.size).to eq 1
      expect(carried.first[1].kind).to eq Kind::Bow
      expect(carried.first[1].enchantment).to eq 1
    end

    it "names the letter it went under" do
      expect(last "spawn bow").to eq "a - a bow"
    end

    it "says why it made nothing" do
      expect(last "spawn trombone").to contain "trombone"
    end

    it "counts gold rather than carrying it" do
      game, console = playing
      console.run "spawn 40 gold", game

      expect(game.player.gold).to eq 40
      expect(game.player.inventory).to be_empty
    end

    it "drops what it made when every letter is taken" do
      game, console = playing
      Roguelike::Inventory::LETTERS.each do |letter|
        game.player.inventory.slots[letter] =
          Roguelike::Inventory::Stack.of Item.new(Kind::Dagger)
      end

      console.run "spawn bow", game

      expect(console.lines.last).to contain "underfoot"
      expect(game.here.map &.kind).to eq [Kind::Bow]
    end

    # Nothing the console does rolls, so a run plays out the same way whether
    # or not it was opened.
    it "takes no turn and rolls nothing" do
      game, console = playing
      before = game.turn
      console.run "spawn 12 +1 arrow", game

      expect(game.turn).to eq before
      expect(game.blows).to eq 0
      expect(game.uses).to eq 0
    end
  end

  describe "identify" do
    it "learns one carried kind" do
      game, console = playing
      game.player.inventory.add Item.new(Kind::HealingPotion)
      expect(game.lore.known? Kind::HealingPotion).to be_false

      console.run "identify a", game

      expect(game.lore.known? Kind::HealingPotion).to be_true
      expect(console.lines.last).to contain "potion of healing"
    end

    it "reveals the blessing of what it learned" do
      game, console = playing
      game.player.inventory.add Item.new(Kind::Dagger, blessing: Blessing::Cursed)
      console.run "identify a", game

      expect(game.player.inventory['a'].try &.blessing_known?).to be_true
    end

    it "learns a whole class at once" do
      game, console = playing
      console.run "identify potions", game

      expect(Kind.of_class(Roguelike::ItemClass::Potion).all? do |kind|
        game.lore.known? kind
      end).to be_true
    end

    it "learns every disguised class" do
      game, console = playing
      console.run "identify all", game

      expect(Kind.values.all? { |kind| game.lore.known? kind }).to be_true
    end

    it "says so when nothing is under the letter" do
      expect(last "identify z").to eq "nothing is under z."
    end

    it "says so when it was given no letter" do
      expect(last "identify").to contain "potions, scrolls, wands or all"
    end

    it "says so when it was given more than one letter" do
      expect(last "identify ab").to contain "one letter"
    end
  end

  describe "remove-curse" do
    it "takes the curse off one item" do
      game, console = playing
      game.player.inventory.add Item.new(Kind::Dagger, blessing: Blessing::Cursed)
      console.run "remove-curse a", game

      expect(game.player.inventory['a'].try &.cursed?).to be_false
    end

    it "says so when the item was not cursed" do
      game, console = playing
      game.player.inventory.add Item.new(Kind::Dagger)
      console.run "remove-curse a", game

      expect(console.lines.last).to eq "a was not cursed."
    end

    it "takes the curse off everything at once" do
      game, console = playing
      2.times { game.player.inventory.add Item.new(Kind::Dagger, blessing: Blessing::Cursed) }
      game.player.inventory.add Item.new(Kind::Bow)

      console.run "remove-curse all", game

      expect(console.lines.last).to eq "lifted 2 curses."
      expect(game.player.inventory.entries.any? { |_letter, item| item.cursed? }).to be_false
    end

    it "says so when nothing is under the letter" do
      expect(last "remove-curse z").to eq "nothing is under z."
    end
  end

  describe "kill" do
    it "takes the creature off the floor and awards its experience" do
      game, console = playing
      game.floor.place Monster.new(Species::Goblin, 3, 3, "band-one")
      before = game.player.experience

      console.run "kill 3,3", game

      expect(game.floor.monster 3, 3).to be_nil
      expect(game.player.experience).to be > before
      expect(console.lines.last).to eq "killed the goblin."
    end

    it "takes a square written with a space" do
      game, console = playing
      game.floor.place Monster.new(Species::Goblin, 3, 3, "band-one")
      console.run "kill 3 3", game

      expect(game.floor.monster 3, 3).to be_nil
    end

    it "says so when nothing is standing there" do
      expect(last "kill 3,3").to eq "nothing is standing on 3,3."
    end

    it "says so when it was given no square" do
      expect(last "kill").to contain "as x,y"
    end
  end

  describe "inspect" do
    it "prints the character when it is given no square" do
      written = after "inspect"

      expect(written.any? &.includes?("hit points")).to be_true
      expect(written.any? &.includes?("carrying")).to be_true
    end

    it "prints the creature on a square" do
      game, console = playing
      creature = Monster.new Species::Orc, 3, 3, "band-one"
      creature.carry [Item.new(Kind::Dagger)]
      game.floor.place creature

      console.run "inspect 3,3", game

      expect(console.lines.any? &.includes?("orc at 3,3")).to be_true
      expect(console.lines.any? &.includes?("dagger")).to be_true
    end

    it "says so when nothing is standing there" do
      expect(last "inspect 3,3").to eq "nothing is standing on 3,3."
    end
  end

  describe "goto" do
    it "puts the character on the square" do
      game, console = playing
      console.run "goto 2,2", game

      expect(game.player.at).to eq({2, 2})
      expect(console.lines.last).to eq "moved to 2,2."
    end

    it "refuses a square off the floor" do
      game, console = playing
      before = game.player.at
      console.run "goto 400,400", game

      expect(game.player.at).to eq before
      expect(console.lines.last).to contain "off the floor"
    end

    it "refuses rock" do
      expect(last "goto 0,0").to contain "cannot be walked onto"
    end

    it "refuses a square a creature is standing on" do
      game, console = playing
      game.floor.place Monster.new(Species::Goblin, 3, 3, "band-one")
      console.run "goto 3,3", game

      expect(console.lines.last).to eq "the goblin is standing there."
    end
  end

  describe "reveal" do
    it "remembers every square of the floor" do
      game, console = playing
      expect(game.player.knowledge.size).to be < game.floor.columns * game.floor.rows

      console.run "reveal", game

      expect(game.player.knowledge.size).to eq game.floor.columns * game.floor.rows
    end
  end

  describe "light" do
    it "sets the ambient light" do
      game, console = playing
      console.run "light 0", game

      expect(game.floor.ambient).to eq 0
      expect(console.lines.last).to eq "ambient light is 0."
    end

    it "prints the ambient light when it is given no number" do
      game, console = playing
      game.floor.ambient = 2
      console.run "light", game

      expect(console.lines.last).to eq "ambient light is 2."
    end
  end

  describe "#lines" do
    it "drops the oldest once it is holding as many as it keeps" do
      game, console = playing
      (Console::KEPT + 20).times { console.run "light", game }

      expect(console.lines.size).to eq Console::KEPT
    end
  end
end
