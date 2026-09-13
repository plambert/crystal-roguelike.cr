require "json"
require "./item"

module Roguelike
  # What a character carries, one letter at a time.
  #
  # Every entry has a letter. A person types the letter to choose the item.
  # An item keeps its letter for as long as it is carried, so dropping `b`
  # does not move what is under `c`.
  #
  # A new item takes the lowest free letter. Lower case runs first, then upper
  # case, which is what every roguelike does and what `LETTERS` spells out.
  class Inventory
    # The letters an entry can take, in the order they are handed out.
    LETTERS = ('a'..'z').to_a + ('A'..'Z').to_a

    # What is carried, by letter.
    getter slots : Hash(Char, Item)

    def initialize(@slots : Hash(Char, Item) = {} of Char => Item)
    end

    # How many entries there are. A stack of twelve arrows is one.
    def size : Int32
      @slots.size
    end

    # Whether nothing is carried.
    def empty? : Bool
      @slots.empty?
    end

    # Whether every letter is taken.
    def full? : Bool
      @slots.size >= LETTERS.size
    end

    # The item under *letter*, or `nil` for a letter nothing is under.
    def [](letter : Char) : Item?
      @slots[letter]?
    end

    # Whether anything is under *letter*.
    def has?(letter : Char) : Bool
      @slots.has_key? letter
    end

    # Every entry, by letter, in the order the letters are handed out.
    def each(& : Char, Item ->) : Nil
      LETTERS.each do |letter|
        item = @slots[letter]?
        yield letter, item if item
      end
    end

    # :ditto:, as an array.
    def entries : Array({Char, Item})
      found = [] of {Char, Item}
      each { |letter, item| found << {letter, item} }
      found
    end

    # Every entry whose item answers the block.
    def select(& : Item -> Bool) : Array({Char, Item})
      entries.select { |_letter, item| yield item }
    end

    # Puts *item* in. Answers the letter it went under, or `nil` when every
    # letter is taken.
    #
    # A stack joins one already carried rather than taking a letter of its
    # own. Everything about the two has to match for that, which
    # `Item#stacks_with?` decides.
    def add(item : Item) : Char?
      found = entries.find { |_letter, held| held.stacks_with? item }
      if found
        letter = found[0]
        @slots[letter] = found[1].add item.count
        return letter
      end

      letter = free
      return unless letter

      @slots[letter] = item
      letter
    end

    # Takes out what is under *letter*. Answers it, or `nil` for a letter
    # nothing is under.
    def remove(letter : Char) : Item?
      @slots.delete letter
    end

    # Takes *count* of what is under *letter*, leaving the rest.
    #
    # Answers what came out, or `nil` when there is nothing under the letter.
    # A count at or above what is there takes the whole entry and frees the
    # letter.
    def take(letter : Char, count : Int32) : Item?
      held = @slots[letter]?
      return unless held
      return remove letter if count >= held.count
      return if count <= 0

      @slots[letter] = held.add -count
      held.with_count count
    end

    # The lowest letter nothing is under, or `nil` when every one is taken.
    def free : Char?
      LETTERS.find { |letter| !@slots.has_key? letter }
    end

    # What everything carried weighs.
    def weight : Int32
      @slots.each_value.sum &.weight
    end

    def to_s(io : IO) : Nil
      io << "Inventory(" << @slots.size << " entries)"
    end

    # One entry in a save file.
    #
    # A JSON object key has to be a string and a letter is a `Char`, so the
    # stored form is a list of pairs rather than an object.
    struct Slot
      include JSON::Serializable

      getter letter : String
      getter item : Item

      def initialize(@letter : String, @item : Item)
      end
    end

    # The stored form of this inventory.
    def stored : Array(Slot)
      entries.map { |letter, item| Slot.new letter.to_s, item }
    end

    def self.new(pull : JSON::PullParser) : Inventory
      slots = {} of Char => Item

      Array(Slot).new(pull).each do |slot|
        letter = slot.letter[0]?
        next unless letter

        slots[letter] = slot.item
      end

      new slots
    end

    def to_json(json : JSON::Builder) : Nil
      stored.to_json json
    end

    def ==(other : Inventory) : Bool
      @slots == other.slots
    end
  end
end
