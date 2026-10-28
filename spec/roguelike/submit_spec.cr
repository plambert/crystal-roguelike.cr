require "http/server"
require "../spec_helper"
require "../support/recording"

# A server on localhost that plays the upload protocol and remembers what it
# was sent. The first request is answered with a form that points back here,
# so the whole exchange stays in the process.
class FakeUploadServer
  # The JSON bodies of the requests for a form, in order.
  getter asked = [] of JSON::Any

  # The form fields each upload carried, in order.
  getter forms = [] of Hash(String, String)

  # The bytes each upload carried, by the key the form named.
  getter uploads = {} of String => Bytes

  # Whether to refuse every request for a form.
  property? refuse : Bool = false

  # The kinds to answer 400 for, the way a server that does not know them
  # does.
  property unknown = [] of String

  getter port : Int32

  def initialize
    @server = HTTP::Server.new { |context| handle context }
    @port = @server.bind_tcp("127.0.0.1", 0).port
    spawn { @server.listen }
  end

  def url : String
    "http://127.0.0.1:#{@port}/"
  end

  def close : Nil
    @server.close
  end

  private def handle(context : HTTP::Server::Context) : Nil
    request = context.request
    response = context.response

    if request.method == "POST" && request.path == "/"
      body = JSON.parse request.body.try(&.gets_to_end) || ""
      @asked << body

      if refuse?
        response.status_code = 403
        response.print %({"error": "bad token"})
        return
      end

      if @unknown.includes? body["kind"].as_s
        response.status_code = 400
        response.print %({"error": "bad kind"})
        return
      end

      key = "#{body["version"]}/#{body["log"]}/#{body["seq"].as_i.to_s.rjust 3, '0'}-#{body["kind"]}"
      response.content_type = "application/json"
      response.print({
        url:     "http://127.0.0.1:#{@port}/bucket",
        fields:  {"key" => key, "policy" => "p", "x-amz-signature" => "s"},
        key:     key,
        expires: 300,
      }.to_json)
    elsif request.method == "POST" && request.path == "/bucket"
      fields = {} of String => String
      file = Bytes.empty

      HTTP::FormData.parse(request) do |part|
        if part.name == "file"
          file = part.body.getb_to_end
        else
          fields[part.name] = part.body.gets_to_end
        end
      end

      @forms << fields
      @uploads[fields["key"]] = file
      response.status_code = 204
    else
      response.status_code = 404
    end
  end
end

class FailingParcelFilesystem < Roguelike::Submit::Parcel::Filesystem
  property mode : Symbol?
  getter failed = [] of Symbol

  def rename(source : Path, target : Path) : Nil
    if failure = injected_failure(source, target)
      @failed << failure
      raise IO::Error.new("injected #{failure} failure")
    end

    super
  end

  private def injected_failure(source : Path, target : Path) : Symbol?
    if @mode == :publish || @mode == :rollback
      return :publish if stage_meta?(source, target) && !@failed.includes?(:publish)
    end
    if @mode == :rollback
      :rollback if backup_replay?(source, target) && !@failed.includes?(:rollback)
    end
  end

  private def stage_meta?(source : Path, target : Path) : Bool
    source.parent.basename.includes?("parcel-stage") && target.basename == "meta.json"
  end

  private def backup_replay?(source : Path, target : Path) : Bool
    source.parent.basename.includes?("parcel-backup") && target.basename == "replay.jsonl.gz"
  end
end

class ReentrantParcelFilesystem < Roguelike::Submit::Parcel::Filesystem
  getter reader : Roguelike::Submit::Parcel?

  def initialize(@directory : Path)
    @reader = nil
  end

  def rename(source : Path, target : Path) : Nil
    super
    if source.parent.basename.includes?("parcel-stage") &&
       source.basename == "replay.jsonl.gz" && target.parent == @directory
      @reader = Roguelike::Submit::Parcel.open(@directory)
    end
  end
end

class RecordingParcelCarrier
  include Roguelike::Submit::Outbox::Carrier

  getter sent = 0

  def send(parcel : Roguelike::Submit::Parcel) : Nil
    @sent += 1
  end
end

Spectator.describe Roguelike::Submit do
  alias Submit = Roguelike::Submit
  alias Log = Roguelike::Replay::Log
  alias Replay = Roguelike::Replay
  alias Save = Roguelike::Save
  alias Game = Roguelike::Game
  alias Tester = Roguelike::Tester

  # A directory nothing else writes to.
  def root : Path
    made = Recording.directory / "submit-#{Random.rand UInt32}"
    Dir.mkdir_p made
    made
  end

  # Runs *block* with an outbox under *root*, and takes it away after.
  def sending(root : Path, & : Submit::Outbox -> Nil) : Nil
    outbox = Submit::Outbox.new root / "outbox"
    Submit.outbox = outbox
    yield outbox
  ensure
    Submit.outbox = nil
  end

  # The one log file in *directory*.
  def log_in(directory : Path) : Path
    found = Dir.children(directory).select(&.ends_with? ".jsonl")
    expect(found.size).to eq(1)
    directory / found.first
  end

  # The text in a gzipped parcel piece.
  def unpack(path : Path) : String
    File.open(path) do |file|
      Compress::Gzip::Reader.open(file, &.gets_to_end)
    end
  end

  # The names and bytes directly inside *directory*.
  def contents(directory : Path) : Hash(String, String)
    Dir.children(directory).sort.map do |name|
      {name, File.read(directory / name)}
    end.to_h
  end

  # A replay header with its type field last.
  def type_last(header : Replay::Header) : String
    header.to_json.sub(%({"type":"header",), "{")
      .sub(/\}\z/, %(,"type":"header"}))
  end

  describe ".log_id" do
    it "is 32 hex digits taken from the header, the same for the same file" do
      where = root
      Recording.played (where / "logs").tap { |dir| Dir.mkdir_p dir }.to_s, turns: 3
      path = log_in where / "logs"

      first = Submit.log_id path
      expect(first).to match(/\A[0-9a-f]{32}\z/)
      expect(Submit.log_id path).to eq(first)
    end

    it "differs between two runs" do
      where = root
      Recording.played (where / "a").tap { |dir| Dir.mkdir_p dir }.to_s, turns: 3
      Recording.played (where / "b").tap { |dir| Dir.mkdir_p dir }.to_s, turns: 3, seed: 99_u64

      expect(Submit.log_id log_in(where / "a")).not_to eq(Submit.log_id log_in(where / "b"))
    end
  end

  describe Submit::Meta do
    it "describes the run and names the build" do
      game = Roguelike::Game.dug Roguelike::Rng.new(Recording::SEED)
      game.player.name = "tester"
      meta = Submit::Meta.of game, "ab" * 16

      expect(meta.version).to eq(Roguelike::VERSION)
      expect(meta.platform).to eq(Submit::PLATFORM)
      expect(meta.platform).to match(/\A[a-z0-9]+-[a-z0-9_]+\z/)
      expect(meta.outcome).to eq("playing")
      expect(meta.seed).to eq(Recording::SEED)
      expect(meta.character).to eq("tester")
      expect(meta.turn).to eq(game.turn)

      again = Submit::Meta.from_json meta.to_json
      expect(again.log).to eq("ab" * 16)
    end

    it "includes the tester identity when one is set" do
      previous = Tester.current
      Tester.current = Tester.new "12345678-1234-1234-1234-123456789abc", "playtester"
      game = Game.dug Roguelike::Rng.new(Recording::SEED)
      meta = Submit::Meta.of game, "ab" * 16

      expect(meta.tester.try(&.name)).to eq("playtester")
      expect(meta.tester.try(&.id)).to eq("12345678-1234-1234-1234-123456789abc")
    ensure
      Tester.current = previous
    end
  end

  describe Submit::Parcel do
    it "packs gzipped copies and reads back by name" do
      where = root
      log = where / "run.jsonl"
      save = where / "run.json"
      File.write log, "{\"type\":\"header\"}\n{\"type\":\"act\"}\n{\"type\":\"act\""
      game = Game.dug Roguelike::Rng.new(7_u64)
      game.player.name = "x"
      held = Save::Held.new "x", Roguelike::VERSION, Time.utc, 4,
        game.player.level, game.outcome, game
      File.write save, held.to_pretty_json
      meta = Submit::Meta.new "0.0.1", "test-x", "playing", 4, 7_u64, "x", "cd" * 16

      parcel = Submit::Parcel.pack where / Submit::Parcel.name(meta, 3), meta, 3, log, save

      expect(parcel.directory.basename).to eq("#{"cd" * 16}-003")
      expect(parcel.pieces.map(&.kind)).to eq(["replay", "save", "meta"])

      unpacked = File.open(parcel.directory / "replay.jsonl.gz") do |file|
        Compress::Gzip::Reader.open(file, &.gets_to_end)
      end
      expect(unpacked).to eq(File.read log)

      opened = Submit::Parcel.open parcel.directory
      expect(opened.try(&.seq)).to eq(3)
      expect(opened.try(&.meta.log)).to eq("cd" * 16)

      parcel.remove
      expect(Dir.exists? parcel.directory).to be_false
    end

    it "does not publish a parcel when the replay source is missing" do
      where = root
      meta = Submit::Meta.new "0.0.1", "test-x", "playing", 4, 7_u64,
        "x", "cd" * 16
      outbox = Submit::Outbox.new where / "outbox"

      expect_raises(File::Error) do
        outbox.pack meta, 1, where / "missing.jsonl", nil
      end

      expect(outbox.parcels).to be_empty
      expect(Dir.children(outbox.directory).select(&.includes? "parcel-stage")).to be_empty
    end

    it "cleans staging after save or events packaging fails" do
      where = root
      log = where / "run.jsonl"
      bad_save = where / "bad-save.json"
      File.write log, "{}\n"
      File.write bad_save, "not a save"
      meta = Submit::Meta.new "0.0.1", "test-x", "playing", 4, 7_u64,
        "x", "cd" * 16
      outbox = Submit::Outbox.new where / "outbox"

      expect_raises(JSON::ParseException) do
        outbox.pack meta, 1, log, bad_save
      end
      expect(outbox.parcels).to be_empty
      expect(Dir.children(outbox.directory).select(&.includes? "parcel-stage")).to be_empty

      save = where / "save.json"
      game = Game.dug Roguelike::Rng.new(7_u64)
      held = Save::Held.new "x", Roguelike::VERSION, Time.utc, 4,
        game.player.level, game.outcome, game
      File.write save, held.to_pretty_json
      events = where / "missing.events.jsonl.gz"
      events_meta = Submit::Meta.new "0.0.1", "test-x", "playing", 4,
        7_u64, "x", "cd" * 16, events: true

      expect_raises(File::Error) do
        outbox.pack events_meta, 2, log, save, events
      end
      expect(outbox.parcels).to be_empty
      expect(Dir.children(outbox.directory).select(&.includes? "parcel-stage")).to be_empty
    end

    it "ignores staging directories even when they hold complete files" do
      where = root
      log = where / "run.jsonl"
      File.write log, "{}\n"
      meta = Submit::Meta.new "0.0.1", "test-x", "playing", 4, 7_u64,
        "x", "cd" * 16
      outbox = Submit::Outbox.new where / "outbox"
      parcel = outbox.pack meta, 1, log, nil
      staging = outbox.directory / ".#{parcel.directory.basename}.parcel-stage-test-owned"
      Dir.mkdir staging
      parcel.pieces.each { |piece| File.copy piece.path, staging / piece.path.basename }

      expect(outbox.parcels.map(&.seq)).to eq([1])
      expect(Submit::Parcel.open staging).to be_nil
    end

    it "opens valid legacy parcels without an events flag" do
      where = root
      logs = where / "logs"
      Dir.mkdir_p logs
      Recording.played logs.to_s, turns: 3
      legacy_log = log_in logs
      log_id = Submit.log_id legacy_log
      directory = where / "#{log_id}-001"
      Dir.mkdir_p directory
      meta = {
        "version"   => "0.5.0",
        "platform"  => "test-x",
        "outcome"   => "won",
        "turn"      => 4,
        "seed"      => 7_u64,
        "character" => "x",
        "log"       => log_id,
      }
      File.write directory / "meta.json", meta.to_json
      File.open(directory / "replay.jsonl.gz", "w") do |file|
        Compress::Gzip::Writer.open(file) { |gzip| gzip << File.read(legacy_log) }
      end

      parcel = Submit::Parcel.open directory

      expect(parcel.try(&.meta.events?)).to be_false
      expect(parcel.try(&.pieces.map(&.kind))).to eq(["replay", "meta"])
    end

    it "rejects missing, malformed and inconsistent required pieces" do
      where = root
      log = where / "run.jsonl"
      File.write log, "{}\n"
      meta = Submit::Meta.new "0.0.1", "test-x", "playing", 4, 7_u64,
        "x", "cd" * 16

      missing_replay = Submit::Parcel.pack where / "missing-replay-001", meta, 1, log, nil
      File.delete missing_replay.directory / "replay.jsonl.gz"
      expect(Submit::Parcel.open missing_replay.directory).to be_nil

      malformed_replay = Submit::Parcel.pack where / "malformed-replay-001", meta, 1, log, nil
      File.write malformed_replay.directory / "replay.jsonl.gz", "not gzip"
      expect(Submit::Parcel.open malformed_replay.directory).to be_nil

      malformed_meta = Submit::Parcel.pack where / "malformed-meta-001", meta, 1, log, nil
      File.write malformed_meta.directory / "meta.json", "not json"
      expect(Submit::Parcel.open malformed_meta.directory).to be_nil

      inconsistent = Submit::Parcel.pack where / "inconsistent-001", meta, 1, log, nil
      File.open(inconsistent.directory / "events.jsonl.gz", "w") do |file|
        Compress::Gzip::Writer.open(file, &.print("{}\n"))
      end
      expect(Submit::Parcel.open inconsistent.directory).to be_nil

      game = Game.dug Roguelike::Rng.new(7_u64)
      held = Save::Held.new "x", Roguelike::VERSION, Time.utc, 4,
        game.player.level, game.outcome, game
      save = where / "save.json"
      File.write save, held.to_pretty_json
      outbox = Submit::Outbox.new where / "saved-outbox"
      saved = outbox.pack meta, 1, log, save
      opened = Submit::Parcel.open(saved.directory) || raise "the saved parcel did not open"
      File.delete saved.directory / "save.json.gz"

      expect(Submit::Parcel.open(saved.directory)).to be_nil
      expect(outbox.parcels).to be_empty
      carrier = RecordingParcelCarrier.new
      outbox.flush carrier, IO::Memory.new
      expect(carrier.sent).to eq(0)
      expect_raises(IO::Error) { opened.pieces }
    end

    it "keeps a complete parcel after final-save packaging fails" do
      where = root
      log = where / "run.jsonl"
      save = where / "save.json"
      events = where / "run.events.jsonl.gz"
      File.write log, "{}\n"
      File.open(events, "w") do |file|
        Compress::Gzip::Writer.open(file, &.print("event\n"))
      end
      meta = Submit::Meta.new "0.0.1", "test-x", "left", 4, 7_u64,
        "x", "cd" * 16, events: true
      outbox = Submit::Outbox.new where / "outbox"
      directory = outbox.directory / Submit::Parcel.name(meta, 1)
      parcel = outbox.pack meta, 1, log, nil, events
      File.write parcel.directory / "notes.txt", "keep this file"
      before = contents directory
      source_log = File.read log
      source_events = File.read events
      File.write save, "not a save"
      source_save = File.read save
      won = Submit::Meta.new "0.0.1", "test-x", "won", 4, 7_u64,
        "x", "cd" * 16, events: true

      expect_raises(JSON::ParseException) do
        outbox.pack won, 1, log, save, events
      end
      expect(contents directory).to eq(before)
      expect(File.read(save)).to eq(source_save)
      expect(outbox.parcels.map(&.seq)).to eq([1])

      game = Game.dug Roguelike::Rng.new(7_u64)
      held = Save::Held.new "x", Roguelike::VERSION, Time.utc, 4,
        game.player.level, game.outcome, game
      File.write save, held.to_pretty_json
      source_save = File.read save
      outbox.pack won, 1, log, save, events

      packed = Submit::Parcel.open(directory) || raise "the repacked parcel was not complete"
      expect(packed.pieces.map(&.kind)).to eq(["replay", "save", "events", "meta"])
      expect(packed.meta.outcome).to eq("won")
      expect(packed.meta.events?).to be_true
      expect(unpack(directory / "replay.jsonl.gz")).to eq(source_log)
      expect(unpack(directory / "save.json.gz")).to eq(source_save)
      expect(unpack(directory / "events.jsonl.gz")).to eq("event\n")
      expect(File.read(directory / "notes.txt")).to eq("keep this file")

      outbox.pack won, 1, log, nil, events
      expect(outbox.parcels.first.pieces.map(&.kind)).to eq(["replay", "save", "events", "meta"])
      expect(unpack(directory / "save.json.gz")).to eq(source_save)

      expect(File.read(log)).to eq(source_log)
      expect(File.read(events)).to eq(source_events)
      expect(File.read(save)).to eq(source_save)
    end

    it "rolls back a failed repack publication" do
      where = root
      log = where / "run.jsonl"
      File.write log, "{}\n"
      meta = Submit::Meta.new "0.0.1", "test-x", "left", 4, 7_u64,
        "x", "cd" * 16
      outbox = Submit::Outbox.new where / "outbox"
      parcel = outbox.pack meta, 1, log, nil
      before = contents parcel.directory
      filesystem = FailingParcelFilesystem.new
      filesystem.mode = :publish

      expect_raises(IO::Error) do
        Submit::Parcel.pack parcel.directory, meta, 1, log, nil,
          filesystem: filesystem
      end

      expect(filesystem.failed).to eq([:publish])
      expect(contents parcel.directory).to eq(before)
      expect(Submit::Parcel.open(parcel.directory).try(&.seq)).to eq(1)
      expect(outbox.parcels.map(&.seq)).to eq([1])
    end

    it "recovers the prior parcel when publication and rollback both fail" do
      where = root
      log = where / "run.jsonl"
      File.write log, "{}\n"
      meta = Submit::Meta.new "0.0.1", "test-x", "left", 4, 7_u64,
        "x", "cd" * 16
      outbox = Submit::Outbox.new where / "outbox"
      parcel = outbox.pack meta, 1, log, nil
      before = contents parcel.directory
      filesystem = FailingParcelFilesystem.new
      filesystem.mode = :rollback

      expect_raises(IO::Error) do
        Submit::Parcel.pack parcel.directory, meta, 1, log, nil,
          filesystem: filesystem
      end

      expect(filesystem.failed).to eq([:publish, :rollback])
      recovered = Submit::Parcel.open(parcel.directory)
      expect(recovered.try(&.seq)).to eq(1)
      expect(contents parcel.directory).to eq(before)
      expect(outbox.parcels.map(&.seq)).to eq([1])
    end

    it "refuses a reentrant reader while a repack is publishing" do
      where = root
      old_log = where / "old.jsonl"
      new_log = where / "new.jsonl"
      File.write old_log, "old replay\n"
      File.write new_log, "new replay\n"
      old_meta = Submit::Meta.new "0.0.1", "test-x", "left", 4, 7_u64,
        "x", "cd" * 16
      new_meta = Submit::Meta.new "0.0.1", "test-x", "won", 5, 7_u64,
        "x", "cd" * 16
      directory = where / "#{"cd" * 16}-001"
      Submit::Parcel.pack directory, old_meta, 1, old_log, nil
      filesystem = ReentrantParcelFilesystem.new directory

      Submit::Parcel.pack directory, new_meta, 1, new_log, nil,
        filesystem: filesystem

      expect(filesystem.reader).to be_nil
      published = Submit::Parcel.open(directory) || raise "the repacked parcel did not open"
      expect(published.meta.outcome).to eq("won")
      expect(unpack(directory / "replay.jsonl.gz")).to eq("new replay\n")
    end

    it "leaves similarly prefixed unowned directories unchanged" do
      where = root
      log = where / "run.jsonl"
      File.write log, "{}\n"
      meta = Submit::Meta.new "0.0.1", "test-x", "left", 4, 7_u64,
        "x", "cd" * 16
      outbox = Submit::Outbox.new where / "outbox"
      parcel = outbox.pack meta, 1, log, nil
      unowned = [
        outbox.directory / ".#{parcel.directory.basename}.parcel-backup-not-ours",
        outbox.directory / ".#{parcel.directory.basename}.parcel-backup-#{"ab" * 12}-owned",
      ]
      before = unowned.map do |directory|
        Dir.mkdir directory
        File.write directory / "meta.json", "preserve this metadata"
        File.write directory / "notes.txt", "preserve this note"
        contents directory
      end

      expect(outbox.parcels.map(&.seq)).to eq([1])
      unowned.each_with_index do |directory, index|
        expect(contents(directory)).to eq(before[index])
      end
    end

    it "ignores malformed manifests without interrupting outbox scans or flushes" do
      where = root
      log = where / "run.jsonl"
      File.write log, "{}\n"
      manifests = [
        "not json",
        "1",
        "{}",
        %(["meta.json", 3]),
        %(["meta.json", "replay.jsonl.gz", "../unrelated"]),
      ]

      manifests.each_with_index do |contents, index|
        log_id = index.to_s(16).rjust(32, '0')
        meta = Submit::Meta.new "0.0.1", "test-x", "left", 4, 7_u64,
          "x", log_id
        outbox = Submit::Outbox.new where / "outbox-#{index}"
        parcel = outbox.pack meta, 1, log, nil
        File.delete parcel.directory / "replay.jsonl.gz"

        token = (index + 1).to_s(16).rjust(24, '0')
        backup = outbox.directory / ".#{parcel.directory.basename}.parcel-backup-#{token}-owned"
        Dir.mkdir backup
        File.write backup / ".parcel-owner", token
        File.write backup / ".complete", contents

        expect(outbox.parcels).to be_empty
        carrier = RecordingParcelCarrier.new
        outbox.flush carrier, IO::Memory.new
        expect(carrier.sent).to eq(0)
      end
    end

    it "removes local paths from copies without changing a resumed run" do
      # The long form, so the game and the checks see one spelling of it.
      where = Path[File.realpath(root)]
      logs = where / "logs"
      Dir.mkdir_p logs
      store = Save::Store.under where / "store"
      Log.pattern = logs.to_s
      Log.always = nil
      Submit.outbox = nil

      # The directory as it appears inside JSON. Windows backslashes are
      # doubled there.
      local = where.to_s.to_json[1..-2]

      begin
        game = Game.dug Roguelike::Rng.new(Recording::SEED)
        game.player.name = "privacy"
        6.times { game.perform Roguelike::Action::Wait.new }
        first_save = store.write game
        first_log = log_in logs
        Log.ended nil

        File.delete first_log
        held = store.held("privacy") || raise "the first save was not written"
        game = held.carried first_save
        4.times { game.perform Roguelike::Action::Wait.new }
        save = store.write game
        log = log_in logs
        events = game.events_file || raise "the events file was not written"

        source_log = File.read log
        source_save = File.read save
        source_events = File.read events
        expect(source_log).to contain(local)
        expect(source_save).to contain(local)

        meta = Submit::Meta.of game, Submit.log_id(log), true
        parcel = Submit::Parcel.pack where / "parcel", meta, 1, log, save, events

        expect(File.read(log)).to eq(source_log)
        expect(File.read(save)).to eq(source_save)
        expect(File.read(events)).to eq(source_events)

        uploaded_log = unpack parcel.directory / "replay.jsonl.gz"
        uploaded_save = unpack parcel.directory / "save.json.gz"
        uploaded_events = unpack parcel.directory / "events.jsonl.gz"
        expect(uploaded_log).not_to contain(local)
        expect(uploaded_save).not_to contain(local)
        expect(uploaded_events).not_to contain(local)

        replay_path = parcel.directory / "replay.jsonl.gz"
        reading = Replay::Reading.read replay_path
        expect(reading.header.run).not_to be_nil
        expect(reading.header.run).not_to contain(local)
        expect(reading.header.run).not_to contain("\"carried\":")
        expect(reading.header.continued.try(&.save)).to eq("save.json")
        expect(reading.header.continued.try(&.log)).to eq("replay.jsonl")
        expect(Replay::Verifier.check(replay_path).trouble).to be_nil

        uploaded_held = Save::Held.from_json uploaded_save
        expect(uploaded_held.replay.try(&.log)).to eq("replay.jsonl")
        expect(uploaded_held.game.to_json).not_to contain(local)
        expect(uploaded_held.game.to_json).not_to contain("\"carried\":")
        source_held = Save::Held.from_json source_save
        expect(uploaded_held.game.fingerprint).to eq(source_held.game.fingerprint)

        Log.ended nil
        resumed = (store.held("privacy") || raise "the saved character disappeared").carried(save)
        resumed.perform Roguelike::Action::Wait.new
        Log.ended nil
        report = Replay::Verifier.check log
        expect(report.trouble).to be_nil
        expect(report.resumes).to eq(1)
      ensure
        Log.ended nil
        Log.pattern = nil
        Log.always = nil
        Submit.outbox = nil
      end
    end

    it "replaces Windows drive, UNC and extended paths in uploaded metadata" do
      where = root
      logs = where / "logs"
      Dir.mkdir_p logs
      game = Recording.played logs.to_s, seed: UInt64::MAX, turns: 5, player: "windows"
      source = log_in logs
      lines = File.read_lines source
      header = Replay::Header.from_json lines.first
      continued = Replay::Carried.new(
        "C:\\Users\\Alice\\AppData\\Local\\Rogue\\saves\\hero.json",
        Time.utc, game.turn, "\\\\server\\share\\Alice\\logs\\run.jsonl", 2)
      lines[0] = type_last header.with_continued(continued)
      log = where / "windows.jsonl"
      File.write log, lines.join('\n') + '\n'

      store = Save::Store.under where / "store"
      save = store.write game
      held = store.held("windows") || raise "the save was not written"
      mark = Replay::Mark.new("\\\\?\\C:\\Users\\Alice\\logs\\run.jsonl", 2)
      windows_save = Save::Held.new held.name, held.version, held.saved, held.turn,
        held.level, held.outcome, held.game, mark
      File.write save, windows_save.to_pretty_json

      meta = Submit::Meta.of game, Submit.log_id(log)
      parcel = Submit::Parcel.pack where / "windows-parcel", meta, 1, log, save
      uploaded_log = unpack parcel.directory / "replay.jsonl.gz"
      uploaded_save = Save::Held.from_json unpack(parcel.directory / "save.json.gz")
      sanitized = Replay::Reading.read(parcel.directory / "replay.jsonl.gz")

      expect(uploaded_log).not_to contain("C:\\Users")
      expect(uploaded_log).not_to contain("\\\\server")
      expect(uploaded_log).not_to contain("\\\\?\\")
      expect(sanitized.header.continued.try(&.save)).to eq("save.json")
      expect(sanitized.header.continued.try(&.log)).to eq("replay.jsonl")
      expect(sanitized.header.format).to eq(header.format)
      expect(sanitized.header.seed).to eq(UInt64::MAX)
      expect(uploaded_save.replay.try(&.log)).to eq("replay.jsonl")
      expect(Replay::Verifier.check(parcel.directory / "replay.jsonl.gz").trouble).to be_nil
    end

    it "refuses a path-bearing header it cannot decode" do
      where = root
      logs = where / "logs"
      Dir.mkdir_p logs
      game = Recording.played logs.to_s, turns: 3, player: "invalid"
      lines = File.read_lines log_in logs
      header = Replay::Header.from_json lines.first
      continued = Replay::Carried.new(
        "/Users/private-account/saves/hero.json", Time.utc, game.turn,
        "/Users/private-account/logs/run.jsonl", 1)
      invalid_header = type_last(header.with_continued(continued))
        .sub(/"seed":\d+/, %("seed":"invalid"))
      log = where / "invalid-header.jsonl"
      File.write log, ([invalid_header] + lines[1..]).join('\n') + '\n'
      meta = Submit::Meta.new "0.0.1", "test-x", "playing", game.turn,
        game.world.seed, game.player.name, "ab" * 16

      expect_raises(JSON::ParseException) do
        Submit::Parcel.pack where / "invalid-parcel", meta, 1, log, nil
      end
    end

    it "is nil for a directory that is not a parcel" do
      where = root / "stray"
      Dir.mkdir_p where
      expect(Submit::Parcel.open where).to be_nil
    end
  end

  describe "packing while a run is played" do
    it "packs a save with its log, and the end of the run after it" do
      where = root
      logs = where / "logs"
      Dir.mkdir_p logs
      store = Save::Store.under where / "store"

      sending where do |outbox|
        Recording.recording logs.to_s do
          game = Roguelike::Game.dug Roguelike::Rng.new(Recording::SEED)
          game.player.name = "packer"
          rng = Roguelike::Rng.new Recording::SEED, 5_u64

          4.times { game.perform game.legal.reject(Roguelike::Action::Ascend).sample(rng) }
          store.write game

          first = outbox.parcels
          expect(first.size).to eq(1)
          expect(first.first.seq).to eq(1)
          expect(first.first.pieces.map(&.kind)).to eq(["replay", "save", "events", "meta"])
          expect(first.first.meta.events?).to be_true
          expect(first.first.meta.character).to eq("packer")

          2.times { game.perform game.legal.reject(Roguelike::Action::Ascend).sample(rng) }
          store.write game
          expect(outbox.parcels.map(&.seq)).to eq([1, 2])

          # A save with no action since the last one sent, as when the stairs
          # save and a quit right after it, writes a pause and no parcel.
          store.write game
          expect(outbox.parcels.map(&.seq)).to eq([1, 2])
          expect(store.held("packer").try(&.replay).try(&.pause)).to eq(3)

          # The log is closed with nothing acted since the save. The save's
          # parcel already holds everything, so none is added.
          Log.ended nil
          expect(outbox.parcels.map(&.seq)).to eq([1, 2])

          game
        end

        Recording.recording logs.to_s do
          game = Roguelike::Game.dug Roguelike::Rng.new(Recording::SEED)
          game.player.name = "ender"
          rng = Roguelike::Rng.new Recording::SEED, 6_u64
          3.times { game.perform game.legal.reject(Roguelike::Action::Ascend).sample(rng) }
          game
        end

        # The second run was never saved and the process went out from under
        # it. Its footer is written, and that is worth sending.
        ended = outbox.parcels.select { |parcel| parcel.meta.character == "ender" }
        expect(ended.size).to eq(1)
        expect(ended.first.seq).to eq(1)
        expect(ended.first.pieces.map(&.kind)).to eq(["replay", "events", "meta"])
      end
    end

    it "adds the final save to the parcel for the end of the run" do
      where = root
      logs = where / "logs"
      Dir.mkdir_p logs
      store = Save::Store.under where / "store"

      sending where do |outbox|
        Recording.recording logs.to_s do
          game = Roguelike::Game.dug Roguelike::Rng.new(Recording::SEED)
          game.player.name = "leaver"
          2.times { game.perform Roguelike::Action::Wait.new }
          store.write game
          expect(outbox.parcels.map(&.seq)).to eq([1])

          # Climbing out from the first floor ends the run, and the footer
          # packs the log on its own.
          game.perform Roguelike::Action::Ascend.new
          expect(game.over?).to be_true
          expect(outbox.parcels.map(&.seq)).to eq([1, 2])
          expect(outbox.parcels.last.pieces.map(&.kind)).to eq(["replay", "events", "meta"])

          # The save written after joins that parcel rather than making one.
          store.write game
          expect(outbox.parcels.map(&.seq)).to eq([1, 2])
          expect(outbox.parcels.last.pieces.map(&.kind)).to eq(["replay", "save", "events", "meta"])
          expect(outbox.parcels.last.meta.outcome).to eq("left")

          game
        end
      end
    end

    it "packs nothing when nothing is recording" do
      where = root
      store = Save::Store.under where / "store"

      sending where do |outbox|
        game = Roguelike::Game.dug Roguelike::Rng.new(Recording::SEED)
        game.player.name = "quiet"
        store.write game
        expect(outbox.parcels).to be_empty
      end
    end
  end

  describe Submit::Client do
    it "asks for a form for each piece and posts the file as the last field" do
      where = root
      server = FakeUploadServer.new
      begin
        log = where / "run.jsonl"
        File.write log, "{\"type\":\"header\"}\n"
        meta = Submit::Meta.new "0.2.1", "linux-x86_64", "died", 40, 9_u64, "ex", "ef" * 16
        outbox = Submit::Outbox.new where / "outbox"
        parcel = outbox.pack meta, 2, log, nil
        replay_bytes = File.read(parcel.directory / "replay.jsonl.gz").to_slice

        output = IO::Memory.new
        outbox.flush Submit::Client.new(server.url), output

        expect(output.to_s).to match(/\ASent replay efefefef… \(\d+(\.\d+)? [KM]?B\)\n\z/)
        expect(outbox.parcels).to be_empty

        expect(server.asked.size).to eq(2)
        first = server.asked.first
        expect(first["token"]).to eq(Submit::TOKEN)
        expect(first["version"]).to eq("0.2.1")
        expect(first["platform"]).to eq("linux-x86_64")
        expect(first["log"]).to eq("ef" * 16)
        expect(first["seq"]).to eq(2)
        expect(first["kind"]).to eq("replay")
        expect(first["size"]).to eq(replay_bytes.size)
        expect(server.asked.last["kind"]).to eq("meta")

        expect(server.forms.first.keys).to eq(["key", "policy", "x-amz-signature"])
        expect(server.uploads["0.2.1/#{"ef" * 16}/002-replay"]).to eq(replay_bytes)
        expect(String.new server.uploads["0.2.1/#{"ef" * 16}/002-meta"]).to eq(meta.to_json)
      ensure
        server.close
      end
    end

    it "sends the same bytes with a progress line on" do
      where = root
      server = FakeUploadServer.new
      begin
        log = where / "run.jsonl"
        File.write log, "{\"type\":\"header\"}\n"
        meta = Submit::Meta.new "0.2.1", "linux-x86_64", "died", 40, 9_u64, "ex", "ef" * 16
        outbox = Submit::Outbox.new where / "outbox"
        parcel = outbox.pack meta, 2, log, nil
        replay_bytes = File.read(parcel.directory / "replay.jsonl.gz").to_slice

        output = IO::Memory.new
        shown = IO::Memory.new
        outbox.flush Submit::Client.new(server.url, shown), output

        expect(outbox.parcels).to be_empty
        expect(server.uploads["0.2.1/#{"ef" * 16}/002-replay"]).to eq(replay_bytes)
        expect(String.new server.uploads["0.2.1/#{"ef" * 16}/002-meta"]).to eq(meta.to_json)
        expect(shown.to_s).to match(/\Areplay +\d+ B of \d+ B\nmeta +\d+ B of \d+ B\n\z/)
      ensure
        server.close
      end
    end

    it "keeps a parcel the server refuses and says so" do
      where = root
      server = FakeUploadServer.new
      server.refuse = true
      begin
        log = where / "run.jsonl"
        File.write log, "{}\n"
        meta = Submit::Meta.new "0.2.1", "linux-x86_64", "won", 1, 1_u64, "r", "01" * 16
        outbox = Submit::Outbox.new where / "outbox"
        outbox.pack meta, 1, log, nil

        output = IO::Memory.new
        outbox.flush Submit::Client.new(server.url), output

        expect(output.to_s).to contain("Could not send replay 01010101…")
        expect(output.to_s).to contain("403")
        expect(output.to_s).to contain("tried again next time")
        expect(outbox.parcels.size).to eq(1)
      ensure
        server.close
      end
    end

    it "sends the rest of a parcel to a server that takes no events" do
      where = root
      server = FakeUploadServer.new
      server.unknown = ["events"]
      begin
        log = where / "run.jsonl"
        events = where / "run.events.jsonl.gz"
        File.write log, "{}\n"
        File.open(events, "w") { |file| Compress::Gzip::Writer.open(file, &.print("{}\n")) }
        meta = Submit::Meta.new "0.2.1", "linux-x86_64", "won", 1, 1_u64, "r", "04" * 16, events: true
        outbox = Submit::Outbox.new where / "outbox"
        parcel = outbox.pack meta, 1, log, nil, events
        expect(parcel.pieces.map(&.kind)).to eq(["replay", "events", "meta"])

        output = IO::Memory.new
        outbox.flush Submit::Client.new(server.url), output

        expect(outbox.parcels).to be_empty
        expect(server.asked.map(&.["kind"].as_s)).to eq(["replay", "events", "meta"])
        expect(server.uploads.keys.map(&.split('-').last)).to eq(["replay", "meta"])
      ensure
        server.close
      end
    end

    it "keeps a parcel when nothing answers" do
      where = root
      log = where / "run.jsonl"
      File.write log, "{}\n"
      meta = Submit::Meta.new "0.2.1", "linux-x86_64", "won", 1, 1_u64, "r", "02" * 16
      outbox = Submit::Outbox.new where / "outbox"
      outbox.pack meta, 1, log, nil

      output = IO::Memory.new
      outbox.flush Submit::Client.new("http://127.0.0.1:9/"), output

      expect(output.to_s).to contain("Could not send replay")
      expect(outbox.parcels.size).to eq(1)
    end
  end

  describe ".flush" do
    it "leaves the outbox alone when the binary has no address" do
      where = root
      sending where do |outbox|
        log = where / "run.jsonl"
        File.write log, "{}\n"
        meta = Submit::Meta.new "0.2.1", "linux-x86_64", "won", 1, 1_u64, "r", "03" * 16
        outbox.pack meta, 1, log, nil

        output = IO::Memory.new
        Submit.flush "", output
        expect(output.to_s).to be_empty
        expect(outbox.parcels.size).to eq(1)
      end
    end
  end

  describe Submit::Consent do
    it "has no answer until asked, and keeps the one given" do
      consent = Submit::Consent.new root
      expect(consent.answer).to be_nil

      output = IO::Memory.new
      expect(consent.ask IO::Memory.new("y\n"), output).to be_true
      expect(output.to_s).to contain("What is sent: the replay's seed")
      expect(output.to_s).to contain("saved game state is included when a save is sent")
      expect(output.to_s).to contain("event records")
      expect(output.to_s).to contain("tester name and ID")
      expect(output.to_s).to contain("compiler versions")
      expect(output.to_s).to contain("No local filesystem paths")
      expect(output.to_s).to contain(consent.path.to_s)
      expect(consent.answer).to be_true
      expect(File.read(consent.path)).to start_with("yes ")
    end

    it "takes Enter alone as no" do
      consent = Submit::Consent.new root
      expect(consent.ask IO::Memory.new("\n"), IO::Memory.new).to be_false
      expect(consent.answer).to be_false
    end
  end

  describe ".arrange" do
    after_each do
      Submit.outbox = nil
      Log.always = nil
    end

    it "sends nothing when not wanted" do
      expect(Submit.arrange false, false, root, IO::Memory.new("y\n"), IO::Memory.new).to be_false
      expect(Submit.outbox).to be_nil
    end

    it "does not ask when the input is not a terminal" do
      output = IO::Memory.new
      expect(Submit.arrange true, false, root, IO::Memory.new("y\n"), output).to be_false
      expect(output.to_s).to be_empty
    end

    it "sends when the answer on file is yes, and records to the test logs" do
      where = root
      Submit::Consent.new(where).record true

      expect(Submit.arrange true, false, where, IO::Memory.new, IO::Memory.new).to be_true
      expect(Submit.outbox.try(&.directory)).to eq(where / "outbox")
      expect(Log.always).to eq(Log.test_logs)
    end

    it "keeps a pattern already chosen" do
      where = root
      Submit::Consent.new(where).record true
      Log.always = where / "mine"

      Submit.arrange true, false, where, IO::Memory.new, IO::Memory.new
      expect(Log.always).to eq(where / "mine")
    end

    it "stays off after a no" do
      where = root
      Submit::Consent.new(where).record false
      expect(Submit.arrange true, false, where, IO::Memory.new, IO::Memory.new).to be_false
    end
  end
end
