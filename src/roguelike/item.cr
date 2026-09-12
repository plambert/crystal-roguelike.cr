require "json"
require "./item_kind"

module Roguelike
  # One thing a character can pick up.
  #
  # A kind and its variants. The kind says what it is. The enchantment, the
  # condition and the charges say which one of them this is.
  #
  # An item does not know what it is called. `Lore#name` names it, because the
  # name depends on what the character has found out.
  class Item
    include JSON::Serializable

    # What sort of thing this is.
    getter kind : ItemKind

    # The `+N` on it. Zero on a plain one. Negative on a cursed one.
    getter enchantment : Int32

    # How well made it is, or how badly worn.
    getter condition : Condition

    # Whether a god has touched it, and which way.
    getter blessing : Blessing

    # Whether the character knows the blessing.
    #
    # This is per item rather than per kind. Two identical swords may be
    # blessed and cursed, so learning one says nothing about the other.
    getter? blessing_known : Bool

    # How many there are. Always one for a kind that does not stack.
    getter count : Int32

    # Uses left on a wand. `nil` for anything that is not one.
    getter charges : Int32?

    # Whether this item is alight. Always false for anything that does not
    # burn.
    getter? lit : Bool

    def initialize(@kind : ItemKind,
                   @enchantment : Int32 = 0,
                   @condition : Condition = Condition::Plain,
                   count : Int32 = 1,
                   charges : Int32? = nil,
                   @blessing : Blessing = Blessing::Uncursed,
                   @blessing_known : Bool = false,
                   lit : Bool = false)
      @lit = @kind.light? && lit
      @count = @kind.stacks? ? Math.max(count, 1) : 1
      @charges = charges || (@kind.charges > 0 ? @kind.charges : nil)
      @enchantment = @kind.enchantable? ? @enchantment : 0
      @condition = @kind.enchantable? ? @condition : Condition::Plain
    end

    # Whether this item refuses to be taken off or put down.
    def sticks? : Bool
      @blessing.sticks?
    end

    # How far this item throws light. Zero while it is not alight.
    def light : Int32
      @lit ? @kind.light : 0
    end

    # Whether this item can be set alight.
    def burns? : Bool
      @kind.light?
    end

    # Sets this item alight. Answers whether that was a change.
    #
    # A stack is one flame. Lighting two candles held as one entry lights the
    # entry, because a person carrying two candles lights the one in their
    # hand.
    def kindle : Bool
      return false unless burns?
      return false if @lit

      @lit = true
      true
    end

    # Puts this item out. Answers whether that was a change.
    def douse : Bool
      return false unless @lit

      @lit = false
      true
    end

    # Whether a god has blessed it.
    def blessed? : Bool
      @blessing.blessed?
    end

    # Whether a god has cursed it.
    def cursed? : Bool
      @blessing.cursed?
    end

    # Records that the character has found out the blessing. Answers whether
    # that was news.
    def reveal_blessing : Bool
      return false if @blessing_known

      @blessing_known = true
      true
    end

    # What this item does to whatever it hits.
    #
    # The kind's dice, plus the enchantment and the condition.
    def damage : Dice
      @kind.damage.with_bonus @enchantment + @condition.modifier
    end

    # What this item takes off an attack against whoever wears it.
    def armour : Int32
      return 0 unless @kind.item_class.armour?

      Math.max @kind.armour + @enchantment + @condition.modifier, 0
    end

    # How much the whole stack weighs.
    def weight : Int32
      @kind.facts.weight * @count
    end

    # Whether this item and *other* could be held as one entry.
    #
    # Everything but the count has to match. A `+1` arrow does not stack with
    # a plain one, because a person firing them would want to know which is
    # which.
    def stacks_with?(other : Item) : Bool
      @kind.stacks? && @kind == other.kind &&
        @enchantment == other.enchantment && @condition == other.condition &&
        @blessing == other.blessing && @blessing_known == other.blessing_known? &&
        @lit == other.lit?
    end

    # A copy of this item with *count* of them.
    def with_count(count : Int32) : Item
      Item.new @kind, @enchantment, @condition, count, @charges,
        @blessing, @blessing_known, @lit
    end

    # A copy with *amount* added to the count.
    def add(amount : Int32) : Item
      with_count @count + amount
    end

    # Uses one charge. Answers whether there was one to use.
    def spend : Bool
      left = @charges
      return false unless left && left > 0

      @charges = left - 1
      true
    end

    # Whether a wand has nothing left.
    def spent? : Bool
      left = @charges
      left ? left <= 0 : false
    end

    def ==(other : Item) : Bool
      @kind == other.kind && @enchantment == other.enchantment &&
        @condition == other.condition && @count == other.count &&
        @charges == other.charges && @blessing == other.blessing &&
        @blessing_known == other.blessing_known? && @lit == other.lit?
    end

    def hash(hasher)
      {@kind, @enchantment, @condition, @count, @charges,
       @blessing, @blessing_known, @lit}.hash hasher
    end

    def to_s(io : IO) : Nil
      io << "Item(" << @kind
      io << " x" << @count if @count > 1
      io << ' ' << @blessing if !@blessing.uncursed?
      io << ' ' << @condition if !@condition.plain?
      io << " +" << @enchantment if @enchantment > 0
      io << ' ' << @enchantment if @enchantment < 0
      io << " lit" if @lit
      io << ')'
    end
  end
end
