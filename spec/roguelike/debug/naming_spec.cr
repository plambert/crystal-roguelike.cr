require "../../spec_helper"

Spectator.describe Roguelike::Debug do
  alias Blessing = Roguelike::Blessing
  alias Condition = Roguelike::Condition
  alias Debug = Roguelike::Debug
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind

  # What *text* names. Fails the example when it names nothing.
  def made(text : String) : Item
    found = Debug.item text.split
    raise found if found.is_a? String

    found
  end

  # Why *text* names nothing. Fails the example when it names something.
  def refused(text : String) : String
    found = Debug.item text.split
    raise "#{text} made #{found}" unless found.is_a? String

    found
  end

  describe ".kinds" do
    # A person who knows what a thing is called can type that and stop
    # guessing at abbreviations.
    it "reaches every kind by its own label" do
      Kind.values.each do |kind|
        expect(Debug.kinds kind.label.split).to contain kind
      end
    end

    it "reaches every kind by its member name" do
      Kind.values.each do |kind|
        expect(Debug.kinds [kind.to_s.downcase]).to eq [kind]
      end
    end

    it "reaches a kind by the starts of its words" do
      expect(Debug.kinds %w[sh sword]).to eq [Kind::ShortSword]
      expect(Debug.kinds %w[chain]).to eq [Kind::ChainMail]
    end

    # "potion of healing" has a word between the two that were typed.
    it "skips the words of a label that were not typed" do
      expect(Debug.kinds %w[pot heal]).to eq [Kind::HealingPotion]
      expect(Debug.kinds %w[scroll ident]).to eq [Kind::IdentifyScroll]
      expect(Debug.kinds %w[wand str]).to eq [Kind::StrikingWand]
    end

    it "answers every kind an abbreviation could mean" do
      expect(Debug.kinds(%w[s]).size).to be > 1
    end

    it "answers nothing for words that name nothing" do
      expect(Debug.kinds %w[trombone]).to be_empty
    end

    it "answers nothing for no words at all" do
      expect(Debug.kinds [] of String).to be_empty
    end
  end

  describe ".item" do
    it "makes a plain one from a name on its own" do
      item = made "bow"

      expect(item.kind).to eq Kind::Bow
      expect(item.enchantment).to eq 0
      expect(item.condition).to eq Condition::Plain
      expect(item.blessing).to eq Blessing::Uncursed
      expect(item.count).to eq 1
    end

    it "takes an enchantment" do
      expect(made("+1 bow").enchantment).to eq 1
      expect(made("-2 bow").enchantment).to eq -2
    end

    it "takes a condition" do
      expect(made("mwk sh sword").condition).to eq Condition::Masterwork
      expect(made("masterwork dagger").condition).to eq Condition::Masterwork
      expect(made("damaged dagger").condition).to eq Condition::Damaged
    end

    # A blessing nobody typed is not known. A blessing that was typed is: a
    # person who asked for a cursed sword is not being kept in suspense.
    it "takes a blessing, and leaves it known" do
      item = made "cursed chain mail"

      expect(item.blessing).to eq Blessing::Cursed
      expect(item.blessing_known?).to be_true
      expect(made("bow").blessing_known?).to be_false
    end

    it "takes a count" do
      expect(made("12 arrow").count).to eq 12
    end

    it "takes every part at once" do
      item = made "12 blessed mwk +2 arrow"

      expect(item.kind).to eq Kind::Arrow
      expect(item.count).to eq 12
      expect(item.blessing).to eq Blessing::Blessed
      expect(item.condition).to eq Condition::Masterwork
      expect(item.enchantment).to eq 2
    end

    it "sets a torch alight when it is asked to" do
      expect(made("lit torch").lit?).to be_true
      expect(made("torch").lit?).to be_false
    end

    it "says so when the words name nothing" do
      expect(refused "trombone").to contain "trombone"
    end

    it "says what an abbreviation could mean rather than choosing" do
      complaint = refused "s"

      expect(complaint).to contain "short sword"
      expect(complaint).to contain " or "
    end

    it "says so when it was given no words" do
      expect(refused "").to contain "what to make"
    end

    # Nothing here rolls, so opening the console during a run leaves every
    # stream of that run where it was.
    it "makes the same item every time" do
      expect(made("+1 bow")).to eq made("+1 bow")
    end
  end
end
