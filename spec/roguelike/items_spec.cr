require "../spec_helper"

Spectator.describe Roguelike::Items do
  alias Kind = Roguelike::ItemKind
  alias Condition = Roguelike::Condition

  def stream(seed : UInt64 = Playing::SEED) : Roguelike::Rng
    Roguelike::Rng.new(seed).derive "loot"
  end

  describe ".make" do
    it "makes the kind it is asked for" do
      item = described_class.make stream, Kind::LongSword

      expect(item.kind).to eq Kind::LongSword
    end

    it "leaves a potion plain" do
      rng = stream

      1_000.times do
        item = described_class.make rng, Kind::HealingPotion
        expect(item.enchantment).to eq 0
        expect(item.condition).to eq Condition::Plain
      end
    end

    it "gives a stack a count in its range" do
      rng = stream
      range = Roguelike::Items::STACKS[Kind::Arrow]

      200.times do
        count = described_class.make(rng, Kind::Arrow).count
        expect(count).to be >= range.begin
        expect(count).to be <= range.end
      end
    end

    it "makes one of anything that does not stack" do
      expect(described_class.make(stream, Kind::LongSword).count).to eq 1
    end
  end

  describe ".random" do
    # A run reproduces from its seed. A spec that rolls ten thousand items
    # twice gets the same ten thousand both times.
    it "rolls the same ten thousand items from the same seed" do
      first = Array.new(10_000) { described_class.random(stream(1_u64)).to_s }
      again = Array.new(10_000) { described_class.random(stream(1_u64)).to_s }

      expect(again).to eq first
    end

    it "rolls a different ten thousand from a different seed" do
      rng = stream
      other = stream Playing::SEED + 1

      first = Array.new(10_000) { described_class.random(rng).to_s }
      second = Array.new(10_000) { described_class.random(other).to_s }

      expect(second).not_to eq first
    end

    it "rolls every kind eventually" do
      rng = stream
      seen = Set(Kind).new
      20_000.times { seen << described_class.random(rng).kind }

      expect(seen.size).to eq Kind.values.size
    end

    it "rolls a plain item more often than any other condition" do
      rng = stream
      counts = Hash(Condition, Int32).new 0
      10_000.times do
        item = described_class.random rng
        counts[item.condition] += 1 if item.kind.enchantable?
      end

      expect(counts[Condition::Plain]).to be > counts[Condition::Damaged]
      expect(counts[Condition::Plain]).to be > counts[Condition::Masterwork]
    end

    it "rolls nothing more often than any plus" do
      rng = stream
      plain = 0
      enchanted = 0

      10_000.times do
        item = described_class.random rng
        next unless item.kind.enchantable?

        if item.enchantment.zero?
          plain += 1
        else
          enchanted += 1
        end
      end

      expect(plain).to be > enchanted
    end
  end

  describe ".pick" do
    it "never picks a weight of nothing" do
      rng = stream
      choices = { {:never, 0}, {:always, 5} }

      500.times { expect(described_class.pick(rng, choices)).to eq :always }
    end

    it "refuses a table that adds up to nothing" do
      expect { described_class.pick stream, { {:never, 0} } }
        .to raise_error ArgumentError, /nothing to pick/
    end

    it "picks each entry in proportion" do
      rng = stream
      counts = Hash(Symbol, Int32).new 0
      choices = { {:rare, 1}, {:common, 9} }

      10_000.times { counts[described_class.pick(rng, choices)] += 1 }

      expect(counts[:common]).to be > counts[:rare] * 5
    end
  end

  describe "the tables" do
    it "weights every kind" do
      Kind.each do |kind|
        expect(Roguelike::Items::WEIGHTS[kind]?).not_to be_nil
      end
    end

    it "weights every kind above nothing" do
      Roguelike::Items::WEIGHTS.each_value { |weight| expect(weight).to be > 0 }
    end

    it "gives a stack range to every kind that stacks and needs one" do
      Roguelike::Items::STACKS.each_key do |kind|
        expect(kind.stacks?).to be_true
      end
    end
  end
end
