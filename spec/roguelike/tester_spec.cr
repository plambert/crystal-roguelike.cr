require "../spec_helper"
require "../support/playing"
require "../support/recording"

Spectator.describe Roguelike::Tester do
  alias Tester = Roguelike::Tester

  # A state directory of its own. The specs never touch the real one.
  let(root) do
    Path[File.tempname "roguelike-tester", nil].tap do |made|
      Dir.mkdir_p made
      at_exit { FileUtils.rm_rf made.to_s }
    end
  end

  # What the file under *root* holds, as JSON.
  def written(where : Path) : JSON::Any
    JSON.parse File.read(Tester.path where)
  end

  # Runs *block* with `Tester.current` set to *tester*, and puts it back.
  def playing_as(tester : Tester?, &)
    Tester.current = tester
    yield
  ensure
    Tester.current = nil
  end

  describe "the first-launch question" do
    let(run) { Playing.open }

    # Asks the way the game does and records what happens next.
    def asked(run : Playing::Run, where : Path) : Array(String)
      after = [] of String
      run.play.ask_the_tester where, -> do
        after << "started"
        nil
      end
      run.session.render
      after
    end

    after_each { Tester.current = nil }

    it "asks why the name is wanted" do
      asked run, root

      expect(run.play.entry.asking?).to be_true
      expect(run.text).to contain "uploaded runs"
      expect(run.text).to contain "dashboard"
    end

    it "writes the name and a uuid to the file" do
      after = asked run, root
      run.type "Hedrik"
      run.press "enter"

      held = written root
      expect(held["name"].as_s).to eq "Hedrik"
      expect(UUID.parse?(held["id"].as_s)).not_to be_nil
      expect(Tester.current.try(&.name)).to eq "Hedrik"
      expect(after).to eq ["started"]
    end

    it "takes anonymous for an empty answer, with a uuid" do
      asked run, root
      run.press "enter"

      held = written root
      expect(held["name"].as_s).to eq "anonymous"
      expect(UUID.parse?(held["id"].as_s)).not_to be_nil
    end

    it "takes anonymous when the question is escaped" do
      asked run, root
      run.press "escape"

      expect(written(root)["name"].as_s).to eq "anonymous"
    end

    it "gives two anonymous answers different uuids" do
      other = Path[File.tempname "roguelike-tester", nil]
      at_exit { FileUtils.rm_rf other.to_s }

      asked run, root
      run.press "enter"
      again = Playing.open
      asked again, other
      again.press "enter"

      expect(written(root)["id"]).not_to eq written(other)["id"]
    end
  end

  describe ".arrange" do
    let(uuid) { "0b1f6e0e-3a53-4f0b-9d6e-6a2f2a1f2b11" }

    it "answers nil when there is no file and no flag, so the game asks" do
      expect(Tester.arrange root).to be_nil
      expect(File.exists? Tester.path(root)).to be_false
    end

    it "answers the file when there is one" do
      Tester.new(uuid, "Hedrik").write root

      expect(Tester.arrange(root).try(&.name)).to eq "Hedrik"
    end

    it "writes the name given by --tester-name, with a new uuid" do
      tester = Tester.arrange root, nil, "Hedrik"

      expect(tester.try(&.name)).to eq "Hedrik"
      expect(written(root)["name"].as_s).to eq "Hedrik"
      expect(UUID.parse?(written(root)["id"].as_s)).not_to be_nil
    end

    it "writes the uuid given by --tester-id, with the name anonymous" do
      Tester.arrange root, uuid, nil

      expect(written(root)["id"].as_s).to eq uuid
      expect(written(root)["name"].as_s).to eq "anonymous"
    end

    it "keeps the name when --tester-id changes the uuid" do
      Tester.new("11111111-1111-4111-8111-111111111111", "Hedrik").write root
      Tester.arrange root, uuid, nil

      expect(written(root)["id"].as_s).to eq uuid
      expect(written(root)["name"].as_s).to eq "Hedrik"
    end

    it "keeps the uuid when --tester-name renames" do
      Tester.new(uuid, "Hedrik").write root
      Tester.arrange root, nil, "HedWin"

      expect(written(root)["id"].as_s).to eq uuid
      expect(written(root)["name"].as_s).to eq "HedWin"
    end

    it "leaves the file alone when the flags repeat what it says" do
      Tester.new(uuid, "Hedrik").write root
      before = File.read Tester.path(root)
      File.write Tester.path(root), before.sub("{", "{ ")
      kept = File.read Tester.path(root)

      Tester.arrange root, uuid, "Hedrik"

      expect(File.read Tester.path(root)).to eq kept
    end

    it "takes an empty --tester-name as anonymous" do
      expect(Tester.arrange(root, nil, "  ").try(&.name)).to eq "anonymous"
    end

    it "refuses an id that is not a uuid" do
      expect { Tester.arrange root, "not-a-uuid", nil }.to raise_error ArgumentError
      expect(File.exists? Tester.path(root)).to be_false
    end

    it "does not read a file that is not JSON" do
      File.write Tester.path(root), "oops"

      expect(Tester.read root).to be_nil
    end
  end

  describe "the flags" do
    it "are on the command line" do
      cli = Roguelike::Cli.parse %w[--tester-id 0b1f6e0e-3a53-4f0b-9d6e-6a2f2a1f2b11 --tester-name Hed]

      expect(cli.tester_id).to eq "0b1f6e0e-3a53-4f0b-9d6e-6a2f2a1f2b11"
      expect(cli.tester_name).to eq "Hed"
      expect(Roguelike::Cli.parse(%w[]).tester_name).to be_nil
    end
  end

  describe "in the upload meta" do
    let(game) do
      Roguelike::Game.dug(Roguelike::Rng.new(Recording::SEED)).tap(&.player.name = "x")
    end

    it "carries the id and name" do
      tester = Tester.new "0b1f6e0e-3a53-4f0b-9d6e-6a2f2a1f2b11", "Hedrik"
      meta = playing_as(tester) { Roguelike::Submit::Meta.of game, "ab" * 16 }

      held = JSON.parse meta.to_json
      expect(held["tester"]["id"].as_s).to eq tester.id
      expect(held["tester"]["name"].as_s).to eq "Hedrik"
      expect(Roguelike::Submit::Meta.from_json(meta.to_json).tester).to eq tester
    end

    it "has no tester field when there is no tester" do
      meta = Roguelike::Submit::Meta.of game, "ab" * 16

      expect(JSON.parse(meta.to_json).as_h.has_key?("tester")).to be_false
    end
  end

  describe "in the replay header" do
    # The first line of a run recorded to a file.
    def header(tester : Tester?) : JSON::Any
      name = Recording.directory / "tester-#{Random::Secure.hex 4}.jsonl"
      playing_as(tester) { Recording.played name.to_s, turns: 3 }

      JSON.parse File.read(name).lines.first
    end

    it "carries the id and name" do
      tester = Tester.new "0b1f6e0e-3a53-4f0b-9d6e-6a2f2a1f2b11", "Hedrik"
      held = header tester

      expect(held["tester"]["id"].as_s).to eq tester.id
      expect(held["tester"]["name"].as_s).to eq "Hedrik"
    end

    it "has no tester field when there is no tester" do
      expect(header(nil).as_h.has_key?("tester")).to be_false
    end
  end
end
