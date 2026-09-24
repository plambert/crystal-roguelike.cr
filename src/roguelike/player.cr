require "json"
require "./advancement"
require "./attributes"
require "./equipment"
require "./inventory"
require "./knowledge"
require "./pace"

module Roguelike
  # The character the person plays.
  #
  # The word "level" means two things in a roguelike. `#floor` is which level
  # of the world the character stands on. `#level` is how far the character
  # has advanced. They are named apart here so that neither reading has to be
  # guessed.
  #
  # The floor is held by its id rather than by a reference to the `Floor`.
  # Levels persist and a save file stores them. A save file that stored the
  # floor twice would hold one copy in the world and one under the player. The
  # two copies would then need to stay in step.
  class Player
    include JSON::Serializable

    # What the person called this character.
    #
    # Empty for a character nobody has named, which is what a spec builds and
    # what a run holds until the title screen has been answered. The save file
    # is named after a slug of this, and the file's header holds it as typed.
    property name : String = ""

    # Which level of the world the character stands on.
    property floor : String

    # The column the character stands in.
    getter x : Int32

    # The row the character stands in.
    getter y : Int32

    # What the character is made of.
    property attributes : Attributes

    # How far the character has advanced. It starts at one.
    getter level : Int32

    # Experience points. `Advancement` turns them into a level.
    getter experience : Int32

    # Hit points left. The character dies at zero.
    getter hit_points : Int32

    # How many turns the character cannot see for.
    #
    # It has a default, so a save written before this field existed loads
    # with the character able to see.
    getter blinded : Int32 = 0

    # How fast the character is, and how much of the next action is paid for.
    #
    # It has a default, so a save written before this field existed loads a
    # character at normal speed with an action in hand.
    getter pace : Pace = Pace.new

    # What the character carries.
    getter inventory : Inventory

    # What the character has readied, by slot. The letters are the
    # inventory's own.
    getter equipment : Equipment

    # Gold pieces. Counted rather than carried, so they take no letter.
    getter gold : Int32

    # What the character remembers of each floor they have walked on, by
    # floor id.
    #
    # Floors persist, so a character coming back to one remembers the shape of
    # it. A monster band will hold the same type.
    getter memory : Hash(String, Knowledge)

    def initialize(@floor : String, @x : Int32, @y : Int32,
                   @attributes : Attributes = Attributes.new,
                   @level : Int32 = 1,
                   @experience : Int32 = 0,
                   hit_points : Int32? = nil,
                   @inventory : Inventory = Inventory.new,
                   @gold : Int32 = 0,
                   @equipment : Equipment = Equipment.new,
                   @memory : Hash(String, Knowledge) = {} of String => Knowledge,
                   @name : String = "")
      @hit_points = hit_points || Advancement.max_hit_points(@level, @attributes.constitution)
    end

    # What the character remembers of the floor they are on.
    #
    # A floor they have not walked on yet gets an empty one, put in the table
    # so that what they learn on it is kept. That is a change to the run, and
    # `#memory` is written to the save, so only code that is about to write
    # to the map calls this. Code that reads the map calls `#knowledge?`.
    def knowledge : Knowledge
      @memory[@floor] ||= Knowledge.new @floor
    end

    # What the character remembers of the floor they are on. `nil` for a
    # floor they have never looked at.
    #
    # Nothing is put in the table. Reading the map leaves the run as it was,
    # so two runs on one seed and one list of actions have the same
    # fingerprint whether or not anything read the map.
    def knowledge? : Knowledge?
      @memory[@floor]?
    end

    # What the character remembers of the floor *id*. `nil` for one they have
    # never been on.
    def knowledge?(id : String) : Knowledge?
      @memory[id]?
    end

    # What a character with nothing in their hands hits for.
    UNARMED = Dice.new 1, 2

    # What is in *slot*. `nil` for an empty slot.
    def in_slot(slot : Slot) : Item?
      letter = @equipment[slot]
      return unless letter

      @inventory[letter]
    end

    # What the character swings. `nil` for bare hands.
    def wielded : Item?
      in_slot Slot::Melee
    end

    # What the character shoots with. `nil` for nothing readied.
    def ranged_weapon : Item?
      in_slot Slot::Ranged
    end

    # What the character shoots. `nil` for an empty quiver.
    def quivered : Item?
      in_slot Slot::Quiver
    end

    # Every piece of armour being worn, by slot.
    def worn : Array({Slot, Item})
      found = [] of {Slot, Item}

      @equipment.worn.each do |slot, letter|
        item = @inventory[letter]
        found << {slot, item} if item
      end

      found
    end

    # Whether what is under *letter* is readied in any slot.
    def readied?(letter : Char) : Bool
      @equipment.readied? letter
    end

    # How much an attack against this character is reduced by.
    #
    # Higher is better. It is what is worn, plus the dexterity modifier, and
    # it never goes below zero. Each piece already carries its enchantment and
    # its condition, which `Item#armour` works in.
    def armour_class : Int32
      total = worn.sum { |_slot, item| item.armour }

      Math.max total + @attributes.modifier(Attributes::Which::Dexterity), 0
    end

    # What the character adds to a swing.
    #
    # The dexterity modifier, plus what the wielded weapon adds. Bare hands
    # add the modifier and nothing else.
    def to_hit : Int32
      bonus = @attributes.modifier Attributes::Which::Dexterity
      held = wielded
      return bonus unless held && Player.swung?(held)

      bonus + held.aim
    end

    # Whether what is in the hand is swung for its own dice.
    #
    # A thing with no dice of its own hits like a fist. A cursed wand puts
    # itself in the hand, and swinging a wand is swinging a stick.
    def self.swung?(item : Item) : Bool
      !item.kind.damage.none?
    end

    # What the character hits for in melee.
    #
    # The wielded weapon's dice, or `UNARMED` for bare hands, plus the
    # strength modifier. The weapon's own dice already carry its enchantment
    # and its condition.
    def damage : Dice
      held = wielded
      dice = held && Player.swung?(held) ? held.damage : UNARMED

      dice.with_bonus @attributes.modifier(Attributes::Which::Strength)
    end

    # What the character adds to a shot from *weapon* with *ammunition*.
    #
    # The dexterity modifier, plus what each of the two adds. A masterwork
    # bow and a bent arrow both count, and so does a blessing on either.
    def to_shoot(weapon : Item, ammunition : Item) : Int32
      @attributes.modifier(Attributes::Which::Dexterity) +
        weapon.aim + ammunition.aim
    end

    # What a shot of *ammunition* from *weapon* hits for.
    #
    # The ammunition's dice, which already carry its own enchantment and its
    # condition, plus the weapon's enchantment and condition. Strength adds
    # nothing. The bow throws the arrow, not the arm.
    def shot_damage(weapon : Item, ammunition : Item) : Dice
      ammunition.damage.with_bonus weapon.enchantment + weapon.condition.modifier
    end

    # What the character adds to a throw of *item*.
    def to_throw(item : Item) : Int32
      @attributes.modifier(Attributes::Which::Dexterity) + item.aim
    end

    # What *item* hits for when it is thrown.
    #
    # Its dice, plus the strength modifier. An arm sends this one.
    def throw_damage(item : Item) : Dice
      item.damage.with_bonus @attributes.modifier(Attributes::Which::Strength)
    end

    # What the character adds to a bolt from a wand.
    #
    # The dexterity modifier and nothing else. A wand carries no `+N`, and
    # strength does not aim one.
    def to_zap : Int32
      @attributes.modifier Attributes::Which::Dexterity
    end

    # Adds *amount* gold pieces. Answers the new total.
    def take_gold(amount : Int32) : Int32
      @gold += Math.max amount, 0
    end

    # Takes *amount* gold pieces away, no further than nothing. Answers how
    # many were taken.
    def spend_gold(amount : Int32) : Int32
      spent = Math.min Math.max(amount, 0), @gold
      @gold -= spent
      spent
    end

    # Where the character stands.
    def at : {Int32, Int32}
      {@x, @y}
    end

    # Puts the character at *x*, *y*. This method does not check the square.
    # `Game#step` checks the square.
    def move_to(x : Int32, y : Int32) : Nil
      @x = x
      @y = y
    end

    # :ditto:
    def move_to(spot : {Int32, Int32}) : Nil
      move_to spot[0], spot[1]
    end

    # Whether the character stands on *x*, *y*.
    def at?(x : Int32, y : Int32) : Bool
      @x == x && @y == y
    end

    # Hit points at full health.
    def max_hit_points : Int32
      Advancement.max_hit_points @level, @attributes.constitution
    end

    # Whether the character is still alive.
    def alive? : Bool
      @hit_points > 0
    end

    # Experience still needed to reach the next level. `nil` at the last one.
    def to_next_level : Int32?
      Advancement.to_next @experience
    end

    # Whether the character cannot see.
    def blind? : Bool
      @blinded > 0
    end

    # Takes the character's sight away for *turns*. Answers whether that was
    # longer than they were already blinded for.
    #
    # A second helping does not stack. What it does is set a floor: whichever
    # is longer wins.
    def blind(turns : Int32) : Bool
      return false if turns <= @blinded

      @blinded = turns
      true
    end

    # Passes one turn of being unable to see. Answers whether sight came
    # back on this one.
    def blink : Bool
      return false unless blind?

      @blinded -= 1
      @blinded.zero?
    end

    # Ticks since the last wound.
    #
    # `Game#regenerate` reads it. It has a default, so a save written before
    # this field existed loads a character who was hurt a moment ago and has
    # to go unhurt for a while before they regenerate.
    getter rested : Int32 = 0

    # Counts one tick of going unhurt. Answers how many there have been.
    def rest : Int32
      @rested += 1
    end

    # Ticks one hit point of regeneration takes, from constitution.
    def regeneration : Int32
      Advancement.regeneration @attributes.constitution
    end

    # Takes *amount* off the hit points. Answers how many are left.
    #
    # Being hurt puts the rest count back to nothing, so a character hit once
    # a turn never regenerates.
    def hurt(amount : Int32) : Int32
      @rested = 0
      @hit_points = Math.max @hit_points - amount, 0
    end

    # Puts *amount* back, up to full health. Answers how many were restored.
    #
    # It never takes any off. A character already above their maximum is left
    # where they are rather than pulled down to it, because healing that hurt
    # would be a strange thing for a potion to do.
    def heal(amount : Int32) : Int32
      before = @hit_points
      @hit_points = Math.min before + amount, Math.max(max_hit_points, before)
      @hit_points - before
    end

    # Adds *amount* experience. Answers how many levels that gained.
    #
    # A level gained raises the maximum hit points. The current hit points go
    # up by the same number. A character who levels up mid fight is better off
    # than before, and is not suddenly at full health either.
    def gain(amount : Int32) : Int32
      return 0 if amount <= 0

      @experience += amount
      wanted = Advancement.level_for @experience
      return 0 if wanted <= @level

      before = max_hit_points
      gained = wanted - @level
      @level = wanted
      @hit_points += max_hit_points - before

      gained
    end

    def to_s(io : IO) : Nil
      io << "Player(" << @floor << ' ' << @x << ',' << @y
      io << " L" << @level << ' ' << @hit_points << '/' << max_hit_points << ')'
    end
  end
end
