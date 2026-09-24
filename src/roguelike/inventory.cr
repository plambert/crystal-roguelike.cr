require "json"
require "./item"

module Roguelike
  # What a character carries, one letter at a time.
  #
  # Every letter has a list rather than one item. A person types the letter to
  # choose what is under it, and what is under it is everything that looks the
  # same to them: twelve arrows picked up in the first room and three more
  # found in the third are one row reading "15 arrows". `Item#looks_like?`
  # decides that, and it compares only what the character can see.
  #
  # Inside the letter the items stay apart. Two of those arrows may be cursed
  # and the rest not, and the character finds that out one stack at a time.
  # `Item#stacks_with?` decides which of them are the same thing, the hidden
  # blessing included.
  #
  # The list is in the order it was picked up, and everything that takes one
  # item takes the first. A person firing a quiver empties the oldest arrows
  # first.
  #
  # An item keeps its letter for as long as it is carried, so dropping `b`
  # does not move what is under `c`. A new item takes the lowest free letter.
  # Lower case runs first, then upper case, which is what every roguelike does
  # and what `LETTERS` spells out.
  class Inventory
    # The letters an entry can take, in the order they are handed out.
    LETTERS = ('a'..'z').to_a + ('A'..'Z').to_a

    # Everything under one letter.
    #
    # The order is the order it was picked up. Nothing here reorders it.
    class Stack
      # What is under the letter, oldest first.
      getter items : Array(Item)

      def initialize(@items : Array(Item) = [] of Item)
      end

      # One item under a letter of its own.
      def self.of(item : Item) : Stack
        new [item]
      end

      # The item everything that takes one takes.
      def first : Item?
        @items.first?
      end

      # How many there are across the whole letter.
      def count : Int32
        @items.sum &.count
      end

      # How many separate things are under the letter.
      def size : Int32
        @items.size
      end

      # Whether there is nothing under the letter.
      def empty? : Bool
        @items.empty?
      end

      # Whether *item* belongs under this letter.
      def holds?(item : Item) : Bool
        found = first
        found ? found.looks_like?(item) : false
      end

      # Puts *item* in.
      #
      # It joins whichever of the items here it is the same thing as, and
      # goes on the end when it is the same thing as none of them.
      def add(item : Item) : Nil
        found = @items.index &.stacks_with?(item)
        if found
          @items[found] = @items[found].merge item
        else
          @items << item
        end
      end

      # Takes *count* off the front. The part that leaves is given the id
      # *id*.
      #
      # Answers what came out, or `nil` when there is nothing here.
      #
      # A pile split in two keeps its id on the part that stays in the pack.
      # That is the pile the character goes on naming. Two arrows off a stack
      # of twelve leave ten arrows that are still the same arrows. The two
      # that left are a separate pile from here on, under *id*.
      #
      # A count that reaches the whole front stack is not a split. The pile
      # moves as it stands, under the id it already had, and *id* is not
      # used. An id need only be unique and follow from the seed, so a gap in
      # the numbering costs nothing.
      def take(count : Int32, id : Int32) : Item?
        held = first
        return unless held
        return if count <= 0

        if count >= held.count
          @items.shift
          return held
        end

        @items[0] = held.add -count
        held.with_count count, id
      end

      # Takes *item* out by identity. Answers whether it was here.
      def pull(item : Item) : Bool
        found = @items.index &.same?(item)
        return false unless found

        @items.delete_at found
        true
      end

      # Everything but *keep*, taken out.
      def strip(keep : Item) : Array(Item)
        gone = @items.reject &.same?(keep)
        @items.select! &.same?(keep)
        gone
      end

      # What everything under the letter weighs.
      def weight : Int32
        @items.sum &.weight
      end

      def ==(other : Stack) : Bool
        @items == other.items
      end

      def to_s(io : IO) : Nil
        io << "Stack(" << @items.size << ')'
      end
    end

    # What is carried, by letter.
    getter slots : Hash(Char, Stack)

    def initialize(@slots : Hash(Char, Stack) = {} of Char => Stack)
    end

    # How many letters are taken. A stack of twelve arrows is one.
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

    # The item under *letter* that an action takes, or `nil` for a letter
    # nothing is under.
    #
    # The first of the list. Everything that takes one item takes this.
    def [](letter : Char) : Item?
      @slots[letter]?.try &.first
    end

    # Everything under *letter*, oldest first.
    def all(letter : Char) : Array(Item)
      @slots[letter]?.try(&.items) || [] of Item
    end

    # How many there are under *letter*, across everything it holds.
    #
    # This is what a readout prints. Fifteen arrows under one letter read
    # "15 arrows" whether they are one stack or four.
    def count(letter : Char) : Int32
      @slots[letter]?.try(&.count) || 0
    end

    # Whether anything is under *letter*.
    def has?(letter : Char) : Bool
      @slots.has_key? letter
    end

    # Every letter and the item an action would take, in the order the
    # letters are handed out.
    def each(& : Char, Item ->) : Nil
      LETTERS.each do |letter|
        item = self[letter]
        yield letter, item if item
      end
    end

    # Every item carried, letter by letter and oldest first.
    #
    # `#each` gives one item a letter. This gives all of them, which is what
    # anything walking the whole pack wants.
    def each_item(& : Char, Item ->) : Nil
      LETTERS.each do |letter|
        stack = @slots[letter]?
        next unless stack

        stack.items.each { |item| yield letter, item }
      end
    end

    # :ditto:, as an array.
    def entries : Array({Char, Item})
      found = [] of {Char, Item}
      each { |letter, item| found << {letter, item} }
      found
    end

    # Every item carried, as an array.
    def items : Array({Char, Item})
      found = [] of {Char, Item}
      each_item { |letter, item| found << {letter, item} }
      found
    end

    # Every entry whose item answers the block.
    def select(& : Item -> Bool) : Array({Char, Item})
      entries.select { |_letter, item| yield item }
    end

    # Puts *item* in. Answers the letter it went under, or `nil` when every
    # letter is taken.
    #
    # It joins a letter holding something that looks the same, and takes a
    # letter of its own otherwise. `Item#looks_like?` decides, so a cursed
    # arrow joins the plain ones until somebody notices.
    def add(item : Item) : Char?
      letter = LETTERS.find { |found| @slots[found]?.try(&.holds? item) || false }

      unless letter
        letter = free
        return unless letter

        @slots[letter] = Stack.new
      end

      @slots[letter].add item
      letter
    end

    # Takes everything out from under *letter*. Answers it, oldest first.
    def remove(letter : Char) : Array(Item)
      @slots.delete(letter).try(&.items) || [] of Item
    end

    # Takes *count* off the front of *letter*, leaving the rest.
    #
    # Answers what came out, or `nil` when there is nothing under the letter.
    # A count at or above what the front holds takes the whole front stack,
    # and a letter left with nothing under it is freed.
    #
    # *id* is the id of the part that leaves, once it is a pile of its own.
    # `Stack#take` is where the split happens.
    def take(letter : Char, count : Int32, id : Int32) : Item?
      stack = @slots[letter]?
      return unless stack

      found = stack.take count, id
      @slots.delete letter if stack.empty?
      found
    end

    # Moves *item* out from under *letter* to a letter of its own.
    #
    # Answers the letter it went to, or `nil` when there was nowhere for it.
    # A letter holding one thing has nothing to split, and answers its own
    # letter.
    #
    # `Game` calls this when the character notices a blessing. What they
    # noticed no longer looks like what it was sitting with, and two things
    # that look different cannot share a letter.
    def relocate(letter : Char, item : Item) : Char?
      stack = @slots[letter]?
      return unless stack
      return letter if stack.size <= 1
      return unless stack.pull item

      @slots.delete letter if stack.empty?

      found = add item
      return found if found

      # Nowhere for it. Put it back rather than losing it, and let the caller
      # make room.
      (@slots[letter] ||= Stack.new).add item
      nil
    end

    # Takes everything but *keep* out from under *letter*.
    #
    # What comes out is the caller's to put somewhere. `Game` drops it on the
    # floor when a split has nowhere to go.
    def strip(letter : Char, keep : Item) : Array(Item)
      stack = @slots[letter]?
      return [] of Item unless stack

      gone = stack.strip keep
      @slots.delete letter if stack.empty?
      gone
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

    # One letter in a save file.
    #
    # A JSON object key has to be a string and a letter is a `Char`, so the
    # stored form is a list of pairs rather than an object.
    #
    # `item` is what a save written before a letter held a list holds. It is
    # read and never written. `items` is the form written now.
    struct Slot
      include JSON::Serializable

      getter letter : String
      getter item : Item? = nil
      getter items : Array(Item)? = nil

      def initialize(@letter : String, @items : Array(Item)? = nil,
                     @item : Item? = nil)
      end

      # What this letter holds, whichever form it was written in.
      def held : Array(Item)
        found = @items
        return found if found

        one = @item
        one ? [one] : [] of Item
      end
    end

    # The stored form of this inventory.
    def stored : Array(Slot)
      found = [] of Slot
      LETTERS.each do |letter|
        stack = @slots[letter]?
        found << Slot.new letter.to_s, stack.items if stack
      end
      found
    end

    def self.new(pull : JSON::PullParser) : Inventory
      slots = {} of Char => Stack

      Array(Slot).new(pull).each do |slot|
        letter = slot.letter[0]?
        next unless letter

        held = slot.held
        next if held.empty?

        slots[letter] = Stack.new held
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
