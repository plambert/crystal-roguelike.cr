require "compress/gzip"
require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Event::StatChanged do
  alias Action = Roguelike::Action
  alias Event = Roguelike::Event
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Monster = Roguelike::Monster
  alias Player = Roguelike::Player
  alias Species = Roguelike::Species
  alias World = Roguelike::World
  alias Writer = Roguelike::Events::Writer

  # One lit room with the character in the middle.
  ROOM = [
    "#######",
    "#.....#",
    "#.....#",
    "#..<..#",
    "#.....#",
    "#.....#",
    "#######",
  ]

  # A game on `ROOM` with *player*, and a slime north of them when *slime*.
  def room(player : Player, slime : Bool = false) : Game
    floor = Playing.daylight Floor.parse("arena", ROOM)
    floor.place Monster.new(Species::Slime, 3, 2, "band-one", hit_points: 12) if slime
    game = Game.new World.new(20260912_u64, {floor.id => floor}), player
    game.enroll
    game
  end

  # The stat events of the last action.
  def changes(game : Game) : Array(Event::StatChanged)
    game.events.compact_map &.as?(Event::StatChanged)
  end

  # Every stat event over up to *times* swings at the slime, each with the
  # event before it.
  def fought(game : Game, times : Int32) : Array({Event?, Event::StatChanged})
    found = [] of {Event?, Event::StatChanged}
    times.times do
      break unless game.floor.monster(3, 2)

      game.perform Action::MeleeAttack.new({3, 2})
      game.events.each_with_index do |event, index|
        next unless event.is_a?(Event::StatChanged)

        before = game.events[0...index].reverse.find { |other| !other.is_a?(Event::StatChanged) }
        found << {before, event}
      end
    end
    found
  end

  it "fires nothing for an action that changes no stat" do
    game = room Player.new("arena", 3, 3)

    game.perform Action::Wait.new
    expect(changes game).to be_empty
    game.perform Action::Move.new(Roguelike::Direction::East)
    expect(changes game).to be_empty
  end

  it "lowers the hit points with the blow as the cause" do
    game = room Player.new("arena", 3, 3, hit_points: 200), slime: true

    blows = fought(game, 200).select { |_, changed| changed.stat == "hp" && changed.cause == "attack" }
    expect(blows).not_to be_empty
    blows.each do |before, changed|
      attack = before.as(Event::Attack)
      expect(attack.hit?).to be_true
      expect(changed.from.as(Int32) - changed.to.as(Int32)).to eq(attack.damage)
    end
  end

  it "changes the armor class with the wear as the cause" do
    player = Player.new "arena", 3, 3
    player.inventory.add Item.new(ItemKind::LeatherArmor)
    game = room player
    before = player.armor_class

    game.perform Action::Wear.new(game.carried('a').as(Item).id)
    ac = changes(game).select(&.stat.== "ac")
    expect(ac.size).to eq(1)
    expect(ac.first.from).to eq(before)
    expect(ac.first.to).to eq(player.armor_class)
    expect(ac.first.to).not_to eq(before)
    expect(ac.first.cause).to eq("readied")
  end

  it "fires level, maximum hit points and experience on a level up" do
    player = Player.new "arena", 3, 3, hit_points: 200,
      experience: Roguelike::Advancement.threshold(2) - 1
    game = room player, slime: true

    found = fought(game, 200).map(&.[1])
    up = found.select(&.cause.== "level_up")
    expect(up.map(&.stat)).to contain("level", "hp_max", "experience")
    level = up.find!(&.stat.== "level")
    expect(level.from).to eq(1)
    expect(level.to).to eq(2)
    experience = up.find!(&.stat.== "experience")
    expect(experience.from).to eq(Roguelike::Advancement.threshold(2) - 1)
    expect(experience.to).to eq(player.experience)
  end

  it "names every stat once and holds the player's numbers" do
    player = Player.new "arena", 3, 3
    reading = Event::StatChanged.reading player
    expect(reading.size).to eq(Event::StatChanged::NAMES.size)
    expect(reading[0]).to eq(player.hit_points)
    expect(reading[Event::StatChanged::NAMES.index!("ac")]).to eq(player.armor_class)
    expect(reading[Event::StatChanged::NAMES.index!("damage")]).to eq(player.damage.to_s)
    expect(reading[Event::StatChanged::NAMES.index!("speed")]).to eq(player.pace.speed)
  end

  it "round-trips through JSON as old and new" do
    changed = Event::StatChanged.new("damage", "1d2", "1d6+1", "readied")
    json = JSON.parse changed.to_json
    expect(json["kind"]).to eq("stat_changed")
    expect(json["old"]).to eq("1d2")
    expect(json["new"]).to eq("1d6+1")

    back = Event.from_json(changed.to_json).as(Event::StatChanged)
    expect(back.stat).to eq("damage")
    expect(back.to).to eq("1d6+1")
    expect(back.cause).to eq("readied")
  end

  it "writes a line to the events file after the event that caused it" do
    where = Recording.directory / "stat-events-#{Random.rand UInt32}"
    Dir.mkdir_p where
    game = room Player.new("arena", 3, 3, hit_points: 200), slime: true
    game.player.name = "fighter"

    Recording.recording where.to_s do
      fought game, 200
      game
    end

    log = where / Dir.children(where).find!(&.ends_with? ".jsonl")
    found = File.open Writer.path_for(log) do |file|
      Compress::Gzip::Reader.open(file) do |gzip|
        gzip.each_line.map { |line| JSON.parse line }.to_a
      end
    end
    hp = found.select { |line| line["kind"]? == "stat_changed" && line["stat"] == "hp" }
    expect(hp).not_to be_empty
    hp.each do |line|
      expect(line["turn"].as_i?).not_to be_nil
      expect(line["old"].as_i).to be > line["new"].as_i if line["cause"] == "attack"
    end
  end
end
