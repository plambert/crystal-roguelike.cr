require "../spec_helper"
require "../support/recording"

Spectator.describe "wielding and wearing by one key" do
  alias Action = Roguelike::Action
  alias Awareness = Roguelike::Awareness
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Slot = Roguelike::Slot
  alias Species = Roguelike::Species
  alias Verifier = Roguelike::Replay::Verifier

  SWAP_SEED = 20261014_u64

  # A short corridor running north into a long one running east. Nothing of
  # the east corridor is in sight from the staircase.
  BEND = [
    "#########################",
    "#.......................#",
    "########.################",
    "########.################",
    "########<################",
    "#########################",
  ]

  # Where a creature waits in `BEND`, round the corner from the character.
  ROUND_THE_CORNER = {11, 1}

  # A lit game on `BEND` with the character on the staircase carrying
  # *items*. The first of *readied* is wielded or worn already.
  def carrying(items : Array(Item), readied : Item? = nil) : Game
    floor = Floor.parse "here", BEND
    floor.ambient = 1
    player = Roguelike::Player.new "here", *Game.entrance(floor), hit_points: 40
    items.each { |item| player.inventory.add item }
    readied.try { |item| ready player, item }

    game = Game.new Roguelike::World.new(SWAP_SEED, {"here" => floor}), player
    game.enroll
    game
  end

  # Puts *item* in its slot without a turn passing.
  def ready(player : Roguelike::Player, item : Item) : Nil
    slot = Slot.for(item)
    raise "#{item.kind} has no slot" unless slot

    player.inventory.each_item do |letter, held|
      player.equipment.put slot, letter if held.same? item
    end
  end

  # A goblin at *spot*, round the corner from the character, hunting them.
  def lurking(game : Game, spot : {Int32, Int32} = ROUND_THE_CORNER) : Monster
    goblin = Monster.new Species::Goblin, *spot, "band-one"
    game.floor.place goblin

    band = game.floor.band goblin.band
    raise "no band" unless band
    known = band.knowledge "here"
    game.floor.each { |column, row, _tile| known.see game.floor, column, row }
    known.saw Roguelike::Knowledge::PLAYER, *game.player.at, 0
    band.awareness = Awareness::Hunting
    game.enroll
    goblin
  end

  # Whether *game*'s character carries *item*.
  def carries?(game : Game, item : Item) : Bool
    found = false
    game.player.inventory.each_item { |_letter, held| found ||= held.same? item }
    found
  end

  # Every action the replay at *path* holds, in order.
  def acts(path : String) : Array(Action)
    Recording.read(path).records.compact_map(&.as?(Roguelike::Replay::Act)).map &.action
  end

  it "wields a weapon" do
    sword = Item.new Kind::LongSword
    game = carrying [sword]

    expect(game.don sword.id).to be_true
    expect(game.player.wielded).to be sword
    expect(game.log.last?).to contain "now holding"
  end

  it "wears armor" do
    mail = Item.new Kind::ChainMail
    game = carrying [mail]

    expect(game.don mail.id).to be_true
    expect(game.player.in_slot Slot::Body).to be mail
    expect(game.log.last?).to contain "now wearing"
  end

  it "takes the old piece off and puts the new one on over two actions" do
    mail = Item.new Kind::ChainMail
    leather = Item.new Kind::LeatherArmor
    game = carrying [mail, leather], mail
    turn = game.turn

    expect(game.don leather.id).to be_true
    expect(game.player.in_slot Slot::Body).to be leather
    expect(game.log.lines.last(2)).to eq ["You are no longer wearing chain mail.",
                                          "You are now wearing leather armor."]
    expect(game.turn - turn).to eq 2 * (Roguelike::Costs::BODY // Roguelike::Pace::TICK)
  end

  it "swaps one weapon for another the same way" do
    dagger = Item.new Kind::Dagger
    sword = Item.new Kind::LongSword
    game = carrying [dagger, sword], dagger

    game.don sword.id

    expect(game.player.wielded).to be sword
    expect(game.log.lines.last(2).first).to contain "no longer holding a dagger"
  end

  it "stops after the first action when a creature comes into view" do
    mail = Item.new Kind::ChainMail
    leather = Item.new Kind::LeatherArmor
    game = carrying [mail, leather], mail
    lurking game
    expect(game.monsters_in_sight).to be_empty

    expect(game.don leather.id).to be_false
    expect(game.player.in_slot Slot::Body).to be_nil
    expect(carries? game, leather).to be_true
    expect(game.log.last?).to eq "You are interrupted, and have not put on the leather armor yet!"
    expect(game.events.last).to be_a Event::Interrupted
    expect(game.events.last.as(Event::Interrupted).halt).to eq Halt::Creature
  end

  it "says a weapon has not been wielded when a swap of weapons stops" do
    dagger = Item.new Kind::Dagger
    sword = Item.new Kind::LongSword
    game = carrying [dagger, sword], dagger
    lurking game, {9, 1}
    expect(game.monsters_in_sight).to be_empty

    game.don sword.id

    expect(game.player.wielded).to be_nil
    expect(game.log.last?).to eq "You are interrupted, and have not wielded the long sword yet!"
  end

  it "refuses to start when the piece worn is cursed" do
    mail = Item.new Kind::ChainMail, blessing: Roguelike::Blessing::Cursed
    leather = Item.new Kind::LeatherArmor
    game = carrying [mail, leather], mail
    turn = game.turn

    expect(game.don leather.id).to be_false
    expect(game.player.in_slot Slot::Body).to be mail
    expect(game.log.last?).to eq "You cannot let go of cursed chain mail."
    expect(game.turn).to eq turn
  end

  it "replays a swap as the two actions it took" do
    where = (Recording.directory / "swap-#{Random.rand UInt32}.jsonl").to_s
    mail = Item.new Kind::ChainMail
    leather = Item.new Kind::LeatherArmor
    game = carrying [mail, leather], mail
    game.player.name = Recording::PLAYER

    Recording.recording where do
      game.don leather.id
      game
    end

    expect(acts(where).map &.class).to eq [Action::Remove, Action::Wear]
    expect(Verifier.check(where).ok?).to be_true
  end

  it "replays a swap a creature stopped" do
    where = (Recording.directory / "swap-stopped-#{Random.rand UInt32}.jsonl").to_s
    mail = Item.new Kind::ChainMail
    leather = Item.new Kind::LeatherArmor
    game = carrying [mail, leather], mail
    game.player.name = Recording::PLAYER
    lurking game

    Recording.recording where do
      game.don leather.id
      game
    end

    expect(game.log.last?).to contain "interrupted"
    expect(acts(where).map &.class).to eq [Action::Remove]
    expect(Verifier.check(where).ok?).to be_true
  end
end
