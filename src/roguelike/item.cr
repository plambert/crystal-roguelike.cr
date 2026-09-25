require "json"
require "./handling"
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

    # What this pile is called in a log or by a bot, for as long as it is
    # this pile.
    #
    # Zero means it has no id yet. `Game#enrol` walks the run and gives an
    # id to whatever has none. Everything the generator made is numbered
    # that way. A save written before ids existed is numbered the same way.
    #
    # The field has a default, so such a save loads rather than being
    # refused.
    getter id : Int32 = 0

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

    # How much attention this item has had.
    #
    # `Handling` says what a turn is worth and how much is enough to tell a
    # blessing from a curse. It has a default, so an item written before this
    # field existed loads and starts from nothing.
    getter handling : Int32 = 0

    def initialize(@kind : ItemKind,
                   @enchantment : Int32 = 0,
                   @condition : Condition = Condition::Plain,
                   count : Int32 = 1,
                   charges : Int32? = nil,
                   @blessing : Blessing = Blessing::Uncursed,
                   @blessing_known : Bool = false,
                   lit : Bool = false,
                   @handling : Int32 = 0)
      @lit = @kind.light? && lit
      @count = @kind.stacks? ? Math.max(count, 1) : 1
      @charges = charges || (@kind.charges > 0 ? @kind.charges : nil)
      @enchantment = @kind.enchantable? ? @enchantment : 0
      @condition = @kind.enchantable? ? @condition : Condition::Plain
    end

    # Whether a curse holds this item.
    #
    # A curse holds what is in a slot and nothing else. This says only that
    # the item is cursed. `Game` is what knows whether it is in one, and the
    # two together decide whether it can be let go of.
    def sticks? : Bool
      @blessing.sticks?
    end

    # Adds *gain* to how much attention this item has had.
    def handle(gain : Int32) : Nil
      @handling += gain
    end

    # Gives this item the id *id*. Answers whether it took one.
    #
    # An item takes an id once. A pile that already has one keeps it, so
    # walking the run twice numbers nothing twice. An *id* of zero means
    # there is no id to give.
    def enrol(id : Int32) : Bool
      return false unless @id.zero?
      return false if id.zero?

      @id = id
      true
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

    # Takes a curse off. Answers whether that was a change.
    #
    # The blessing is left known. A character who watched a curse lift knows
    # the item is no longer cursed.
    def uncurse : Bool
      return false unless @blessing.cursed?

      @blessing = Blessing::Uncursed
      @blessing_known = true
      true
    end

    # Marks this item damaged. Answers whether that was a change.
    #
    # The constructor refuses a condition on a kind that cannot carry one, so
    # `Items.make` never rolls one onto a wand. This is the only way one gets
    # there. A cursed wand that cracks in the hand goes dormant.
    def crack : Bool
      return false if @condition.damaged?

      @condition = Condition::Damaged
      true
    end

    # Takes the damage out. Answers whether that was a change.
    #
    # A damaged thing is made plain rather than better than it was. A scroll
    # of repair undoes wear; it does not make a smith out of the reader.
    def repair : Bool
      return false unless @condition.damaged?

      @condition = Condition::Plain
      true
    end

    # Whether the damage in this item is damage a repair could take out.
    #
    # A wand is left out. The only way a wand is damaged at all is a cursed
    # one cracking in the hand, and that crack is the way out of the curse.
    # Mending it would hand the character back to it.
    def mendable? : Bool
      @kind.enchantable?
    end

    # Blesses this item. Answers whether that was a change.
    #
    # The blessing is left known. A character who watched a god touch a thing
    # knows it has been touched.
    def bless : Bool
      return false if @blessing.blessed?

      @blessing = Blessing::Blessed
      @blessing_known = true
      true
    end

    # Records that the character has found out the blessing. Answers whether
    # that was news.
    def reveal_blessing : Bool
      return false if @blessing_known

      @blessing_known = true
      true
    end

    # What a blessing adds to a swing or a shot landing.
    #
    # It adds nothing to the damage, so it never shows in a number the
    # character is told. A blessed sword reads as a plain one and lands more
    # often than one.
    BLESSED_AIM = 1

    # What this item adds to a swing or a shot landing.
    #
    # The enchantment, the condition, and a blessing. Nothing here asks
    # whether the character knows about the blessing: a blessed sword swings
    # the way it swings.
    def aim : Int32
      @enchantment + @condition.modifier + (blessed? ? BLESSED_AIM : 0)
    end

    # What this item does to whatever it hits.
    #
    # The kind's dice, plus the enchantment and the condition. A blessing is
    # not in it. See `#aim`.
    def damage : Dice
      @kind.damage.with_bonus @enchantment + @condition.modifier
    end

    # What this item takes off an attack against whoever wears it.
    def armor : Int32
      return 0 unless @kind.item_class.armor?

      Math.max @kind.armor + @enchantment + @condition.modifier, 0
    end

    # How much the whole stack weighs.
    def weight : Int32
      @kind.facts.weight * @count
    end

    # Whether this item and *other* are one and the same thing.
    #
    # Everything but the count has to match, the hidden blessing included. A
    # `+1` arrow does not stack with a plain one, because a person firing
    # them would want to know which is which.
    #
    # `Inventory` holds these inside a letter. Which letter they go under is
    # `#looks_like?`, which compares less.
    #
    # `handling` is left out. It is what the character has noticed about the
    # item rather than a property of the item, and two stacks that merge take
    # the larger through `#merge`.
    def stacks_with?(other : Item) : Bool
      @kind.stacks? && @kind == other.kind &&
        @enchantment == other.enchantment && @condition == other.condition &&
        @blessing == other.blessing && @blessing_known == other.blessing_known? &&
        @lit == other.lit?
    end

    # Whether *other* would sit under the same letter as this.
    #
    # Everything the character can see has to match. The blessing counts only
    # once they know it, so two arrows that differ in a hidden curse share a
    # letter until one of them is noticed. Two letters would say something
    # differs without saying what.
    #
    # A kind that does not stack keeps a letter to itself. `Equipment` names
    # a slot's contents by letter, and two swords under one letter would
    # leave no way to say which is wielded.
    def looks_like?(other : Item) : Bool
      @kind.stacks? && @kind == other.kind &&
        @enchantment == other.enchantment && @condition == other.condition &&
        @lit == other.lit? &&
        @blessing_known == other.blessing_known? &&
        (!@blessing_known || @blessing == other.blessing)
    end

    # This item and *other* held as one, with the larger handling of the two.
    #
    # The caller has already decided they stack.
    #
    # The id is this item's. Two piles put together are one pile, and it is
    # this one. *other*'s id names nothing after this, and it is not given
    # out again.
    def merge(other : Item) : Item
      found = with_count @count + other.count
      found.handle Math.max(@handling, other.handling) - @handling
      found
    end

    # A copy of this item with *count* of them, under the id *id*.
    #
    # The id carries over by default. A change in how many are in a pile does
    # not make it a different pile. Ten arrows with one taken away are still
    # the same arrows. `#carried` counts a letter as one stack, which is a
    # way of looking at a pile rather than a new pile.
    #
    # A caller that splits a pile in two passes an *id* from `Game#next_id`
    # for the part that leaves. `Inventory::Stack#take` is the one place that
    # happens.
    def with_count(count : Int32, id : Int32 = @id) : Item
      found = Item.new @kind, @enchantment, @condition, count, @charges,
        @blessing, @blessing_known, @lit, @handling
      found.enrol id
      found
    end

    # A separate item with the same state.
    #
    # A `Memory` holds one of these. An item goes on burning down and being
    # identified after somebody looks away, and what they remember does not.
    #
    # The id carries over. What is remembered of a pile and the pile itself
    # have the same id.
    def copy : Item
      with_count @count
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

    # Whether this item and *other* are the same in every way a character
    # could care about.
    #
    # The id is left out, here and in `#hash`. An id is which pile this is
    # rather than what it is. A spec asks whether the character carries twelve
    # arrows. That question is about the arrows and not about which pile they
    # are in.
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
