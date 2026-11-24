require "json"
require "../roguelike"

module Roguelike
  # An ordered list of rules about items, and what each rule decides.
  #
  # `List(O)` holds the rules. A rule matches an item or does not, and the
  # first rule that matches gives its outcome. `List#otherwise` is the
  # outcome when no rule matches. *O* is an enum the user of the list
  # chooses, so one model serves automatic pickup, and can serve a list that
  # hides or highlights items or one that sorts the food bag.
  #
  # A rule reads an item only through `Facts`, which answers from what the
  # character knows. A blessing nobody has found out and a kind nobody has
  # identified match nothing.
  #
  #     rules = ItemFilter::List(Pickup::Outcome).new [
  #       ItemFilter::Rule.new(Pickup::Outcome::Take, ItemFilter::Group::Gold),
  #     ], Pickup::Outcome::Leave
  #     rules.verdict item, facts # => Take for gold, Leave for the rest
  module ItemFilter
    # The most rules a list holds. A longer list is not valid.
    LIMIT = 40

    # The sorts of item a rule names.
    #
    # A member is never removed and never reordered. A save and a replay hold
    # the member name.
    enum Group
      Gold
      Food
      Weapon
      Launcher
      Ammunition
      Thrown
      Armor
      Potion
      Scroll
      Wand
      Light
      Tool
      Amulet
      Remains
      Reagent
      Refuse

      # The group *item* is in.
      def self.of(item : Item) : Group
        case item.kind.item_class
        in .treasure?         then Gold
        in .food?, .delicacy? then Food
        in .melee?            then Weapon
        in .ranged_weapon?    then Launcher
        in .ammunition?       then Ammunition
        in .thrown?           then Thrown
        in .armor?            then Armor
        in .potion?           then Potion
        in .scroll?           then Scroll
        in .wand?             then Wand
        in .light?            then Light
        in .tool?             then Tool
        in .amulet?           then Amulet
        in .remains?          then Remains
        in .reagent?          then Reagent
        in .refuse?           then Refuse
        end
      end

      # What one of the group is called after "any".
      def noun : String
        case self
        in .gold?       then "gold"
        in .food?       then "food"
        in .weapon?     then "melee weapon"
        in .launcher?   then "ranged weapon"
        in .ammunition? then "ammunition"
        in .thrown?     then "throwing weapon"
        in .armor?      then "armor"
        in .potion?     then "potion"
        in .scroll?     then "scroll"
        in .wand?       then "wand"
        in .light?      then "light"
        in .tool?       then "tool"
        in .amulet?     then "amulet"
        in .remains?    then "remains"
        in .reagent?    then "reagent"
        in .refuse?     then "refuse"
        end
      end
    end

    # One thing a rule asks about an item. `Facts#holds?` answers each.
    #
    # A member is never removed and never reordered. A save and a replay hold
    # the member name.
    enum Trait
      # The character put the pile down.
      Dropped

      # The character knows the item is cursed.
      KnownCursed

      # The character knows the item is blessed.
      KnownBlessed

      # The character knows what kind of thing the item is.
      Identified

      # The item could be more of a pile the character carries.
      Stacks

      # The item is the ammunition the quiver holds, or held last.
      Quiver

      # The item is food that has rotted.
      Spoiled

      # The item is a melee weapon or a piece of armor better than the one
      # in use. `Appraisal.better?` decides.
      Better

      # The words that follow the noun when the trait is *wanted*, and when
      # it is not.
      def clause(wanted : Bool) : String
        case self
        in .dropped?
          wanted ? "you put down" : "you did not put down"
        in .known_cursed?
          wanted ? "you know is cursed" : "you do not know is cursed"
        in .known_blessed?
          wanted ? "you know is blessed" : "you do not know is blessed"
        in .identified?
          wanted ? "you have identified" : "you have not identified"
        in .stacks?
          wanted ? "that stacks with what you carry" : "that does not stack with what you carry"
        in .quiver?
          wanted ? "your quiver holds" : "your quiver does not hold"
        in .spoiled?
          wanted ? "that has spoiled" : "that has not spoiled"
        in .better?
          wanted ? "that is better than what you use" : "that is not better than what you use"
        end
      end

      # A short name for a form row.
      def label : String
        case self
        in .dropped?       then "You put it down"
        in .known_cursed?  then "Known cursed"
        in .known_blessed? then "Known blessed"
        in .identified?    then "Identified"
        in .stacks?        then "Stacks with yours"
        in .quiver?        then "Quiver holds it"
        in .spoiled?       then "Spoiled"
        in .better?        then "Better than yours"
        end
      end
    end

    # A trait, and whether a rule wants it to hold.
    #
    # It is written as the trait's name, with `!` in front when the rule
    # wants it not to hold, as in `"spoiled"` and `"!spoiled"`.
    record Test, trait : Trait, wanted : Bool = true do
      def self.new(pull : JSON::PullParser) : Test
        text = pull.read_string
        wanted = !text.starts_with? '!'
        trait = Trait.parse? text.lchop('!')
        raise JSON::ParseException.new("unknown trait #{text.inspect}", 0, 0) unless trait

        new trait, wanted
      end

      def to_json(json : JSON::Builder) : Nil
        json.string "#{wanted ? "" : "!"}#{trait.to_s.underscore}"
      end
    end

    # What the character knows about items, for a rule to ask.
    #
    # One is built for the character as they stand and answers for any
    # number of items. It reads the character and changes nothing.
    class Facts
      # The stacking items carried that are not known to be cursed.
      @held : Array(Item)

      def initialize(@player : Player, @lore : Lore)
        @held = [] of Item
        @player.inventory.each_item do |_letter, item|
          @held << item if item.kind.stacks? && !item.known_cursed?
        end
      end

      # Whether *trait* holds for *item*. `nil` when the character cannot
      # tell, and then no rule that asks matches, whichever way it asks.
      def holds?(trait : Trait, item : Item) : Bool?
        case trait
        in .dropped?       then item.dropped?
        in .known_cursed?  then item.known_cursed?
        in .known_blessed? then item.blessing_known? && item.blessed?
        in .identified?    then @lore.known? item.kind
        in .stacks?        then @held.any?(&.might_be?(item))
        in .quiver?        then quiver? item
        in .spoiled?       then item.food? && item.freshness.rotten?
        in .better?        then Appraisal.better? item, @player, @lore
        end
      end

      # Whether the quiver takes *item* back. A full quiver takes what it
      # holds, damaged or not. An empty one takes what it held last.
      private def quiver?(item : Item) : Bool
        if held = @player.quivered
          return held.looks_like? item, any_condition: true
        end

        @player.quiver_memory.try(&.matches?(item)) || false
      end
    end

    # One rule. It matches an item in *group*, or in any group when that is
    # `nil`, for which every test comes out the way the test wants.
    struct Rule(O)
      include JSON::Serializable

      @[JSON::Field(key: "class")]
      getter group : Group?

      @[JSON::Field(key: "when", ignore_serialize: @tests.empty?)]
      getter tests : Array(Test) = [] of Test

      @[JSON::Field(key: "then")]
      getter outcome : O

      def initialize(@outcome : O, @group : Group? = nil,
                     @tests : Array(Test) = [] of Test)
      end

      def_equals_and_hash @group, @tests, @outcome

      # Whether this rule matches *item*.
      def matches?(item : Item, facts : Facts) : Bool
        wanted = @group
        return false if wanted && wanted != Group.of(item)

        @tests.all? { |test| facts.holds?(test.trait, item) == test.wanted }
      end

      # Whether the rule asks about *trait*, and which way. `nil` when it
      # does not ask.
      def wants?(trait : Trait) : Bool?
        @tests.find(&.trait.==(trait)).try &.wanted
      end

      # What the rule matches, in words.
      #
      #     Anything
      #     Any food that has not spoiled
      #     Any potion you know is cursed and you did not put down
      def phrase : String
        subject = @group.try { |group| "Any #{group.noun}" } || "Anything"
        return subject if @tests.empty?

        "#{subject} #{@tests.join(" and ") { |test| test.trait.clause test.wanted }}"
      end
    end

    # The rules in order, and the outcome when none of them matches.
    struct List(O)
      include JSON::Serializable

      getter rules : Array(Rule(O)) = [] of Rule(O)

      @[JSON::Field(key: "else")]
      getter otherwise : O

      def initialize(@rules : Array(Rule(O)), @otherwise : O)
      end

      def_equals_and_hash @rules, @otherwise

      # The outcome of the first rule that matches *item*, or `#otherwise`.
      def verdict(item : Item, facts : Facts) : O
        @rules.each { |rule| return rule.outcome if rule.matches? item, facts }

        @otherwise
      end

      # Whether the list is short enough and no rule asks a trait twice.
      def valid? : Bool
        @rules.size <= LIMIT &&
          @rules.all? { |rule| rule.tests.map(&.trait).uniq!.size == rule.tests.size }
      end

      # A copy with *rules* in place of these.
      def with(rules : Array(Rule(O))) : List(O)
        List(O).new rules, @otherwise
      end

      # A copy that gives *otherwise* when no rule matches.
      def with(otherwise : O) : List(O)
        List(O).new @rules, otherwise
      end
    end
  end
end
