require "../spec_helper"

Spectator.describe Roguelike::Lore do
  alias Kind = Roguelike::ItemKind
  alias Item = Roguelike::Item
  alias Condition = Roguelike::Condition

  subject(lore) { described_class.roll Roguelike::Rng.new(Playing::SEED) }

  describe ".roll" do
    it "gives every disguised kind a look" do
      Kind.each do |kind|
        next unless kind.disguised?

        expect(lore.appearance(kind)).not_to be_nil
      end
    end

    it "gives nothing else one" do
      expect(lore.appearance(Kind::LongSword)).to be_nil
    end

    # A swirly potion is the same thing all game. A person who learned the
    # colours once would never have to learn them again, so the next game
    # gives different ones.
    it "gives the same looks for the same seed" do
      again = described_class.roll Roguelike::Rng.new(Playing::SEED)

      expect(again.appearances).to eq lore.appearances
    end

    it "gives different looks for a different seed" do
      other = described_class.roll Roguelike::Rng.new(Playing::SEED + 1)

      expect(other.appearances).not_to eq lore.appearances
    end

    # The stream is derived by name, so the looks do not depend on what
    # anything else rolled first.
    it "gives the same looks however much the run has rolled" do
      rng = Roguelike::Rng.new Playing::SEED
      1_000.times { rng.rand 100 }

      expect(described_class.roll(rng).appearances).to eq lore.appearances
    end

    # A person who drank one swirly potion would be told the other kind was
    # identified too.
    it "gives every disguised kind a look of its own" do
      looks = Kind.values.compact_map { |kind| lore.appearance kind }

      expect(looks.uniq.size).to eq looks.size
    end

    it "has enough looks for every kind it has to disguise" do
      {
        {Roguelike::ItemClass::Potion, Roguelike::Lore::POTION_LOOKS},
        {Roguelike::ItemClass::Wand, Roguelike::Lore::WAND_LOOKS},
        {Roguelike::ItemClass::Scroll, Roguelike::Lore::SCROLL_LOOKS},
      }.each do |item_class, pool|
        expect(pool.size).to be >= Kind.of_class(item_class).size
      end
    end
  end

  describe "#revealed" do
    it "knows every kind" do
      known = lore.revealed

      expect(Kind.values.all? { |kind| known.known? kind }).to be_true
    end

    it "names a potion nobody drank" do
      expect(lore.name Item.new(Kind::HealingPotion)).not_to contain "healing"
      expect(lore.revealed.name Item.new(Kind::HealingPotion))
        .to eq "a potion of healing"
    end

    it "leaves the lore it was made from alone" do
      lore.revealed

      expect(lore.known?(Kind::HealingPotion)).to be_false
    end

    it "keeps the appearances" do
      expect(lore.revealed.appearances).to eq lore.appearances
    end
  end

  describe "#known?" do
    it "knows a sword on sight" do
      expect(lore.known?(Kind::LongSword)).to be_true
    end

    it "does not know a potion until somebody drinks one" do
      expect(lore.known?(Kind::HealingPotion)).to be_false

      lore.learn Kind::HealingPotion
      expect(lore.known?(Kind::HealingPotion)).to be_true
    end

    it "learns nothing twice" do
      expect(lore.learn(Kind::HealingPotion)).to be_true
      expect(lore.learn(Kind::HealingPotion)).to be_false
    end

    it "learns nothing about a kind nobody has to find out" do
      expect(lore.learn(Kind::LongSword)).to be_false
    end

    # Identification is per kind. Drinking one swirly potion names every
    # swirly potion.
    it "names every potion of that kind once one is learned" do
      lore.learn Kind::HealingPotion

      expect(lore.name(Item.new(Kind::HealingPotion))).to eq "a potion of healing"
      expect(lore.name(Item.new(Kind::HealingPotion, count: 3)))
        .to eq "3 potions of healing"
    end
  end

  describe "#name" do
    it "names a plain item" do
      expect(lore.name(Item.new(Kind::Dagger))).to eq "a dagger"
    end

    it "puts the condition before the noun" do
      expect(lore.name(Item.new(Kind::ShortSword, 0, Condition::Damaged)))
        .to eq "a damaged short sword"
    end

    it "puts the condition before the plus" do
      expect(lore.name(Item.new(Kind::ChainMail, 1, Condition::Masterwork)))
        .to eq "masterwork +1 chain mail"
    end

    it "writes a penalty with its sign" do
      expect(lore.name(Item.new(Kind::Dagger, -1))).to eq "a -1 dagger"
    end

    it "counts a stack and drops the article" do
      expect(lore.name(Item.new(Kind::Arrow, count: 12))).to eq "12 arrows"
    end

    it "names one of a stack in the singular" do
      expect(lore.name(Item.new(Kind::Arrow, count: 1))).to eq "an arrow"
    end

    describe "a blessing" do
      it "says nothing while the character does not know" do
        cursed = Item.new Kind::Dagger, blessing: Roguelike::Blessing::Cursed

        expect(lore.name(cursed)).to eq "a dagger"
      end

      it "goes first, before the condition and the plus" do
        item = Item.new Kind::LongSword, 1, Condition::Masterwork,
          blessing: Roguelike::Blessing::Blessed, blessing_known: true

        expect(lore.name(item)).to eq "a blessed masterwork +1 long sword"
      end

      it "says uncursed once the character knows" do
        item = Item.new Kind::Dagger, blessing_known: true

        expect(lore.name(item)).to eq "an uncursed dagger"
      end

      it "counts a cursed stack" do
        arrows = Item.new Kind::Arrow, count: 5,
          blessing: Roguelike::Blessing::Cursed, blessing_known: true

        expect(lore.name(arrows)).to eq "5 cursed arrows"
      end

      # A character can be told a potion is cursed without being told what is
      # in it.
      it "shows on an item the character has not identified" do
        look = lore.appearance Kind::HealingPotion
        potion = Item.new Kind::HealingPotion,
          blessing: Roguelike::Blessing::Cursed, blessing_known: true

        expect(lore.name(potion)).to eq "a cursed #{look} potion"
      end

      it "shows on an uncountable noun with no article" do
        mail = Item.new Kind::ChainMail, blessing: Roguelike::Blessing::Blessed,
          blessing_known: true

        expect(lore.name(mail)).to eq "blessed chain mail"
      end
    end

    describe "the article" do
      it "is a before a consonant" do
        expect(lore.name(Item.new(Kind::Dagger))).to start_with "a "
        expect(lore.name(Item.new(Kind::Mace))).to start_with "a "
      end

      it "is an before a vowel" do
        expect(lore.name(Item.new(Kind::Arrow))).to start_with "an "
      end

      # The letter is not the sound. "uncursed" takes "an" and "unicorn"
      # would take "a".
      it "follows the sound rather than the letter" do
        expect(described_class.article("uncursed dagger")).to eq "an"
        expect(described_class.article("unicorn horn")).to eq "a"
        expect(described_class.article("one-handed sword")).to eq "a"
        expect(described_class.article("arrow")).to eq "an"
        expect(described_class.article("")).to eq "a"
      end

      # "chain mail" is a substance and "boots" is a pair. Neither takes one.
      it "is nothing at all before an uncountable noun" do
        expect(lore.name(Item.new(Kind::ChainMail))).to eq "chain mail"
        expect(lore.name(Item.new(Kind::Boots))).to eq "boots"
        expect(lore.name(Item.new(Kind::LeatherArmour))).to eq "leather armour"
        expect(lore.name(Item.new(Kind::Gloves))).to eq "gloves"
      end

      it "is still nothing with a condition on it" do
        expect(lore.name(Item.new(Kind::Boots, 0, Condition::Damaged)))
          .to eq "damaged boots"
      end
    end

    describe "a disguised item" do
      it "names a potion by its look" do
        look = lore.appearance Kind::HealingPotion

        expect(lore.name(Item.new(Kind::HealingPotion))).to eq "a #{look} potion"
      end

      it "names a wand by what it is made of" do
        look = lore.appearance Kind::LightWand

        expect(lore.name(Item.new(Kind::LightWand))).to eq "a #{look} wand"
      end

      it "names a scroll by what is written on it" do
        look = lore.appearance Kind::IdentifyScroll

        expect(lore.name(Item.new(Kind::IdentifyScroll)))
          .to eq "a scroll #{look}"
      end

      it "counts a stack of them" do
        look = lore.appearance Kind::HealingPotion

        expect(lore.name(Item.new(Kind::HealingPotion, count: 2)))
          .to eq "2 #{look} potions"
      end

      it "never says what it is before the character finds out" do
        expect(lore.name(Item.new(Kind::HealingPotion))).not_to contain "healing"
      end
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      lore.learn Kind::HealingPotion
      again = described_class.from_json lore.to_json

      expect(again.appearances).to eq lore.appearances
      expect(again.known?(Kind::HealingPotion)).to be_true
      expect(again.known?(Kind::LightWand)).to be_false
    end
  end

  describe "the game" do
    it "rolls its looks from its own seed" do
      run = Playing.open

      expect(run.game.lore.appearance(Kind::HealingPotion)).not_to be_nil
    end

    it "names an item the way the character would" do
      run = Playing.open

      expect(run.game.name(Item.new(Kind::Dagger))).to eq "a dagger"
    end

    it "keeps its looks through a save" do
      run = Playing.open
      again = Roguelike::Game.from_json run.game.to_json

      expect(again.lore.appearances).to eq run.game.lore.appearances
    end
  end
end
