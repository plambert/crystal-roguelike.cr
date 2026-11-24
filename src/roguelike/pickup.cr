require "../roguelike"

module Roguelike
  # What the character picks up without being asked.
  #
  # The rules are an `ItemFilter::List`. `Game#pickup_rules` holds the run's
  # own, a save keeps them, and `Action::Configure` changes them, so a replay
  # picks up the same things. `options.json` holds the rules a new character
  # starts with.
  #
  # A rule that says take is still bound by what can be carried. Food goes
  # in the food bag while the bag has room, a corpse is never taken, and
  # anything else needs a letter in the pack.
  module Pickup
    # What a rule decides for an item on the square the character steps on.
    #
    # A member is never removed and never reordered. A save and a replay hold
    # the member name.
    enum Outcome
      Take
      Leave

      # The word a rule row ends with.
      def label : String
        take? ? "take" : "leave"
      end
    end

    # A rule about automatic pickup.
    alias Rule = ItemFilter::Rule(Outcome)

    # The rules of automatic pickup.
    alias Rules = ItemFilter::List(Outcome)

    # The rules a character has until somebody changes them.
    #
    # Gold is taken. Nothing the character put down is taken. Food that has
    # not rotted is taken, and so is the quiver's own ammunition and anything
    # that could be more of a pile already carried.
    def self.default : Rules
      test = ->(trait : ItemFilter::Trait, wanted : Bool) { [ItemFilter::Test.new(trait, wanted)] }

      Rules.new [
        Rule.new(Outcome::Take, ItemFilter::Group::Gold),
        Rule.new(Outcome::Leave, tests: test.call(ItemFilter::Trait::Dropped, true)),
        Rule.new(Outcome::Leave, ItemFilter::Group::Food, test.call(ItemFilter::Trait::Spoiled, true)),
        Rule.new(Outcome::Take, ItemFilter::Group::Food),
        Rule.new(Outcome::Take, tests: test.call(ItemFilter::Trait::Quiver, true)),
        Rule.new(Outcome::Take, tests: test.call(ItemFilter::Trait::Stacks, true)),
      ], Outcome::Leave
    end

    # Reads the rules in `options.json` without rejecting the other options
    # when they do not read. Rules that do not read are the defaults.
    module Stored
      def self.from_json(pull : JSON::PullParser) : Rules
        found = Rules.from_json pull.read_raw
        found.valid? ? found : Pickup.default
      rescue JSON::ParseException | JSON::SerializableError
        Pickup.default
      end

      def self.to_json(value : Rules, json : JSON::Builder) : Nil
        value.to_json json
      end
    end
  end
end
