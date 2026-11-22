require "../spec_helper"

# Each item on a square is remembered on its own, with its own regard.
Spectator.describe "remembering items one by one" do
  alias Action = Roguelike::Action
  alias Event = Roguelike::Event
  alias Explore = Roguelike::Explore
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Knowledge = Roguelike::Knowledge
  alias Memory = Roguelike::Memory
  alias Regard = Roguelike::Regard

  # A lit room 3 rows by 40 columns, with nothing in it.
  def hall : Floor
    lines = ["#" * 42] + Array.new(3) { "#" + "." * 40 + "#" } + ["#" * 42]
    Playing.daylight Floor.parse("hall", lines)
  end

  # An item of *kind* with the id *id*.
  def item(kind : Kind, id : Int32, count : Int32 = 1) : Item
    found = Item.new kind, count: count
    found.enroll id
    found
  end

  # How well *knowledge* made out the item with the id *id* at *x*, *y*.
  def regard(knowledge : Knowledge, x : Int32, y : Int32, id : Int32) : Regard?
    knowledge[x, y].try &.regard_of(id)
  end

  let(floor) { hall }
  subject(knowledge) { Knowledge.new floor.id }

  describe "a look" do
    it "makes out every item on the square as its kind from a distance" do
      floor.drop 5, 2, item(Kind::Spear, 1)
      floor.drop 5, 2, item(Kind::Bread, 2)
      floor.drop 5, 2, item(Kind::HealingPotion, 3)

      knowledge.see floor, 5, 2, 1, Regard::Kind

      expect(knowledge[5, 2].try &.items.map(&.regard)).to eq [Regard::Kind] * 3
    end

    it "makes out every item on the square in full from close by" do
      floor.drop 5, 2, item(Kind::Spear, 1)
      floor.drop 5, 2, item(Kind::Bread, 2)

      knowledge.see floor, 5, 2, 1, Regard::Everything

      expect(knowledge[5, 2].try &.items.map(&.regard)).to eq [Regard::Everything] * 2
    end

    it "raises one item without touching the others" do
      floor.drop 5, 2, item(Kind::Spear, 1)
      knowledge.see floor, 5, 2, 1, Regard::Everything
      floor.drop 5, 2, item(Kind::HealingPotion, 2)
      knowledge.see floor, 5, 2, 2, Regard::Kind

      expect(regard knowledge, 5, 2, 1).to eq Regard::Everything
      expect(regard knowledge, 5, 2, 2).to eq Regard::Kind

      knowledge.see floor, 5, 2, 3, Regard::Everything

      expect(regard knowledge, 5, 2, 1).to eq Regard::Everything
      expect(regard knowledge, 5, 2, 2).to eq Regard::Everything
    end

    it "keeps the item and its full regard when it rots into a putrid mass" do
      bread = item(Kind::Bread, 2)
      floor.drop 5, 2, item(Kind::Spear, 1)
      floor.drop 5, 2, bread
      knowledge.see floor, 5, 2, 1, Regard::Everything

      floor.take 5, 2, bread
      floor.drop 5, 2, Game.putrid_mass(bread)
      knowledge.see floor, 5, 2, 2, Regard::Kind

      memory = knowledge[5, 2]
      raise "the square was not remembered" unless memory

      expect(memory[2].try &.item.kind).to eq Kind::PutridMass
      expect(memory.items.map(&.regard)).to eq [Regard::Everything] * 2
      expect(memory.unread?).to be_false
    end

    it "lets in a new item at the look's regard and drops nothing else" do
      floor.drop 5, 2, item(Kind::Spear, 1)
      knowledge.see floor, 5, 2, 1, Regard::Everything

      floor.items(5, 2).unshift item(Kind::Dagger, 2)
      floor.drop 5, 2, item(Kind::HealingPotion, 3)
      knowledge.see floor, 5, 2, 2, Regard::Kind

      memory = knowledge[5, 2]
      raise "the square was not remembered" unless memory

      expect(memory.items.map(&.id)).to eq [2, 1, 3]
      expect(memory.regard_of 1).to eq Regard::Everything
      expect(memory.regard_of 2).to eq Regard::Kind
      expect(memory.regard_of 3).to eq Regard::Kind
      expect(memory[2].try &.turn).to eq 2
    end

    it "forgets an item that is no longer there" do
      spear = item(Kind::Spear, 1)
      floor.drop 5, 2, spear
      floor.drop 5, 2, item(Kind::Bread, 2)
      knowledge.see floor, 5, 2, 1, Regard::Everything

      floor.take 5, 2, spear
      knowledge.see floor, 5, 2, 2, Regard::Kind

      expect(knowledge[5, 2].try &.items.map(&.id)).to eq [2]
    end

    it "forgets the pile when the square is bare" do
      spear = item(Kind::Spear, 1)
      floor.drop 5, 2, spear
      knowledge.see floor, 5, 2, 1
      floor.take 5, 2, spear
      knowledge.see floor, 5, 2, 2

      expect(knowledge[5, 2].try &.items?).to be_false
    end

    # A potion swapped in at the bottom of a pile read up close. The pile's
    # top is the same, and from across the hall the character sees a potion
    # and nothing about which one.
    it "does not give away an item changed beneath the top from a distance" do
      lore = Roguelike::Lore.new
      bottom = item(Kind::HealingPotion, 1)
      floor.drop 5, 2, bottom
      floor.drop 5, 2, item(Kind::Spear, 2)
      knowledge.see floor, 5, 2, 1, Regard::Everything

      floor.take 5, 2, bottom
      floor.items(5, 2).unshift item(Kind::HastePotion, 3)
      knowledge.see floor, 5, 2, 2, Regard::Kind

      memory = knowledge[5, 2]
      raise "the square was not remembered" unless memory

      fresh = memory[3]
      raise "the new potion was not remembered" unless fresh

      expect(fresh.regard).to eq Regard::Kind
      expect(lore.name fresh.item, regard: fresh.regard).to eq "a potion"
      expect(memory.regard_of 2).to eq Regard::Everything
    end

    it "keeps what only a close look shows when the item changes out of reach" do
      spear = Item.new Kind::Spear, enchantment: 2
      spear.enroll 1
      floor.drop 5, 2, spear
      knowledge.see floor, 5, 2, 1, Regard::Everything

      spear.crack
      knowledge.see floor, 5, 2, 2, Regard::Kind

      kept = knowledge[5, 2].try &.[](1).try &.item
      expect(kept.try &.enchantment).to eq 2
      expect(kept.try &.condition).to eq Roguelike::Condition::Plain
    end
  end

  describe "the revision" do
    it "moves on each change to the items remembered and not on a refresh" do
      spear = item(Kind::Spear, 1)
      bread = item(Kind::Bread, 2)
      floor.drop 5, 2, spear
      knowledge.see floor, 5, 2, 1, Regard::Kind
      counted = ->(look : Regard) do
        before = knowledge.revision
        knowledge.see floor, 5, 2, 9, look
        knowledge.revision - before
      end

      expect(counted.call Regard::Kind).to eq 0
      expect(counted.call Regard::Everything).to eq 1
      expect(counted.call Regard::Kind).to eq 0

      floor.drop 5, 2, bread
      expect(counted.call Regard::Kind).to eq 1

      floor.take 5, 2, bread
      floor.drop 5, 2, Game.putrid_mass(bread)
      expect(counted.call Regard::Kind).to eq 1

      floor.take 5, 2, spear
      expect(counted.call Regard::Kind).to eq 1
      expect(counted.call Regard::Kind).to eq 0
    end
  end

  describe Roguelike::Explore do
    it "lists a square while any item worth reading on it is unread" do
      floor.drop 5, 2, item(Kind::Spear, 1)
      floor.drop 9, 2, item(Kind::Spear, 2)
      floor.drop 9, 2, item(Kind::HealingPotion, 3)
      floor.drop 13, 2, item(Kind::Gold, 4, 20)
      floor.drop 13, 2, item(Kind::Torch, 5)
      floor.drop 17, 2, item(Kind::PutridMass, 6)
      knowledge.see floor, 5, 2, 1, Regard::Everything
      knowledge.see floor, 9, 2, 1, Regard::Everything
      [{9, 2}, {13, 2}, {17, 2}].each { |spot| knowledge.see floor, spot[0], spot[1], 1, Regard::Kind }
      floor.drop 9, 2, item(Kind::Dagger, 8)
      knowledge.see floor, 9, 2, 2, Regard::Kind

      expect(Explore.unread knowledge).to eq [{9, 2}]
    end
  end

  describe "the item a map draws" do
    it "is the one whose class comes first, whatever the order of the pile" do
      mass = item(Kind::PutridMass, 1)
      spear = item(Kind::Spear, 2)
      potion = item(Kind::HealingPotion, 3)

      expect(Memory.shown [spear, mass]).to eq spear
      expect(Memory.shown [mass, spear]).to eq spear
      expect(Memory.shown [mass, spear, potion]).to eq potion
      expect(Memory.shown [] of Item).to be_nil
    end

    it "is the one with the lowest id among items of one class" do
      first = item(Kind::Spear, 4)
      second = item(Kind::Dagger, 9)

      expect(Memory.shown([second, first]).try &.id).to eq 4
    end

    it "is drawn on the map for a remembered square" do
      floor.drop 5, 2, item(Kind::Spear, 1)
      floor.drop 5, 2, item(Kind::PutridMass, 2)
      knowledge.see floor, 5, 2, 1

      expect(knowledge[5, 2].try &.shown.try &.kind).to eq Kind::Spear
    end
  end

  describe "a band's knowledge" do
    it "is its own, and a member's copy makes things out on its own" do
      band = Roguelike::Band.new "band-one"
      floor.drop 5, 2, item(Kind::Spear, 1)
      held = band.knowledge floor.id
      held.see floor, 5, 2, 1, Regard::Kind
      knowledge.see floor, 5, 2, 1, Regard::Everything

      member = held.copy
      member.see floor, 5, 2, 2, Regard::Everything

      expect(regard held, 5, 2, 1).to eq Regard::Kind
      expect(regard member, 5, 2, 1).to eq Regard::Everything
      expect(regard knowledge, 5, 2, 1).to eq Regard::Everything
    end
  end

  describe "a save" do
    it "round-trips each item's regard and turn" do
      floor.drop 5, 2, item(Kind::Spear, 1)
      knowledge.see floor, 5, 2, 1, Regard::Everything
      floor.drop 5, 2, item(Kind::Bread, 2)
      knowledge.see floor, 5, 2, 4, Regard::Kind

      again = Knowledge.from_json knowledge.to_json

      expect(again).to eq knowledge
      expect(again[5, 2].try &.items.map { |one| {one.id, one.regard, one.turn} })
        .to eq [{1, Regard::Everything, 4}, {2, Regard::Kind, 4}]
    end

    # What a build before items were remembered one by one wrote for a pile
    # at 1,1 seen from a distance: a dagger under a cap, one regard for both.
    OLD_PILE = <<-JSON
      {"floor":"room","memories":{"1,1":{"terrain":"stone_floor","item":{"id":7,
      "kind":"cap","enchantment":0,"condition":"plain","blessing":"uncursed",
      "blessing_known":false,"count":1,"lit":false,"handling":0},"turn":3,
      "regard":"kind","under":[{"id":6,"kind":"dagger","enchantment":0,
      "condition":"plain","blessing":"uncursed","blessing_known":false,"count":1,
      "lit":false,"handling":0}]}},"sightings":{},"openings":[]}
      JSON

    it "loads an old pile as one memory per item with the square's regard" do
      again = Knowledge.from_json OLD_PILE
      memory = again[1, 1]
      raise "the square was not loaded" unless memory

      expect(memory.items.map { |one| {one.id, one.item.kind, one.regard, one.turn} })
        .to eq [{6, Kind::Dagger, Regard::Kind, 3}, {7, Kind::Cap, Regard::Kind, 3}]
      expect(again.to_json).not_to contain %("under")
      expect(Knowledge.from_json(again.to_json)).to eq again
    end
  end

  # Paul's floor: a pile read up close, then a loaf on it rots into a
  # putrid mass while the character is across the room.
  describe "explore" do
    def walk(game : Game, limit : Int32) : {Array(Halt), Array({Int32, Int32})}
      halts = [] of Halt
      squares = [game.player.at]
      limit.times do
        break unless game.explorable?

        game.perform Action::Explore.new
        game.look
        game.events.each { |event| halts << event.halt if event.is_a?(Event::Stopped) }
        break unless halts.empty?

        squares << game.player.at
      end
      {halts, squares}
    end

    it "does not walk back to re-read a pile whose loaf rotted" do
      game = Playing.field 41, 5
      loaf = item(Kind::Bread, 2)
      game.floor.drop 3, 2, item(Kind::Spear, 1)
      game.floor.drop 3, 2, loaf
      game.floor.drop 3, 2, item(Kind::Dagger, 3)
      game.player.move_to 5, 2
      game.look
      expect(game.knowledge[3, 2].try &.unread?).to be_false

      game.player.move_to 37, 2
      game.look
      game.floor.take 3, 2, loaf
      game.floor.drop 3, 2, Game.putrid_mass(loaf)
      game.look

      memory = game.knowledge[3, 2]
      raise "the pile was not remembered" unless memory

      expect(memory[2].try &.item.kind).to eq Kind::PutridMass
      expect(memory.items.all?(&.regard.everything?)).to be_true
      expect(Explore.unread game.knowledge).to be_empty

      _halts, squares = walk game, 40
      expect(squares.min_by &.[0]).to eq({37, 2})
    end
  end
end
