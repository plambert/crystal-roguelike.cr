require "../spec_helper"
require "../support/recording"
require "../support/fixture"

Spectator.describe Roguelike::Replay::Dump do
  alias Check = Roguelike::Replay::Check
  alias Dump = Roguelike::Replay::Dump

  # A file nothing else in this run of the specs writes to.
  def spot(name : String) : Path
    Recording.directory / "#{name}-#{Random.rand UInt32}.jsonl"
  end

  # Everything dumping *source* wrote.
  def dumped(source : Path) : String
    held = IO::Memory.new
    Dump.run source, held
    held.to_s
  end

  describe "what it writes" do
    it "writes the messages of the golden replay with their turns" do
      text = dumped Recording.golden

      expect(text.chomp).to eq Fixture.expected("replay/golden-dump.txt", text.chomp)
    end

    it "starts every line with a turn and a tab" do
      dumped(Recording.golden).each_line do |line|
        expect(line).to match /\A\d+\t\S/
      end
    end

    it "writes the same lines every time" do
      expect(dumped Recording.golden).to eq dumped(Recording.golden)
    end

    it "reports the lines and the turn" do
      held = IO::Memory.new
      report = Dump.run Recording.golden, held

      expect(report.ok?).to be_true
      expect(report.lines).to eq held.to_s.lines.size
      expect(report.turn).to be > 0
      expect(report.to_s).to contain "dumped #{report.lines} messages"
    end
  end

  describe "a run that no longer plays out the way it was recorded" do
    # The golden replay with the fingerprint of its second checkpoint
    # replaced by one this build does not take.
    def corrupted : Path
      seen = 0
      lines = File.read_lines(Recording.golden).map do |line|
        next line unless line.starts_with? %({"type":"check")

        seen += 1
        next line unless seen == 2

        Check.new(Check.from_json(line).turn, "sha256:#{"0" * 64}").to_json
      end

      where = spot "corrupt"
      File.write where, lines.join('\n') + "\n"
      where
    end

    it "stops and names the turn" do
      report = Dump.run corrupted, IO::Memory.new

      expect(report.ok?).to be_false
      expect(report.trouble.to_s).to contain "the run differs"
      expect(report.trouble.to_s).to contain "replay verify"
    end

    it "writes only the lines before the checkpoint that disagrees" do
      held = IO::Memory.new
      Dump.run corrupted, held
      whole = dumped Recording.golden

      expect(held.to_s.size).to be < whole.size
      expect(whole).to start_with held.to_s
    end

    it "stops where the header does not match" do
      lines = File.read_lines Recording.golden
      lines[0] = JSON.parse(lines[0]).as_h
        .merge({"state" => JSON::Any.new("sha256:#{"0" * 64}")}).to_json

      where = spot "wrong-header"
      File.write where, lines.join('\n') + "\n"

      held = IO::Memory.new
      report = Dump.run where, held

      expect(report.ok?).to be_false
      expect(report.trouble.to_s).to contain "does not start where"
      expect(held.to_s).to be_empty
    end
  end
end
