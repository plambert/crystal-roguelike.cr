require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Replay::Upgrade do
  alias Check = Roguelike::Replay::Check
  alias Header = Roguelike::Replay::Header
  alias Log = Roguelike::Replay::Log
  alias Upgrade = Roguelike::Replay::Upgrade
  alias Verifier = Roguelike::Replay::Verifier

  # A file nothing else in this run of the specs writes to.
  def spot(name : String) : Path
    Recording.directory / "#{name}-#{Random.rand UInt32}.jsonl"
  end

  # A recorded run, written down the way this build writes one.
  def recorded : Path
    where = spot "recorded"
    Recording.played where.to_s, turns: 60
    where
  end

  # *source*, with its format and every fingerprint in it made wrong.
  #
  # This is the shape of a file an older build wrote. Its actions are good
  # and its fingerprints are values this build does not take.
  def staled(source : Path) : Path
    where = spot "stale"

    lines = File.read_lines(source).map do |line|
      next line if line.blank?

      case line
      when .starts_with? %({"type":"header")
        JSON.parse(line).as_h.merge({"format" => JSON::Any.new(1_i64),
                                     "state"  => JSON::Any.new("sha256:#{"0" * 64}")}).to_json
      when .starts_with? %({"type":"check")
        check = Check.from_json line
        Check.new(check.turn, "sha256:#{"0" * 64}").to_json
      else
        line
      end
    end

    File.write where, lines.join('\n') + "\n"
    where
  end

  # Every action of the file at *path*, as JSON.
  def actions(path : Path) : Array(String)
    Recording.read(path, fingerprints: false).records.compact_map do |record|
      record.as?(Roguelike::Replay::Act).try &.action.to_json
    end
  end

  # The header of the file at *path*.
  def header(path : Path) : Header
    Recording.read(path, fingerprints: false).header
  end

  # The footer of the file at *path*.
  def footer(path : Path) : Roguelike::Replay::Footer
    Recording.read(path, fingerprints: false).footer.as Roguelike::Replay::Footer
  end

  describe "a file this build refuses" do
    it "is refused before the upgrade and read after it" do
      stale = staled recorded
      expect(Verifier.check(stale).trouble).to match /format 1/

      target = spot "upgraded"
      expect(Upgrade.run(stale, target).ok?).to be_true
      expect(Verifier.check(target).ok?).to be_true
    end

    it "keeps every action as it was" do
      stale = staled recorded
      target = spot "upgraded"
      Upgrade.run stale, target

      expect(actions target).to eq actions(stale)
    end

    it "keeps the checkpoints on the turns they were on" do
      stale = staled recorded
      target = spot "upgraded"
      Upgrade.run stale, target

      turns = ->(path : Path) do
        Recording.read(path, fingerprints: false).records
          .compact_map { |record| record.as?(Check).try &.turn }
      end

      expect(turns.call target).to eq turns.call(stale)
    end

    it "writes the fingerprints this build takes" do
      stale = staled recorded
      target = spot "upgraded"
      Upgrade.run stale, target

      expect(header(target).state).to_not eq header(stale).state
      expect(header(target).format).to eq Roguelike::Replay::FORMAT
    end

    it "keeps the seed, the character and when the run was played" do
      stale = staled recorded
      target = spot "upgraded"
      Upgrade.run stale, target

      was = header stale
      now = header target

      expect(now.seed).to eq was.seed
      expect(now.player).to eq was.player
      expect(now.generate?).to eq was.generate?
      expect(now.source).to eq was.source
      expect(now.started_at).to eq was.started_at
    end

    it "keeps when the run ended" do
      stale = staled recorded
      target = spot "upgraded"
      Upgrade.run stale, target

      was = footer stale
      now = footer target

      expect(now.ended_at).to eq was.ended_at
      expect(now.turn).to eq was.turn
      expect(now.outcome).to eq was.outcome
    end

    it "reports the run it wrote" do
      stale = staled recorded
      target = spot "upgraded"
      report = Upgrade.run stale, target

      expect(report.acts).to eq Recording.read(stale, fingerprints: false).acts
      expect(report.path).to eq target
    end
  end

  describe "the settings it borrows" do
    it "puts every one of them back" do
      stale = staled recorded
      held = {Log.pattern, Log.every, Log.generate?, Log.source,
              Log.started_at, Log.ended_at}

      Upgrade.run stale, spot("upgraded")

      expect({Log.pattern, Log.every, Log.generate?, Log.source,
              Log.started_at, Log.ended_at}).to eq held
    end

    it "puts them back when the file does not read" do
      held = {Log.pattern, Log.started_at}

      expect { Upgrade.run spot("missing"), spot("upgraded") }
        .to raise_error File::Error

      expect({Log.pattern, Log.started_at}).to eq held
    end
  end

  describe "the checkpoint spacing" do
    it "takes the spacing the file was recorded with" do
      where = spot "every-ten"
      Roguelike::Replay::Log.every = 10
      begin
        Recording.played where.to_s, turns: 60
      ensure
        Roguelike::Replay::Log.every = Roguelike::Replay::Log::EVERY
      end

      read = Recording.read where, fingerprints: false
      expect(Upgrade.every_of read).to eq 10
    end

    # A three-turn action ran past turn 30, so the checkpoint due then was
    # written on turn 32 and the gap after it is 8.
    it "takes the commonest gap when an action ran past a checkpoint" do
      header = File.read_lines(Recording.golden).first
      checks = {10, 20, 32, 40, 50}.map do |turn|
        %({"type":"check","turn":#{turn},"state":"sha256:#{"0" * 64}"})
      end

      read = Recording.read Recording.file([header] + checks.to_a, "jumped"), fingerprints: false
      expect(Upgrade.every_of read).to eq 10
    end

    it "takes the setting in force for a file with one checkpoint" do
      read = Recording.read Recording.golden
      expect(Upgrade.every_of read).to eq Log.every if read.checks < 2
    end
  end
end
