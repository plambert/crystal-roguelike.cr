require "json"
require "./item"
require "./rng"

module Roguelike
  # What a run looks like, and what the character has found out about it.
  #
  # A potion is a colour until somebody drinks one. The colour is rolled per
  # run, so a swirly potion is the same thing all game and a different thing
  # in the next game. That is the whole point of the disguise. A person who
  # learned the colours once would never have to learn them again.
  #
  # Identification is per kind. Drinking one swirly potion names every swirly
  # potion.
  class Lore
    include JSON::Serializable

    # The stream the appearances are rolled from.
    DOMAIN = "appearance"

    # What a potion looks like before anybody drinks one.
    POTION_LOOKS = %w[swirly murky bubbling fizzy cloudy smoky golden silver
      ruby emerald inky pearly milky dark bright]

    # What a wand is made of.
    WAND_LOOKS = %w[oak iron glass bone silver crystal ebony copper bronze
      walnut brass tin]

    # What is written on a scroll.
    SCROLL_LOOKS = %w[ZELGO MER JUYED GARVEN THARR VENZAR KIRJE ELBIB YLOH
      VERR PRIRUTSENIE ANDOVA]

    # What each disguised kind looks like this run.
    getter appearances : Hash(ItemKind, String)

    # Which kinds the character has found out.
    getter known : Set(ItemKind)

    def initialize(@appearances : Hash(ItemKind, String) = {} of ItemKind => String,
                   @known : Set(ItemKind) = Set(ItemKind).new)
    end

    # Rolls the appearances for a run on *rng*.
    #
    # The stream is derived by name, so the appearances do not depend on what
    # anything else rolled first.
    def self.roll(rng : Rng) : Lore
      stream = rng.derive DOMAIN
      table = {} of ItemKind => String

      {
        {ItemClass::Potion, POTION_LOOKS},
        {ItemClass::Wand, WAND_LOOKS},
        {ItemClass::Scroll, SCROLL_LOOKS},
      }.each do |item_class, pool|
        kinds = ItemKind.of_class item_class
        if kinds.size > pool.size
          raise ArgumentError.new "#{item_class} has #{kinds.size} kinds and " \
                                  "#{pool.size} looks to disguise them with"
        end

        looks = pool.shuffle stream
        kinds.each_with_index { |kind, index| table[kind] = looks[index] }
      end

      new table
    end

    # What *kind* looks like. `nil` for a kind nobody has to find out.
    def appearance(kind : ItemKind) : String?
      @appearances[kind]?
    end

    # Whether the character knows what *kind* is.
    #
    # A kind nobody has to find out is known from the start.
    def known?(kind : ItemKind) : Bool
      return true unless kind.disguised?

      @known.includes? kind
    end

    # Records that the character has found out what *kind* is. Answers whether
    # that was news.
    def learn(kind : ItemKind) : Bool
      return false unless kind.disguised?
      return false if @known.includes? kind

      @known << kind
      true
    end

    # What *item* is called.
    #
    #     a damaged short sword
    #     a blessed masterwork +1 chain mail
    #     3 cursed arrows
    #     a swirly potion
    #     a potion of healing
    def name(item : Item) : String
      noun = noun_for item
      return "#{item.count} #{noun}" if item.count > 1
      return noun if item.kind.uncountable?

      "#{Lore.article noun} #{noun}"
    end

    # :ditto:, without the article or the count.
    def noun_for(item : Item) : String
      kind = item.kind
      plural = item.count > 1

      unless known? kind
        return disguised_noun item, plural
      end

      words = [] of String
      words << item.blessing.label if item.blessing_known?
      words << (item.condition.label || "") unless item.condition.plain?
      words << Lore.enchantment(item.enchantment) unless item.enchantment.zero?
      words << (plural ? kind.plural : kind.label)

      words.reject(&.empty?).join ' '
    end

    # What an unidentified item is called.
    #
    # A known blessing still shows. A character can be told a potion is cursed
    # without being told what is in it.
    private def disguised_noun(item : Item, plural : Bool) : String
      kind = item.kind
      look = appearance kind
      noun = if look
               case kind.item_class
               when .potion? then plural ? "#{look} potions" : "#{look} potion"
               when .wand?   then plural ? "#{look} wands" : "#{look} wand"
               when .scroll? then plural ? "scrolls labelled #{look}" : "scroll labelled #{look}"
               else               plural ? kind.plural : kind.label
               end
             else
               plural ? kind.plural : kind.label
             end

      item.blessing_known? ? "#{item.blessing.label} #{noun}" : noun
    end

    # `+1`, `-2`, and so on.
    def self.enchantment(amount : Int32) : String
      amount > 0 ? "+#{amount}" : amount.to_s
    end

    # Words that start with a vowel letter and take `a` anyway.
    #
    # The letter is not the sound. "unicorn" and "one-handed" both start with
    # a consonant sound. The list is short because the catalogue is short, and
    # a word added to one is added to the other.
    CONSONANT_SOUNDS = %w[uni use uso eu one]

    # `a` or `an`, by the sound *noun* starts with.
    def self.article(noun : String) : String
      word = noun.downcase
      first = word[0]?
      return "a" unless first
      return "a" unless "aeiou".includes? first
      return "a" if CONSONANT_SOUNDS.any? { |sound| word.starts_with? sound }

      "an"
    end
  end
end
