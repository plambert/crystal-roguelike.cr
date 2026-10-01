require "../spec_helper"
require "../support/recording"

# Piles in the pack that become identical once the character learns something
# about one of them.
Spectator.describe "restacking the pack" do
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Blessing = Roguelike::Blessing
  alias Action = Roguelike::Action
  alias Slot = Roguelike::Slot

  LINE = "You organize your pack more efficiently."

  # A game with *items* in the pack, given ids.
  def packed(*items : Item) : Game
    game = Playing.field 20, 10
    items.each { |item| game.player.inventory.add item }
    game.enroll
    game
  end

  # The pile under *letter* in *game*.
  def pile(game : Game, letter : Char) : Item
    game.player.inventory[letter] || raise "nothing under #{letter}"
  end

  # How often the line is in the log.
  def lines(game : Game) : Int32
    game.log.lines.count LINE
  end

  # Reads the scroll of identify under *scroll* and names the pile *target*.
  def identify(game : Game, scroll : Char, target : Char) : Nil
    game.perform Action::Read.new pile(game, scroll).id,
      pile(game, target).id
  end

  def arrows(count : Int32, blessing : Blessing = Blessing::Uncursed,
             known : Bool = false, enchantment : Int32 = 0) : Item
    Item.new Kind::Arrow, count: count, blessing: blessing,
      blessing_known: known, enchantment: enchantment
  end

  def scroll : Item
    Item.new Kind::IdentifyScroll, blessing_known: true
  end

  describe "arrows that differ in a hidden blessing" do
    let(game) { packed arrows(3, Blessing::Blessed, true), arrows(2, Blessing::Blessed), scroll }

    it "sit apart until the blessing is learned" do
      expect(game.player.inventory.count 'a').to eq 3
      expect(game.player.inventory.count 'b').to eq 2
    end

    it "merge the turn it is learned" do
      identify game, 'c', 'b'

      expect(game.player.inventory.count 'a').to eq 5
      expect(game.player.inventory.has? 'b').to be_false
      expect(lines game).to eq 1
    end

    it "keep the id of the earlier letter" do
      kept = pile(game, 'a').id
      gone = pile(game, 'b').id
      identify game, 'c', 'b'

      expect(pile(game, 'a').id).to eq kept
      expect(game.item gone).to be_nil
    end

    it "keep the quivered letter and its id" do
      game.player.equipment.put Slot::Quiver, 'b'
      kept = pile(game, 'b').id
      identify game, 'c', 'b'

      expect(game.player.inventory.count 'b').to eq 5
      expect(game.player.inventory.has? 'a').to be_false
      expect(game.player.equipment[Slot::Quiver]).to eq 'b'
      expect(pile(game, 'b').id).to eq kept
    end

    it "records the ids that merged" do
      kept = pile(game, 'a').id
      gone = pile(game, 'b').id
      identify game, 'c', 'b'
      event = game.events.compact_map(&.as?(Roguelike::Event::Restacked)).first

      expect(event.kept).to eq [kept]
      expect(event.gone).to eq [gone]
    end
  end

  describe "stacks that still differ" do
    it "stay apart when the blessings differ" do
      game = packed arrows(3, Blessing::Blessed, true), arrows(2), scroll
      identify game, 'c', 'b'

      expect(game.player.inventory.count 'a').to eq 3
      expect(game.player.inventory.count 'b').to eq 2
      expect(lines game).to eq 0
    end

    it "stay apart when the enchantments differ" do
      game = packed arrows(3, Blessing::Blessed, true), arrows(2, Blessing::Blessed, false, 1), scroll
      identify game, 'c', 'b'

      expect(game.player.inventory.has? 'a').to be_true
      expect(game.player.inventory.has? 'b').to be_true
      expect(lines game).to eq 0
    end
  end

  describe "unidentified potions" do
    it "merge when learning one makes their blessings known and equal" do
      known = Item.new Kind::MinorHealingPotion, blessing_known: true
      hidden = Item.new Kind::MinorHealingPotion
      game = packed known, hidden, scroll
      identify game, 'c', 'b'

      expect(game.player.inventory.size).to eq 1
      expect(game.player.inventory.count 'a').to eq 2
    end
  end

  describe "the message" do
    it "is written once however many stacks merge" do
      blessing = Item.new Kind::BlessingScroll, blessing_known: true
      game = packed arrows(3, Blessing::Blessed, true), arrows(2, Blessing::Blessed),
        Item.new(Kind::Dart, count: 3, blessing: Blessing::Blessed, blessing_known: true),
        Item.new(Kind::Dart, count: 2, blessing: Blessing::Blessed), blessing
      game.perform Action::Read.new pile(game, 'e').id

      event = game.events.compact_map(&.as?(Roguelike::Event::Restacked)).first
      expect(event.kept.size).to eq 2
      expect(lines game).to eq 1
    end
  end

  describe "a save" do
    it "keeps two stacks that now match until something is learned" do
      kept = Playing.store
      game = packed arrows(3, Blessing::Blessed, true), arrows(2, Blessing::Blessed), scroll
      game.player.name = "Sparky"
      pile(game, 'b').reveal_blessing
      kept.write game
      again = (kept.held("Sparky") || raise "no save").game

      expect(again.player.inventory.has? 'a').to be_true
      expect(again.player.inventory.has? 'b').to be_true

      identify again, 'c', 'a'

      expect(again.player.inventory.has? 'b').to be_false
      expect(again.player.inventory.count 'a').to eq 5
    end
  end

  describe "a replay" do
    it "verifies a run with a merge in it" do
      where = (Recording.directory / "restack-#{Random.rand UInt32}.jsonl").to_s

      Recording.recording where do
        game = packed arrows(3, Blessing::Blessed, true), arrows(2, Blessing::Blessed), scroll
        game.player.name = "restack"
        identify game, 'c', 'b'
        game.perform Action::Wait.new
        game
      end

      expect(Roguelike::Replay::Verifier.check(where).trouble).to be_nil
    end
  end
end
