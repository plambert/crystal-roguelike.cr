require "../item"
require "../item_kind"

module Roguelike
  # The debug console and what it runs.
  #
  # Nothing here is reachable in a normal run. `--debug-console` builds the
  # panel and binds the key that opens it. Without the flag the panel is never
  # made and the key is never bound.
  module Debug
    # The words that name a blessing.
    BLESSINGS = {
      "cursed"   => Blessing::Cursed,
      "uncursed" => Blessing::Uncursed,
      "blessed"  => Blessing::Blessed,
    }

    # The words that name a condition. "mwk" is what a person types.
    CONDITIONS = {
      "damaged"    => Condition::Damaged,
      "plain"      => Condition::Plain,
      "masterwork" => Condition::Masterwork,
      "mwk"        => Condition::Masterwork,
    }

    # The word that sets a torch or a candle alight.
    ALIGHT = "lit"

    # What *words* name, or a sentence saying why they name nothing.
    #
    # The parts come in this order and each one may be left out:
    #
    #     [count] [blessing] [condition] [+N] [lit] <kind>
    #
    # So `+1 bow`, `mwk sh sword`, `12 +1 arrow`, `cursed chain mail`,
    # `lit torch` and `pot heal` all name something.
    #
    # Nothing here rolls. An enchantment nobody typed is zero rather than one
    # drawn from `Items::ENCHANTMENTS`, so spawning an item leaves every
    # stream of the run where it was.
    def self.item(words : Array(String)) : Item | String
      left = words.map &.downcase
      return "say what to make." if left.empty?

      count = take_count left
      blessing = take BLESSINGS, left
      condition = take CONDITIONS, left
      enchantment = take_enchantment left
      lit = take_alight left

      found = kinds left
      return "nothing is called #{left.join ' '}." if found.empty?
      return "#{left.join ' '} could be #{listed found}." if found.size > 1

      Item.new found.first, enchantment || 0, condition || Condition::Plain,
        count || 1, blessing: blessing || Blessing::Uncursed,
        blessing_known: !blessing.nil?, lit: lit
    end

    # Every kind *words* could name.
    #
    # A kind matches when its member name with the spaces taken out is exactly
    # what was typed, so `shortsword` names one thing. It also matches when
    # each word in turn is the start of a later word of its label, so
    # `sh sword` names a short sword and `pot heal` a potion of healing.
    def self.kinds(words : Array(String)) : Array(ItemKind)
      return [] of ItemKind if words.empty?

      joined = words.join
      exact = ItemKind.values.select do |kind|
        kind.to_s.downcase == joined || kind.label.delete(' ') == joined
      end
      return exact unless exact.empty?

      ItemKind.values.select { |kind| abbreviates? words, kind.label }
    end

    # Whether *words* are the starts of words of *label*, in order.
    #
    # Words of the label between them are skipped, which is what lets
    # `pot heal` reach "potion of healing".
    private def self.abbreviates?(words : Array(String), label : String) : Bool
      rest = label.split ' '

      words.each do |word|
        found = rest.index &.starts_with?(word)
        return false unless found

        rest = rest[(found + 1)..]
      end

      true
    end

    # The leading count, taken off *words*. `nil` when there is none.
    #
    # A signed number is the enchantment rather than the count. `+1 bow` is
    # one enchanted bow, not one plain one.
    private def self.take_count(words : Array(String)) : Int32?
      word = words.first?
      return if !word || word.starts_with?('+') || word.starts_with?('-')

      found = word.to_i?
      return unless found && found > 0

      words.shift
      found
    end

    # The value *table* gives the first of *words*, taken off it.
    private def self.take(table, words : Array(String))
      found = words.first?.try { |word| table[word]? }
      words.shift if found

      found
    end

    # The leading `+N` or `-N`, taken off *words*. `nil` when there is none.
    private def self.take_enchantment(words : Array(String)) : Int32?
      word = words.first?
      return unless word && (word.starts_with?('+') || word.starts_with?('-'))

      found = word.to_i?
      return unless found

      words.shift
      found
    end

    # Whether `lit` leads *words*, taken off it.
    private def self.take_alight(words : Array(String)) : Bool
      return false unless words.first? == ALIGHT

      words.shift
      true
    end

    # *found* as a sentence: `a, b or c`.
    def self.listed(found : Array(ItemKind)) : String
      labels = found.map &.label
      return labels.join if labels.size <= 1

      "#{labels[0..-2].join ", "} or #{labels[-1]}"
    end
  end
end
