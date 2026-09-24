require "../spec_helper"

# The ids a run gives to its items and creatures.
#
# A bot and a replay log name a thing by its id rather than by the letter it
# sits under. A letter moves and an id does not. The ids have to follow from
# the seed and from nothing else, so a replay of a run reads the same names
# the run wrote.
Spectator.describe "entity ids" do
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Rng = Roguelike::Rng

  # The seed every example here runs on.
  SEED = 20260911_u64

  # Every id in *game*, each with a word for what has it.
  #
  # The word names the kind of thing. It does not name the particular one.
  # Two runs on one seed are then compared on the things rather than on the
  # objects holding them.
  def named(game : Game) : Array({Int32, String})
    found = [] of {Int32, String}

    game.world.floors.keys.sort!.each do |name|
      ground = game.world[name]

      ground.monsters.keys.sort!.each do |spot|
        creature = ground.monsters[spot]
        found << {creature.id, creature.species.to_s}
        creature.carrying.each { |held| found << {held.id, held.kind.to_s} }
      end

      ground.litter.keys.sort!.each do |spot|
        ground.litter[spot].each { |lot| found << {lot.id, lot.kind.to_s} }
      end
    end

    game.player.inventory.each_item do |_letter, item|
      found << {item.id, item.kind.to_s}
    end

    found
  end

  # Every id in *game*.
  def ids(game : Game) : Array(Int32)
    named(game).map { |id, _what| id }
  end

  # *game* written out with every id and the counter taken out. That is what
  # a save written before ids existed holds.
  #
  # The file is made here rather than checked in. A fixture would go stale
  # the first time the save format changed. What is under test is the reader
  # rather than any one old file.
  def stripped(game : Game) : String
    text = JSON.parse game.to_json
    text.as_h.delete "minted"
    unname text
    text.to_json
  end

  # Takes the `id` field out of every item and every creature under *found*.
  def unname(found : JSON::Any) : Nil
    raw = found.raw

    case raw
    when Hash(String, JSON::Any)
      raw.delete "id" if raw.has_key?("enchantment") || raw.has_key?("species")
      raw.each_value { |value| unname value }
    when Array(JSON::Any)
      raw.each { |value| unname value }
    end
  end

  describe "a dug run" do
    it "gives the same ids to the same things on one seed" do
      one = Game.dug Rng.new(SEED)
      two = Game.dug Rng.new(SEED)

      expect(named two).to eq named(one)
      expect(named(one).empty?).to be_false
    end

    it "gives every item and creature an id" do
      game = Game.dug Rng.new(SEED)

      expect(ids(game).includes?(0)).to be_false
    end

    it "gives no two things the same id" do
      game = Game.dug Rng.new(SEED)
      found = ids game

      expect(found.uniq.size).to eq found.size
    end

    it "counts from one in every run, so nothing carries between them" do
      one = Game.dug Rng.new(SEED)
      two = Game.dug Rng.new(SEED + 1)

      expect(ids(one).min).to eq 1
      expect(ids(two).min).to eq 1
    end
  end

  describe "a run written out and read back" do
    it "keeps every id" do
      game = Game.dug Rng.new(SEED)
      again = Game.from_json game.to_json

      expect(named again).to eq named(game)
    end

    it "carries on from where the counter stood" do
      game = Game.dug Rng.new(SEED)
      before = game.minted
      again = Game.from_json game.to_json

      expect(again.minted).to eq before
      expect(again.next_id).to eq before + 1
    end
  end

  describe "a save written before ids existed" do
    it "loads and comes out with ids" do
      game = Game.dug Rng.new(SEED)
      old = Game.from_json stripped(game)
      found = ids old

      expect(found.includes?(0)).to be_false
      expect(found.uniq.size).to eq found.size
    end

    it "leaves the counter above every id it handed out" do
      game = Game.dug Rng.new(SEED)
      old = Game.from_json stripped(game)

      expect(old.minted).to eq ids(old).max
    end
  end

  describe "#item" do
    it "answers what wears the id" do
      game = Game.dug Rng.new(SEED)
      _letter, carried = game.player.inventory.items.first

      expect(game.item(carried.id)).to be carried
    end

    it "answers nothing for an id nothing wears" do
      game = Game.dug Rng.new(SEED)

      expect(game.item(0)).to be_nil
      expect(game.item(game.minted + 1)).to be_nil
    end

    it "finds a pile lying on the floor" do
      game = Game.dug Rng.new(SEED)
      purse = Item.new Kind::Gold, count: 7
      purse.enrol game.next_id
      game.floor.drop 1, 1, purse

      expect(game.item(purse.id).try &.count).to eq 7
    end
  end

  describe "#monster" do
    it "answers which creature wears the id" do
      game = Game.dug Rng.new(SEED)
      creature = game.floor.monsters.values.first

      expect(game.monster(creature.id)).to be creature
    end

    it "answers nothing for an id no creature wears" do
      game = Game.dug Rng.new(SEED)
      _letter, carried = game.player.inventory.items.first

      expect(game.monster(carried.id)).to be_nil
    end
  end

  # `Game#item` and `Game#monster` answer out of an index rather than by
  # walking the run. An index that is out of step would answer with something
  # that has been drunk, merged away or killed, which is worse than the walk
  # it replaces. Every example here moves something and then asks.
  describe "the index behind #item and #monster" do
    alias Action = Roguelike::Action

    # A run with a potion lying under the character's feet.
    def stocked : Game
      game = Game.dug Rng.new(SEED)
      potion = Item.new Kind::HealingPotion
      potion.enrol game.next_id
      game.floor.drop game.player.x, game.player.y, potion
      game
    end

    it "finds an item in the pack after it was picked up" do
      game = stocked
      potion = game.floor.items(game.player.x, game.player.y).first

      expect(game.item potion.id).to be potion
      game.perform Action::PickUp.new(potion.id)

      expect(game.item(potion.id)).to be potion
      expect(game.floor.items(game.player.x, game.player.y)).to be_empty
    end

    it "finds an item on the floor after it was dropped" do
      game = Game.dug Rng.new(SEED)
      carried = game.player.inventory.items.map(&.[1]).find! &.kind.spike?
      game.perform Action::Drop.new(carried.id)

      expect(game.item carried.id).to be carried
      expect(game.floor.items(game.player.x, game.player.y)).to contain carried
    end

    it "answers nothing for a potion that has been drunk" do
      game = stocked
      potion = game.floor.items(game.player.x, game.player.y).first
      game.perform Action::PickUp.new(potion.id)
      game.perform Action::Quaff.new(potion.id)

      expect(game.item potion.id).to be_nil
    end

    it "answers nothing for a pile that was merged away" do
      game = Game.dug Rng.new(SEED)
      letter = game.player.inventory.add Item.new(Kind::Arrow, count: 3)
      kept = letter ? game.player.inventory[letter] : nil
      raise "no arrows" unless kept
      kept.enrol game.next_id

      more = Item.new Kind::Arrow, count: 2
      more.enrol game.next_id
      game.floor.drop game.player.x, game.player.y, more
      game.perform Action::PickUp.new(more.id)

      expect(game.item more.id).to be_nil
      expect(game.item(kept.id).try &.count).to eq 5
    end

    it "answers nothing for a creature that has been killed" do
      game = Game.dug Rng.new(SEED)
      creature = game.floor.monsters.values.first
      game.floor.remove creature.x, creature.y
      game.wait

      expect(game.monster creature.id).to be_nil
    end

    it "gives out the same ids however many times it was asked" do
      one = Game.dug Rng.new(SEED)
      two = Game.dug Rng.new(SEED)
      ids(two).each { |id| two.item id }
      two.wait
      ids(two).each { |id| two.monster id }

      expect(named two).to eq named(one)
    end
  end

  describe "a pile that splits" do
    # The part that stays in the pack keeps the id. The character goes on
    # naming their arrows. A bot that recorded which pile it fires from must
    # not have to record it again after every shot.
    it "leaves the id on what is left in the pack" do
      game = Game.start Rng.new(SEED)
      letter = game.player.inventory.add Item.new(Kind::Arrow, count: 12)
      raise "no letter for the arrows" unless letter
      game.enrol

      quiver = game.player.inventory[letter]
      raise "no arrows" unless quiver
      before = quiver.id

      taken = game.player.inventory.take letter, 2, game.next_id
      left = game.player.inventory[letter]

      expect(left.try &.id).to eq before
      expect(left.try &.count).to eq 10
      expect(taken.try &.count).to eq 2
      expect(taken.try &.id).to_not eq before
    end

    # A pile put into another is gone, and so is its id. What is left is the
    # pile that was already there.
    it "keeps the receiving pile's id on a merge" do
      one = Item.new Kind::Arrow, count: 5
      two = Item.new Kind::Arrow, count: 3
      one.enrol 4
      two.enrol 9

      expect(one.merge(two).id).to eq 4
      expect(one.merge(two).count).to eq 8
    end

    # `Item#with_count` is how a letter is counted as one stack and how a
    # memory of a pile is taken. Neither makes a new pile.
    it "keeps the id when a pile is only counted differently" do
      stack = Item.new Kind::Arrow, count: 12
      stack.enrol 4

      expect(stack.with_count(3).id).to eq 4
      expect(stack.copy.id).to eq 4
    end
  end

  describe "Item#enrol" do
    it "takes an id once" do
      item = Item.new Kind::Arrow

      expect(item.enrol 4).to be_true
      expect(item.enrol 9).to be_false
      expect(item.id).to eq 4
    end

    it "refuses zero, which is the way of saying there is no id" do
      item = Item.new Kind::Arrow

      expect(item.enrol 0).to be_false
      expect(item.id).to eq 0
    end
  end
end
