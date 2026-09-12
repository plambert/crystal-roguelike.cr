require "json"
require "./inventory"
require "./slot"

module Roguelike
  # What a character has readied, one slot at a time.
  #
  # A slot holds an inventory letter rather than an item. A readied item is
  # still carried, and a person reading the inventory has to see the sword in
  # their hand listed with everything else. Holding the item here as well
  # would put two copies of it in a save file.
  #
  # So every lookup goes through an `Inventory`. A letter whose item has left
  # the inventory names nothing, and `#clean` takes such a letter out.
  class Equipment
    # What is readied, by slot.
    getter slots : Hash(Slot, Char)

    def initialize(@slots : Hash(Slot, Char) = {} of Slot => Char)
    end

    # Whether nothing is readied.
    def empty? : Bool
      @slots.empty?
    end

    # How many slots are filled.
    def size : Int32
      @slots.size
    end

    # The letter in *slot*. `nil` for an empty slot.
    def [](slot : Slot) : Char?
      @slots[slot]?
    end

    # Which slot holds *letter*. `nil` when no slot does.
    def slot_of(letter : Char) : Slot?
      @slots.each { |slot, held| return slot if held == letter }
      nil
    end

    # Whether *letter* is readied anywhere.
    def readied?(letter : Char) : Bool
      !slot_of(letter).nil?
    end

    # Puts *letter* in *slot*. Answers the letter that was there, or `nil`.
    #
    # A letter readied somewhere else comes out of that slot first. One item
    # is in one place.
    def put(slot : Slot, letter : Char) : Char?
      held = @slots[slot]?

      taken = slot_of letter
      @slots.delete taken if taken && taken != slot

      @slots[slot] = letter
      held
    end

    # Empties *slot*. Answers the letter that was in it, or `nil`.
    def clear(slot : Slot) : Char?
      @slots.delete slot
    end

    # Takes *letter* out of whatever slot holds it. Answers that slot, or
    # `nil` when no slot held it.
    def release(letter : Char) : Slot?
      slot = slot_of letter
      return unless slot

      @slots.delete slot
      slot
    end

    # Every filled slot, in the order `Slot` names them.
    def each(& : Slot, Char ->) : Nil
      Slot.values.each do |slot|
        letter = @slots[slot]?
        yield slot, letter if letter
      end
    end

    # :ditto:, as an array.
    def entries : Array({Slot, Char})
      found = [] of {Slot, Char}
      each { |slot, letter| found << {slot, letter} }
      found
    end

    # Every filled armour slot, in the order `Slot` names them.
    def worn : Array({Slot, Char})
      entries.select { |slot, _letter| slot.armour? }
    end

    # Takes out every letter *inventory* no longer holds.
    #
    # A readied item that leaves the inventory leaves its slot. Nothing else
    # has to remember to empty the slot.
    def clean(inventory : Inventory) : Nil
      entries.each do |slot, letter|
        @slots.delete slot unless inventory.has? letter
      end
    end

    def to_s(io : IO) : Nil
      io << "Equipment("
      entries.each_with_index do |(slot, letter), index|
        io << ' ' if index > 0
        io << slot.label << '=' << letter
      end
      io << ')'
    end

    def ==(other : Equipment) : Bool
      @slots == other.slots
    end

    # One slot in a save file.
    #
    # A JSON object key has to be a string and a letter is a `Char`, so the
    # stored form is a list of pairs rather than an object. `Inventory` stores
    # its letters the same way.
    struct Held
      include JSON::Serializable

      getter slot : String
      getter letter : String

      def initialize(@slot : String, @letter : String)
      end
    end

    # The stored form of this equipment.
    def stored : Array(Held)
      entries.map { |slot, letter| Held.new slot.to_s, letter.to_s }
    end

    def self.new(pull : JSON::PullParser) : Equipment
      slots = {} of Slot => Char

      Array(Held).new(pull).each do |held|
        slot = Slot.parse? held.slot
        letter = held.letter[0]?
        next unless slot && letter

        slots[slot] = letter
      end

      new slots
    end

    def to_json(json : JSON::Builder) : Nil
      stored.to_json json
    end
  end
end
