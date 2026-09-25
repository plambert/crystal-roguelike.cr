require "../spec_helper"

Spectator.describe Roguelike::Inventory do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item

  subject(bag) { described_class.new }

  describe "#add" do
    it "hands out the first letter" do
      expect(bag.add(Item.new(Kind::Dagger))).to eq 'a'
    end

    it "hands out the next letter after that" do
      bag.add Item.new(Kind::Dagger)

      expect(bag.add(Item.new(Kind::LongSword))).to eq 'b'
    end

    it "joins a stack already carried rather than taking a letter" do
      bag.add Item.new(Kind::Arrow, count: 5)

      expect(bag.add(Item.new(Kind::Arrow, count: 7))).to eq 'a'
      expect(bag.size).to eq 1
      expect(bag['a'].try &.count).to eq 12
    end

    it "gives a different stack its own letter" do
      bag.add Item.new(Kind::Arrow, count: 5)
      bag.add Item.new(Kind::Arrow, 1, count: 5)

      expect(bag.size).to eq 2
    end

    it "answers nothing once every letter is taken" do
      Roguelike::Inventory::LETTERS.size.times { bag.add Item.new(Kind::LongSword) }

      expect(bag.full?).to be_true
      expect(bag.add(Item.new(Kind::Dagger))).to be_nil
    end
  end

  # Dropping b does not move what is under c.
  describe "the letters" do
    it "keeps a letter for as long as the item is carried" do
      bag.add Item.new(Kind::Dagger)
      bag.add Item.new(Kind::LongSword)
      bag.add Item.new(Kind::Mace)

      bag.remove 'b'

      expect(bag['a'].try &.kind).to eq Kind::Dagger
      expect(bag['c'].try &.kind).to eq Kind::Mace
    end

    it "gives a new item the lowest free letter" do
      bag.add Item.new(Kind::Dagger)
      bag.add Item.new(Kind::LongSword)
      bag.add Item.new(Kind::Mace)
      bag.remove 'b'

      expect(bag.add(Item.new(Kind::Spear))).to eq 'b'
      expect(bag['c'].try &.kind).to eq Kind::Mace
    end

    it "runs lower case before upper case" do
      letters = Roguelike::Inventory::LETTERS

      expect(letters.first).to eq 'a'
      expect(letters[25]).to eq 'z'
      expect(letters[26]).to eq 'A'
      expect(letters.size).to eq 52
    end
  end

  describe "#each" do
    it "walks the entries in letter order" do
      bag.add Item.new(Kind::Dagger)
      bag.add Item.new(Kind::LongSword)
      bag.remove 'a'
      bag.add Item.new(Kind::Mace)

      expect(bag.entries.map(&.[0])).to eq ['a', 'b']
      expect(bag.entries.map(&.[1].kind)).to eq [Kind::Mace, Kind::LongSword]
    end
  end

  describe "#take" do
    it "takes part of a stack and leaves the rest" do
      bag.add Item.new(Kind::Arrow, count: 12)

      taken = bag.take 'a', 5, 7

      expect(taken.try &.count).to eq 5
      expect(bag['a'].try &.count).to eq 7
    end

    it "takes the whole entry when the count reaches it" do
      bag.add Item.new(Kind::Arrow, count: 12)

      expect(bag.take('a', 12, 7).try &.count).to eq 12
      expect(bag.has?('a')).to be_false
    end

    it "takes nothing for a letter nothing is under" do
      expect(bag.take('z', 1, 7)).to be_nil
    end

    it "leaves the id on the part that stays and gives the rest the new one" do
      stack = Item.new Kind::Arrow, count: 12
      stack.enroll 4
      bag.add stack

      taken = bag.take 'a', 2, 9

      expect(taken.try &.id).to eq 9
      expect(bag['a'].try &.id).to eq 4
    end

    it "hands the whole pile over with the id it wore" do
      stack = Item.new Kind::Arrow, count: 12
      stack.enroll 4
      bag.add stack

      expect(bag.take('a', 12, 9).try &.id).to eq 4
    end
  end

  describe "#weight" do
    it "adds up everything carried" do
      bag.add Item.new(Kind::Arrow, count: 10)
      bag.add Item.new(Kind::LongSword)

      expect(bag.weight)
        .to eq Kind::Arrow.facts.weight * 10 + Kind::LongSword.facts.weight
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      bag.add Item.new(Kind::Arrow, count: 7)
      bag.add Item.new(Kind::LongSword, 1)

      again = described_class.from_json bag.to_json

      expect(again.entries).to eq bag.entries
    end
  end
end

Spectator.describe Roguelike::Inventory do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Blessing = Roguelike::Blessing

  describe "a letter holding several things" do
    # The character cannot see a hidden curse, so two letters reading
    # "arrow" would say something differs without saying what.
    it "puts things that look the same under one letter" do
      pack = described_class.new
      pack.add Item.new(Kind::Arrow, count: 12)
      pack.add Item.new(Kind::Arrow, count: 3, blessing: Blessing::Cursed)

      expect(pack.size).to eq 1
      expect(pack.count 'a').to eq 15
      expect(pack.all('a').size).to eq 2
    end

    it "keeps things that look different apart" do
      pack = described_class.new
      pack.add Item.new(Kind::Arrow, count: 12)
      pack.add Item.new(Kind::Arrow, count: 3, blessing: Blessing::Cursed,
        blessing_known: true)

      expect(pack.size).to eq 2
    end

    it "gives a kind that does not stack a letter to itself" do
      pack = described_class.new
      pack.add Item.new(Kind::LongSword)
      pack.add Item.new(Kind::LongSword)

      expect(pack.size).to eq 2
    end

    it "answers the front of the letter" do
      pack = described_class.new
      first = Item.new Kind::Arrow, count: 12
      second = Item.new Kind::Arrow, count: 3, blessing: Blessing::Cursed
      pack.add first
      pack.add second

      expect(pack['a']).to be first
    end

    it "takes from the front" do
      pack = described_class.new
      pack.add Item.new(Kind::Arrow, count: 2)
      pack.add Item.new(Kind::Arrow, count: 3, blessing: Blessing::Cursed)

      expect(pack.take('a', 2, 7).try &.blessing).to eq Blessing::Uncursed
      expect(pack.take('a', 1, 8).try &.blessing).to eq Blessing::Cursed
      expect(pack.count 'a').to eq 2
    end

    it "frees the letter once nothing is under it" do
      pack = described_class.new
      pack.add Item.new(Kind::Arrow, count: 2)
      pack.take 'a', 5, 7

      expect(pack.has? 'a').to be_false
    end

    it "joins a stack it is the same thing as" do
      pack = described_class.new
      pack.add Item.new(Kind::Arrow, count: 12)
      pack.add Item.new(Kind::Arrow, count: 3)

      expect(pack.all('a').size).to eq 1
      expect(pack.count 'a').to eq 15
    end

    it "keeps the larger handling when two stacks join" do
      pack = described_class.new
      old = Item.new Kind::Arrow, count: 12
      old.handle 37
      pack.add old
      pack.add Item.new(Kind::Arrow, count: 3)

      expect(pack.all('a').first.handling).to eq 37
    end

    it "walks every item rather than every letter" do
      pack = described_class.new
      pack.add Item.new(Kind::Arrow, count: 12)
      pack.add Item.new(Kind::Arrow, count: 3, blessing: Blessing::Cursed)

      expect(pack.entries.size).to eq 1
      expect(pack.items.size).to eq 2
    end
  end

  describe "#relocate" do
    it "moves one thing to a letter of its own" do
      pack = described_class.new
      plain = Item.new Kind::Arrow, count: 12
      cursed = Item.new Kind::Arrow, count: 3, blessing: Blessing::Cursed
      pack.add plain
      pack.add cursed
      cursed.reveal_blessing

      expect(pack.relocate 'a', cursed).to eq 'b'
      expect(pack.all('a')).to eq [plain]
      expect(pack.all('b')).to eq [cursed]
    end

    it "leaves a letter holding one thing where it is" do
      pack = described_class.new
      only = Item.new Kind::Arrow, count: 12
      pack.add only

      expect(pack.relocate 'a', only).to eq 'a'
    end

    it "answers nothing with every letter taken" do
      pack = described_class.new
      plain = Item.new Kind::Arrow, count: 12
      cursed = Item.new Kind::Arrow, count: 3, blessing: Blessing::Cursed
      pack.add plain
      pack.add cursed
      cursed.reveal_blessing

      Roguelike::Inventory::LETTERS.each do |letter|
        next if letter == 'a'
        pack.slots[letter] = Roguelike::Inventory::Stack.of Item.new(Kind::Dagger)
      end

      expect(pack.relocate 'a', cursed).to be_nil
      expect(pack.all('a').size).to eq 2
    end
  end

  describe "#strip" do
    it "takes everything but what it is told to keep" do
      pack = described_class.new
      plain = Item.new Kind::Arrow, count: 12
      cursed = Item.new Kind::Arrow, count: 3, blessing: Blessing::Cursed
      pack.add plain
      pack.add cursed

      expect(pack.strip 'a', cursed).to eq [plain]
      expect(pack.all('a')).to eq [cursed]
    end
  end

  describe "a save file" do
    it "comes back under the same letters" do
      pack = described_class.new
      pack.add Item.new(Kind::Arrow, count: 12)
      pack.add Item.new(Kind::Arrow, count: 3, blessing: Blessing::Cursed)
      pack.add Item.new(Kind::LongSword)

      again = described_class.from_json pack.to_json

      expect(again).to eq pack
      expect(again.all('a').size).to eq 2
    end

    # A save written before a letter held a list has one item per letter.
    it "reads the older form" do
      older = %([{"letter":"a","item":{"kind":"Dagger","enchantment":0,) +
              %("condition":"Plain","blessing":"Uncursed",) +
              %("blessing_known":false,"count":1,"charges":null,"lit":false}}])
      pack = described_class.from_json older

      expect(pack.size).to eq 1
      expect(pack['a'].try &.kind).to eq Kind::Dagger
    end
  end
end
