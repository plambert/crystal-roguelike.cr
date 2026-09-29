require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Replay::Export do
  alias Check = Roguelike::Replay::Check
  alias Export = Roguelike::Replay::Export
  alias Game = Roguelike::Game
  alias Rng = Roguelike::Rng

  # A file nothing else in this run of the specs writes to.
  def spot(name : String) : Path
    Recording.directory / "#{name}-#{Random.rand UInt32}.jsonl"
  end

  # A recorded run, written down the way this build writes one.
  def recorded(turns : Int32 = 60) : Path
    where = spot "exported"
    Recording.played where.to_s, turns: turns
    where
  end

  # Every line of what exporting *source* wrote.
  def exported(source : Path, legal : Bool = true) : Array(JSON::Any)
    held = IO::Memory.new
    Export.run source, held, legal: legal
    held.to_s.lines.map { |line| JSON.parse line }
  end

  describe "what it writes" do
    it "opens with where the pairs came from" do
      source = recorded
      opening = exported(source).first

      expect(opening["type"]).to eq "export"
      expect(opening["format"]).to eq Export::FORMAT
      expect(opening["seed"]).to eq Recording::SEED
      expect(opening["player"]).to eq Recording::PLAYER
      expect(opening["source"]).to eq "human"
      expect(opening["actions"].as_i).to be > 0
    end

    it "writes one pair per action, and a footer" do
      source = recorded
      lines = exported source

      pairs = lines.select { |line| line["type"] == "pair" }
      expect(pairs.size).to eq lines.first["actions"].as_i
      expect(lines.last["type"]).to eq "footer"
      expect(lines.last["pairs"].as_i).to eq pairs.size
    end

    it "writes the action that was recorded on that turn" do
      source = recorded
      lines = exported source

      recorded_acts = File.read_lines(source)
        .select(&.starts_with? %({"type":"act"))
        .map { |line| JSON.parse(line)["action"] }
      pairs = lines.select { |line| line["type"] == "pair" }

      expect(pairs.map &.["action"]).to eq recorded_acts
    end

    it "writes what the character knew before they acted" do
      source = recorded
      pair = exported(source).find! { |line| line["type"] == "pair" }

      expect(pair["obs"]["player"]["pos"]).not_to be_nil
      expect(pair["obs"]["map"]["rows"].as_a).not_to be_empty
      expect(pair["turn"].as_i).to eq pair["obs"]["turn"].as_i
    end

    it "writes the action among the actions that were legal" do
      source = recorded
      exported(source).each do |line|
        next unless line["type"] == "pair"

        expect(line["legal"].as_a).to contain line["action"]
      end
    end

    it "leaves the legal actions out when asked" do
      source = recorded
      pair = exported(source, legal: false).find! { |line| line["type"] == "pair" }

      expect(pair.as_h.has_key? "legal").to be_false
    end

    it "says how the run ended" do
      source = recorded
      lines = exported source

      expect(lines.last["outcome"]).to eq "truncated"
    end
  end

  describe "a run that no longer plays out the way it was recorded" do
    # A fingerprint this build does not take, in a file whose actions are
    # otherwise good. An export from one would be pairs from a run nobody
    # played, which is worse than no export.
    def staled(source : Path) : Path
      where = spot "stale"

      lines = File.read_lines(source).map do |line|
        next line unless line.starts_with? %({"type":"check")

        Check.new(Check.from_json(line).turn, "sha256:#{"0" * 64}").to_json
      end

      File.write where, lines.join('\n') + "\n"
      where
    end

    it "stops and names the turn" do
      source = staled recorded(turns: 80)
      held = IO::Memory.new
      report = Export.run source, held, legal: false

      expect(report.ok?).to be_false
      expect(report.trouble.to_s).to contain "the run differs"
      expect(report.trouble.to_s).to contain "replay verify"
    end

    it "stops where the header does not match" do
      source = recorded
      lines = File.read_lines source
      lines[0] = JSON.parse(lines[0]).as_h
        .merge({"state" => JSON::Any.new("sha256:#{"0" * 64}")}).to_json

      where = spot "wrong-header"
      File.write where, lines.join('\n') + "\n"

      report = Export.run where, IO::Memory.new
      expect(report.ok?).to be_false
      expect(report.trouble.to_s).to contain "does not start where"
    end
  end

  describe "the report" do
    it "counts the pairs and the turn the run reached" do
      source = recorded
      report = Export.run source, IO::Memory.new

      expect(report.ok?).to be_true
      expect(report.pairs).to be > 0
      expect(report.turn).to be > 0
      expect(report.to_s).to contain "exported #{report.pairs} pairs"
    end
  end
end
