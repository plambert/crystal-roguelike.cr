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

Spectator.describe Roguelike::Submit do
  alias Submit = Roguelike::Submit
  alias Log = Roguelike::Replay::Log
  alias Save = Roguelike::Save

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
  end

  describe Submit::Parcel do
    it "packs gzipped copies and reads back by name" do
      where = root
      log = where / "run.jsonl"
      save = where / "run.json"
      File.write log, "{\"type\":\"header\"}\n{\"type\":\"act\"}\n"
      File.write save, "{\"name\":\"x\"}"
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
          expect(first.first.pieces.map(&.kind)).to eq(["replay", "save", "meta"])
          expect(first.first.meta.character).to eq("packer")

          2.times { game.perform game.legal.reject(Roguelike::Action::Ascend).sample(rng) }
          store.write game
          expect(outbox.parcels.map(&.seq)).to eq([1, 2])

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
        expect(ended.first.pieces.map(&.kind)).to eq(["replay", "meta"])
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
      expect(output.to_s).to contain("What is sent: the seed")
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
