require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Explore::Settings do
  alias Action = Roguelike::Action
  alias Explore = Roguelike::Explore
  alias Floor = Roguelike::Floor
  alias Game = Roguelike::Game
  alias Halt = Roguelike::Halt
  alias Item = Roguelike::Item
  alias Monster = Roguelike::Monster
  alias Settings = Roguelike::Explore::Settings
  alias Species = Roguelike::Species
  alias Verifier = Roguelike::Replay::Verifier

  SEED = 20261028_u64

  # A short corridor running north into a long one running east. Nothing of
  # the east corridor is in sight from the staircase.
  MEETING = [
    "#########################",
    "#.......................#",
    "########.################",
    "########.################",
    "########<################",
    "#########################",
  ]

  # The far end of the east corridor in `MEETING`.
  FAR = {23, 1}

  # A lit room with a corridor out of its east side that bends south out of
  # sight.
  SIDE_ROOM = [
    "########################",
    "#.....##################",
    "#<...................###",
    "#.....##############.###",
    "####################.###",
    "####################...#",
    "########################",
  ]

  # A square of `SIDE_ROOM` off the way to the bend.
  ASIDE = {4, 3}

  # A long corridor with a dead end at each end.
  DEAD_ENDS = [
    "########################################",
    "########################################",
    "##....................................##",
    "########################################",
    "########################################",
  ]

  # A game on *lines*, the character on the up staircase or at *at*.
  def played(lines : Array(String), at : {Int32, Int32}? = nil) : Game
    floor = Floor.parse "here", lines
    floor.ambient = 1
    player = Roguelike::Player.new "here", *(at || Game.entrance(floor)), hit_points: 40

    Game.new Roguelike::World.new(SEED, {"here" => floor}), player
  end

  # Gives *game* the settings *text* reads as.
  def tuned(game : Game, text : String) : Nil
    verdict = game.perform Action::Configure.new(Settings.parse text)
    expect(verdict.refused?).to be_false
  end

  # Every square of *game*'s floor known, except those *hidden* holds for.
  def knowing_but(game : Game, &hidden : {Int32, Int32} -> Bool) : Nil
    ground = game.floor
    ground.rows.times do |row|
      ground.columns.times do |column|
        game.player.knowledge.see ground, column, row unless hidden.call({column, row})
      end
    end
  end

  # The square explore on *game* heads for under *settings*.
  def heading(game : Game, settings : Settings) : {Int32, Int32}?
    ground = game.floor
    Explore.route(game.knowledge, game.player.at, ground.columns, ground.rows,
      settings: settings).last?
  end

  describe ".parse" do
    it "reads numbers and toggles over the defaults" do
      found = Settings.parse "reach=2, gold=off,pickup=no,stop-stairs=on"

      expect(found.reach).to eq 2
      expect(found.gold?).to be_false
      expect(found.pickup?).to be_false
      expect(found.stop_stairs?).to be_true
      expect(found.pocket).to eq Roguelike::Chambers::BEHIND
      expect(found.unread?).to be_true
    end

    it "keeps only the stops stop= names" do
      found = Settings.parse "stop=attacked+stairs"

      expect(found.stop_attacked?).to be_true
      expect(found.stop_stairs?).to be_true
      expect(found.stop_creature?).to be_false
      expect(found.stop_hurt?).to be_false
      expect(found.stop_item?).to be_false
      expect(found.stop_message?).to be_false
    end

    it "turns every stop off with stop=none" do
      found = Settings.parse "stop=none"

      expect(Settings::STOPS.values.map { |key| found[key] }.uniq!).to eq [false]
    end

    it "starts again from the defaults on default" do
      base = Settings.parse "reach=1"

      expect(Settings.parse("default,gold=off", base).reach).to eq Explore::REACH
    end

    it "refuses what it cannot read" do
      expect { Settings.parse "speed=3" }.to raise_error(ArgumentError, /no explore setting/)
      expect { Settings.parse "gold=maybe" }.to raise_error(ArgumentError, /on or off/)
      expect { Settings.parse "reach=far" }.to raise_error(ArgumentError, /number/)
      expect { Settings.parse "reach=99" }.to raise_error(ArgumentError, /out of range/)
      expect { Settings.parse "stop=dragons" }.to raise_error(ArgumentError, /no stop/)
      expect { Settings.parse "gold" }.to raise_error(ArgumentError, /key=value/)
    end
  end

  describe "configure" do
    it "takes no turn and is never offered" do
      game = played SIDE_ROOM
      game.look

      tuned game, "gold=off"

      expect(game.turn).to eq 0
      expect(game.explore_settings.gold?).to be_false
      expect(game.legal.map &.class).not_to contain Action::Configure
    end

    it "is refused with a number out of range, and changes nothing" do
      game = played SIDE_ROOM
      settings = Settings.new
      settings.reach = -1

      expect(game.perform(Action::Configure.new settings).refused?).to be_true
      expect(game.explore_settings.default?).to be_true
    end

    it "reads a line with fields left out as their defaults" do
      action = Action.from_json(%({"t":"configure","explore":{"gold":false}}))

      found = action.as(Action::Configure).explore.as(Settings)
      expect(found.gold?).to be_false
      expect(found.reach).to eq Explore::REACH
      expect(Action.from_json(action.to_json).to_json).to eq action.to_json
    end

    it "is in a save only while it differs from the defaults" do
      game = played SIDE_ROOM
      expect(JSON.parse(game.to_json).as_h.has_key? "explore_settings").to be_false

      tuned game, "reach=2"
      back = Game.from_json game.to_json
      expect(back.explore_settings.reach).to eq 2

      tuned game, "default"
      expect(JSON.parse(game.to_json).as_h.has_key? "explore_settings").to be_false
    end

    it "replays the same walk from the log" do
      where = (Recording.directory / "configured-#{Random.rand UInt32}.jsonl").to_s

      game = Recording.recording where do
        dug = Game.dug Roguelike::Rng.new(Recording::SEED)
        dug.player.name = Recording::PLAYER
        dug.floor.monsters.clear
        tuned dug, "reach=0,gold=off,stop=none"
        dug.explore
        tuned dug, "pocket=2,rooms=off"
        dug.explore
        dug
      end

      expect(game.turn).to be > 0
      expect(Verifier.check(where).ok?).to be_true
    end
  end

  describe "where explore walks" do
    it "leaves gold alone with gold off" do
      game = played SIDE_ROOM
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Gold, count: 7)
      game.enroll
      tuned game, "gold=off"

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.player.gold).to eq 0
      expect(game.floor.items(*ASIDE).size).to eq 1
    end

    it "still walks to gold with every search for items off" do
      game = played SIDE_ROOM
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Gold, count: 7)
      game.enroll
      tuned game, "pickup=off,unread=off"

      game.explore

      expect(game.player.gold).to eq 7
    end

    it "leaves the quiver's arrows with pickup off" do
      game = played SIDE_ROOM
      game.player.inventory.add Item.new(Roguelike::ItemKind::Bow)
      game.player.inventory.add Item.new(Roguelike::ItemKind::Arrow, count: 2)
      game.wield 'a'
      game.wield 'b'
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Arrow, count: 5)
      game.enroll
      tuned game, "pickup=off"

      game.explore

      expect(game.player.quivered.try &.count).to eq 2
      expect(game.floor.items(*ASIDE).size).to eq 1
    end

    it "is not offered for gold alone with gold off" do
      game = played SIDE_ROOM
      game.floor.drop *ASIDE, Item.new(Roguelike::ItemKind::Gold, count: 2)
      knowing_but(game) { false }
      game.look
      expect(game.legal.map &.class).to contain Action::Explore

      tuned game, "gold=off"

      expect(game.legal.map &.class).not_to contain Action::Explore
    end

    it "goes by distance alone with reach 0" do
      game = played DEAD_ENDS, at: {8, 2}
      knowing_but(game) { |spot| spot[1] == 2 && ({2, 3}.includes?(spot[0]) || (11..14).includes?(spot[0])) }

      expect(heading game, Settings.new).to eq({4, 2})
      expect(heading game, Settings.parse("reach=0")).to eq({10, 2})
    end

    it "counts a pocket larger than the pocket size as open ground" do
      game = played DEAD_ENDS, at: {8, 2}
      knowing_but(game) { |spot| spot[1] == 2 && ({2, 3}.includes?(spot[0]) || (11..14).includes?(spot[0])) }

      expect(heading game, Settings.parse("pocket=4")).to eq({4, 2})
      expect(heading game, Settings.parse("pocket=2")).to eq({10, 2})
    end
  end

  describe "what stops a walk" do
    it "walks on past a creature coming into view with that stop off" do
      game = played MEETING
      game.floor.place Monster.new(Species::Goblin, *FAR, "band-one")
      tuned game, "stop=hurt"

      went = game.explore

      expect(went.halt).not_to eq Halt::Creature
      expect(game.log.lines).not_to contain "You stop. A goblin warrior comes into view."
    end

    it "stops when attacked with that stop on, though the blow misses" do
      game = played SIDE_ROOM
      game.floor.place Monster.new(Roguelike::Kind::GoblinScout, 5, 1, "scouts")
      game.enroll
      tuned game, "stop=attacked"

      went = game.explore

      expect(went.halt).to eq Halt::Attacked
      expect(game.log.lines).to contain "The goblin scout misses you."
      expect(game.log.last?).to eq "You stop. You are under attack."
    end

    it "walks on through every attack with every stop off" do
      game = played SIDE_ROOM
      game.floor.place Monster.new(Roguelike::Kind::GoblinScout, 5, 1, "scouts")
      game.enroll
      tuned game, "stop=none"

      went = game.explore

      expect(went.halt).to eq Halt::Explored
      expect(game.player.hit_points).to be < 40
    end

    it "stops when it finds the stairs down with that stop on" do
      lines = MEETING.dup
      lines[1] = "#......................>#"
      game = played lines
      tuned game, "stop_stairs=on"

      went = game.explore

      expect(went.halt).to eq Halt::Stairs
      expect(game.log.last?).to eq "You stop. You have found the stairs down."
    end

    it "does not stop for the stairs down by default" do
      lines = MEETING.dup
      lines[1] = "#......................>#"
      game = played lines

      expect(game.explore.halt).not_to eq Halt::Stairs
    end
  end
end
