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

      taken = bag.take 'a', 5

      expect(taken.try &.count).to eq 5
      expect(bag['a'].try &.count).to eq 7
    end

    it "takes the whole entry when the count reaches it" do
      bag.add Item.new(Kind::Arrow, count: 12)

      expect(bag.take('a', 12).try &.count).to eq 12
      expect(bag.has?('a')).to be_false
    end

    it "takes nothing for a letter nothing is under" do
      expect(bag.take('z', 1)).to be_nil
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
