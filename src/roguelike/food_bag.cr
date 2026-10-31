require "json"
require "../roguelike"

module Roguelike
  # How the food bag screen orders what is in the bag.
  enum FoodSort
    Weight
    Type
    Value
    Name
    Freshness

    # What the page is called.
    def label : String
      to_s.downcase
    end
  end

  # What the character carries to eat, apart from the pack.
  #
  # The bag holds food and rotten flesh. It has a weight limit and no
  # letters, and what is in it costs no pace. A stack of food shares one age,
  # so food picked up at different times sits in different stacks.
  class FoodBag
    include JSON::Serializable

    # The most the bag holds, by weight.
    LIMIT = 40

    # What is in the bag, oldest first.
    getter items : Array(Item) = [] of Item

    def initialize(@items : Array(Item) = [] of Item)
    end

    # What everything in the bag weighs.
    def weight : Int32
      @items.sum &.weight
    end

    # Whether *item* fits in what is left of the limit.
    def room_for?(item : Item) : Bool
      weight + item.weight <= LIMIT
    end

    # Whether *item* is something the bag takes at all.
    def self.takes?(item : Item) : Bool
      item.food? && !item.corpse?
    end

    # Puts *item* in. Answers the stack it went into, or `nil` when it does
    # not fit or is not something the bag takes.
    def add(item : Item) : Item?
      return unless FoodBag.takes?(item) && room_for?(item)

      found = @items.index &.stacks_with?(item)
      if found
        @items[found] = @items[found].merge item
        return @items[found]
      end

      @items << item
      item
    end

    # The stack with the id *id*. `nil` when there is none.
    def [](id : Int32) : Item?
      return if id.zero?

      @items.find &.id.==(id)
    end

    # Takes the stack *item* out by identity. Answers whether it was here.
    def remove(item : Item) : Bool
      found = @items.index &.same?(item)
      return false unless found

      @items.delete_at found
      true
    end

    # Takes one off the stack *item*, under the id *id*. Answers the one
    # taken, or `nil` when *item* is not here.
    #
    # A stack of one leaves whole and keeps its own id.
    def take_one(item : Item, id : Int32) : Item?
      found = @items.index &.same?(item)
      return unless found

      held = @items[found]
      if held.count <= 1
        @items.delete_at found
        return held
      end

      @items[found] = held.add -1
      held.with_count 1, id
    end

    # Puts *item* back in where it was taken from, ignoring the limit. A
    # piece that was eaten from goes back beside the stack it came from.
    def put_back(item : Item) : Item
      found = @items.index &.stacks_with?(item)
      if found
        @items[found] = @items[found].merge item
        return @items[found]
      end

      @items << item
      item
    end

    # Ages everything in the bag one turn. Answers each stack whose
    # freshness changed on this turn.
    def ripen : Array(Item)
      @items.select &.ripen
    end

    # Whether the bag is empty.
    def empty? : Bool
      @items.empty?
    end

    # How many stacks are in the bag.
    def size : Int32
      @items.size
    end

    # What is in the bag, in the order *sort* puts it in. Ties stay in the
    # order they went in.
    #
    # Weight and value put the most first. Freshness puts fresh food first,
    # and within each stage what turns soonest.
    def sorted(sort : FoodSort) : Array(Item)
      indexed = @items.each_with_index.to_a
      indexed.sort_by! do |(item, index)|
        noun = Lore.food_noun item, false
        case sort
        in .weight?    then {-item.weight, 0, noun, index}
        in .type?      then {item.category.value, 0, noun, index}
        in .value?     then {-item.food_facts.value, 0, noun, index}
        in .name?      then {0, 0, noun, index}
        in .freshness? then {item.freshness.value, -FoodBag.ripeness(item), "", index}
        end
      end
      indexed.map &.[0]
    end

    # How far *item* is toward its next freshness, out of a thousand. Food
    # that never spoils is at zero.
    def self.ripeness(item : Item) : Int32
      keeps = item.food_facts.keeps
      return 0 if keeps <= 0

      (item.age % keeps) * 1000 // keeps
    end

    def ==(other : FoodBag) : Bool
      @items == other.items
    end

    def to_s(io : IO) : Nil
      io << "FoodBag(" << @items.size << ' ' << weight << '/' << LIMIT << ')'
    end
  end

  # A buff or a debuff from what the character ate, and the turns it has
  # left.
  #
  # *power* is how strong it is. A stronger one of the same status replaces
  # a weaker one. An equal one refreshes the timer. A weaker one does
  # nothing.
  class Buff
    include JSON::Serializable

    # What happened when one was offered.
    enum Taken
      Started
      Stronger
      Renewed
      Weaker
    end

    getter status : Event::Status
    getter power : Int32
    getter left : Int32

    def initialize(@status : Event::Status, @power : Int32, @left : Int32)
    end

    # Counts one turn down. Answers whether it ran out on this one.
    def pass : Bool
      @left -= 1 if @left > 0
      @left.zero?
    end

    def ==(other : Buff) : Bool
      @status == other.status && @power == other.power && @left == other.left
    end
  end
end
