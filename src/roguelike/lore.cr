require "json"
require "./item"
require "./regard"
require "./rng"

module Roguelike
  # What a run looks like, and what the character has found out about it.
  #
  # A potion is a colour until somebody drinks one. The colour is rolled per
  # run, so a swirly potion is the same thing all game and a different thing
  # in the next game. A person who learned the colours once would otherwise
  # never have to learn them again.
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
      VERR PRIRUTSENIE ANDOVA HACKEM MUCK VELOX NEB DAIYEN FOOLS XIXAXA
      XOXAXA GNIK SISI TEMOV FOOBIE BLETCH]

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

    # A copy that knows every kind.
    #
    # The screen a run ends with names what the character was carrying whether
    # or not they ever found out what it was. A person who died holding a wand
    # they never zapped is told what it was.
    def revealed : Lore
      Lore.new @appearances.dup, ItemKind.values.to_set
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
    # *blessing* false leaves the blessing word out, however much the
    # character knows. A line that has already said a thing is cursed does
    # not want to call it "a cursed dagger" as well.
    # *identified* true names the kind whether or not the character has found
    # it out, and teaches them nothing by it. A scroll that says what it
    # destroyed says what it was; it does not say what colour that kind comes
    # in for the rest of the run.
    # *regard* says how well the character has made the item out. Anything
    # short of `Regard::Everything` writes the kind and no more: "a spear"
    # rather than "a cursed -2 spear", and "a scroll" rather than "a scroll
    # labelled YLOH". The default makes everything out, so a caller that is
    # not about distance writes what it has always written.
    def name(item : Item, blessing : Bool = true,
             identified : Bool = false,
             regard : Regard = Regard::Everything) : String
      noun = noun_for item, blessing, identified, regard
      return "#{item.count} #{noun}" if item.count > 1
      return noun if item.kind.uncountable?

      "#{Lore.article noun} #{noun}"
    end

    # :ditto:, without the article or the count.
    def noun_for(item : Item, blessing : Bool = true,
                 identified : Bool = false,
                 regard : Regard = Regard::Everything) : String
      kind = item.kind
      plural = item.count > 1

      return Lore.bare_noun item, plural unless regard.everything?

      unless identified || known?(kind)
        return disguised_noun item, plural, blessing
      end

      words = [] of String
      words << item.blessing.label if blessing &&
                                      (identified || item.blessing_known?)
      words << (item.condition.label || "") unless item.condition.plain?
      words << Lore.enchantment(item.enchantment) unless item.enchantment.zero?
      words << (plural ? kind.plural : kind.label)

      words.reject(&.empty?).join ' '
    end

    # What an unidentified item is called.
    #
    # A known blessing still shows. A character can be told a potion is cursed
    # without being told what is in it.
    private def disguised_noun(item : Item, plural : Bool,
                               blessing : Bool = true) : String
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

      blessing && item.blessing_known? ? "#{item.blessing.label} #{noun}" : noun
    end

    # What *item* is called by somebody who made out its kind and no more.
    #
    #     spear
    #     scroll
    #     potion
    #
    # A thing that is what it looks like keeps its own name: a spear is a
    # spear from any distance, and so is chain mail. A potion, a wand and a
    # scroll are a bottle, a stick and a sheet until somebody is near enough
    # to read them, so each of those is called by its class.
    def self.bare_noun(item : Item, plural : Bool = false) : String
      kind = item.kind

      case kind.item_class
      when .potion? then plural ? "potions" : "potion"
      when .wand?   then plural ? "wands" : "wand"
      when .scroll? then plural ? "scrolls" : "scroll"
      else               plural ? kind.plural : kind.label
      end
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
