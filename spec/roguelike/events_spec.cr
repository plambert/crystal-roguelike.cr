require "compress/gzip"
require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Events::Writer do
  alias Action = Roguelike::Action
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Log = Roguelike::Replay::Log
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Rng = Roguelike::Rng
  alias Save = Roguelike::Save
  alias Species = Roguelike::Species
  alias World = Roguelike::World
  alias Writer = Roguelike::Events::Writer

  # A directory of logs nothing else writes to.
  def logs : Path
    made = Recording.directory / "events-#{Random.rand UInt32}"
    Dir.mkdir_p made
    made
  end

  # The one replay log in *where*.
  def log_in(where : Path) : Path
    found = Dir.children(where).select(&.ends_with? ".jsonl")
    raise "#{where} holds #{found.size} logs" unless found.size == 1

    where / found.first
  end

  # Every line of the events file at *path*, parsed.
  def lines(path : Path) : Array(JSON::Any)
    File.open path do |file|
      Compress::Gzip::Reader.open(file) do |gzip|
        gzip.each_line.map { |line| JSON.parse line }.to_a
      end
    end
  end

  # The lines of *found* whose kind is *kind*.
  def kinds(found : Array(JSON::Any), kind : String) : Array(JSON::Any)
    found.select { |line| line["kind"]?.try(&.as_s) == kind }
  end

  describe "a headless run" do
    it "writes a header and one line per event beside the replay log" do
      where = logs
      Recording.played where.to_s, turns: 40

      log = log_in where
      path = Writer.path_for log
      expect(File.exists? path).to be_true
      expect(path.basename).to eq(log.basename.rchop(".jsonl") + ".events.jsonl.gz")

      found = lines path
      header = found.first
      expect(header["type"]).to eq("header")
      expect(header["format"]).to eq(Writer::FORMAT)
      expect(header["log"]).to eq(Roguelike::Submit.log_id(log))
      expect(header["game_version"].as_s).to start_with(Roguelike::VERSION)

      events = found.select &.["kind"]?
      expect(events).not_to be_empty
      events.each do |line|
        expect(line["turn"].as_i).to be >= 0
        expect(line["floor"].as_i).to eq(1)
      end

      opening = events.first
      expect(opening["kind"]).to eq("stats")
      expect(opening["cause"]).to eq("start")
      expect(opening["ac"].as_i?).not_to be_nil
      expect(opening["hp_max"].as_i?).not_to be_nil
      expect(opening.as_h.has_key? "hit_points").to be_false

      expect(found.last["type"]).to eq("footer")
    end

    it "writes nothing when events are off" do
      where = logs
      Writer.enabled = false
      begin
        Recording.played where.to_s, turns: 5
      ensure
        Writer.enabled = true
      end

      expect(File.exists? Writer.path_for(log_in where)).to be_false
    end
  end

  describe "a fight" do
    # One lit room with the character in the middle and a slime beside them.
    ROOM = [
      "#######",
      "#.....#",
      "#.....#",
      "#..<..#",
      "#.....#",
      "#.....#",
      "#######",
    ]

    it "writes hit, miss and slain lines with the dice" do
      where = logs
      floor = Playing.daylight Floor.parse("arena", ROOM)
      floor.place Monster.new(Species::Slime, 3, 2, "band-one", hit_points: 12)
      player = Player.new floor.id, 3, 3, hit_points: 200,
        experience: Roguelike::Advancement.threshold(2) - 1
      game = Game.new World.new(20260912_u64, {floor.id => floor}), player
      game.player.name = "fighter"

      Recording.recording where.to_s do
        # A creature built by hand takes its id on the first action.
        game.perform Action::Wait.new

        200.times do
          break unless game.floor.monster(3, 2)

          game.perform Action::MeleeAttack.new({3, 2})
        end
        game
      end

      found = lines Writer.path_for(log_in where)
      attacks = kinds(found, "attack").select { |line| line["attacker_species"] == "player" }
      hits = attacks.select &.["hit"].as_bool
      misses = attacks.reject &.["hit"].as_bool
      expect(hits).not_to be_empty
      expect(misses).not_to be_empty

      dice = game.player.damage.to_s
      id = hits.first["target"]
      hits.each do |line|
        expect(line["target"]).to eq(id)
        expect(line["target_species"]).to eq("white_slime")
        expect(line["roll"]["dice"]).to eq(dice)
        expect(line["roll"]["total"]).to eq(line["damage"])
        expect(line["left"].as_i).to be >= 0
      end
      misses.each do |line|
        expect(line["roll"]["dice"]).to eq(dice)
        expect(line["roll"]["total"]?).to be_nil
      end
      expect(hits.last["left"]).to eq(0)

      slain = kinds(found, "slain")
      expect(slain.size).to eq(1)
      expect(slain.first["creature"]).to eq(id)
      expect(slain.first["attacker_species"]).to eq("player")
      expect(slain.first["target_species"]).to eq("white_slime")

      levels = kinds(found, "level_up")
      expect(levels.map(&.["level"])).to eq([2])
      after = found[found.index!(levels.first) + 1]
      expect(after["kind"]).to eq("stats")
      expect(after["cause"]).to eq("level_up")
      expect(after["level"]).to eq(2)

      back = kinds(found, "attack").select { |line| line["attacker_species"] == "white_slime" }
      back.each do |line|
        expect(line["attacker"]).to eq(id)
        expect(line["target_species"]).to eq("player")
        expect(line.as_h.has_key? "weapon").to be_false
      end
    end
  end

  describe "a floor arrival" do
    it "writes the level and hit points, and the numbers after it" do
      where = logs
      game = Game.dug Rng.new(Recording::SEED)
      game.player.name = "climber"

      Recording.recording where.to_s do
        down = game.floor.find Roguelike::Terrain::StairsDown
        raise "the first floor has no staircase down" unless down

        game.player.move_to down
        game.perform Action::Descend.new
        game
      end

      found = lines Writer.path_for(log_in where)
      climbed = kinds(found, "climbed")
      expect(climbed.size).to eq(1)
      line = climbed.first
      expect(line["floor"]).to eq(2)
      expect(line["floor_id"]).to eq(game.player.floor)
      expect(line["depth"]).to eq(2)
      expect(line["level"]).to eq(1)
      expect(line["hp"]).to eq(JSON.parse([game.player.hit_points, game.player.max_hit_points].to_json))

      after = found[found.index!(line) + 1]
      expect(after["kind"]).to eq("stats")
      expect(after["cause"]).to eq("climbed")
    end
  end

  describe Roguelike::Events::ItemFacts do
    alias ItemFacts = Roguelike::Events::ItemFacts
    alias ItemKind = Roguelike::ItemKind

    it "says what the character has made out of their own things" do
      sword = Roguelike::Item.new ItemKind::ShortSword, enchantment: 1,
        blessing: Roguelike::Blessing::Cursed
      facts = JSON.parse ItemFacts.of(sword, Roguelike::Lore.new).to_json

      expect(facts["kind"]).to eq("short_sword")
      expect(facts["enchantment"]).to eq(1)
      expect(facts["blessing"]).to eq("cursed")
      expect(facts["known"]["kind"]).to eq(true)
      expect(facts["known"]["enchantment"]).to eq(true)
      expect(facts["known"]["blessing"]).to eq(false)
    end

    it "says nothing about what is known of a creature's things" do
      sword = Roguelike::Item.new ItemKind::ShortSword
      facts = JSON.parse ItemFacts.of(sword, nil).to_json

      expect(facts.as_h.has_key? "known").to be_false
    end
  end

  describe "a resumed run" do
    NAME = "resumer"

    # Plays *count* actions drawn from `Game#legal`, on a stream of *salt*.
    def play(game : Game, count : Int32, salt : UInt64) : Game
      rng = Rng.new Recording::SEED, salt
      count.times do
        break if game.over?

        game.perform game.legal.reject(Action::Ascend).sample(rng)
      end
      game
    end

    it "appends to the file the run began, after a resume line" do
      where = logs
      store = Playing.store

      Log.pattern = where.to_s
      begin
        game = Game.dug Rng.new(Recording::SEED)
        game.player.name = NAME
        play game, 20, 1_u64
        store.write game
        Log.ended nil

        held = store.held NAME
        raise "#{store.directory} holds no #{NAME}" unless held

        play held.carried(store.path(NAME)), 20, 2_u64
      ensure
        Log.ended nil
        Log.pattern = nil
      end

      found = lines Writer.path_for(log_in where)
      types = found.compact_map &.["type"]?.try(&.as_s)
      expect(types).to eq(["header", "pause", "resume", "footer"])

      resume = found.index! { |line| line["type"]? == "resume" }
      expect(found[resume]["pause"]).to eq(1)
      expect(found[resume + 1]["kind"]).to eq("stats")
      expect(found[resume + 1]["cause"]).to eq("resume")
      expect(found[(resume + 1)..].count(&.["kind"]?)).to be > 1
    end
  end

  describe "the fixture" do
    it "reads as events the game knows" do
      path = Path[__DIR__] / ".." / "fixtures" / "events" / "run.events.jsonl"
      found = File.read_lines(path).map { |line| JSON.parse line }

      expect(found.first["type"]).to eq("header")
      events = found.select &.["kind"]?
      expect(events.size).to be >= 15
      events.each do |line|
        fields = line.as_h.dup
        floor_id = fields.delete "floor_id"
        fields["floor"] = floor_id if floor_id
        event = Event.from_json fields.to_json
        expect(event.kind).to eq(line["kind"])
      end
    end
  end
end
