require "../../spec_helper"
require "../../support/recording"

Spectator.describe "what the rule under the map says during explore" do
  alias Game = Roguelike::Game
  alias Play = Roguelike::Ui::Play
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Reason = Roguelike::Explore::Reason
  alias Step = Roguelike::Step
  alias AsideRule = TermBuf::Widgets::AsideRule

  # A lit room with a way out at its east end that turns south out of sight.
  HALL = [
    "################################",
    "#<.........................#####",
    "#...........................####",
    "#..........................#.###",
    "############################.###",
    "############################.###",
    "################################",
  ]

  # A dark room with a door on its west side. The character starts on the
  # up staircase just inside the door and carries a candle.
  DARK = [
    "#######################################",
    "####.#................................#",
    "####.#................................#",
    "####.+<...............................#",
    "######................................#",
    "######................................#",
    "#######################################",
  ]

  # A lit corridor through two shut doors, one after the other.
  DOORS = [
    "############",
    "#<..+..+...#",
    "############",
  ]

  # A lit room with nothing left to see once the character looks.
  SHUT = [
    "##############################",
    "#<...........................#",
    "#............................#",
    "##############################",
  ]

  # A lit hall with a fountain at its east end.
  WELL = [
    "#############",
    "#...........#",
    "#.<......{..#",
    "#...........#",
    "#############",
  ]

  # Where the fountain is on `WELL`.
  BASIN = {9, 2}

  # A run on *lines* with the character on the up staircase.
  #
  # A floor that is not *lit* is dark, and the character carries a candle.
  def exploring(lines : Array(String) = HALL, columns : Int32 = 60,
                clock : Bool = true, lit : Bool = true) : Playing::Run
    floor = Roguelike::Floor.parse(Roguelike::World.id(1), lines)
    Playing.daylight floor if lit
    player = Playing.dressed(Roguelike::Player.new(floor.id, *Game.entrance(floor), hit_points: 40))
    player.inventory.add Item.new(ItemKind::Candle, lit: true) unless lit
    run = Playing.open Game.new(
      Roguelike::World.new(Playing::SEED, {floor.id => floor}), player),
      columns, 20, clock: clock
    run.clear_monsters
    run
  end

  # Takes one step of the walk under way. A step in place that wrote
  # nothing arms the next on `Play::HOLD` rather than `Play::STRIDE`.
  def stride(run : Playing::Run) : Nil
    run.tick(Play::STRIDE) || run.tick(Play::HOLD)
  end

  # Puts *item* on *spot* and lets the character see it, so the walk does
  # not stop for it coming into sight.
  def lay(run : Playing::Run, spot : {Int32, Int32}, item : Item) : Nil
    run.game.floor.drop *spot, item
    run.game.enroll
    run.game.look
    run.play.refresh
  end

  # Blessed +1 arrows the character knows the blessing of.
  def fine_arrows(count : Int32) : Item
    Item.new(ItemKind::Arrow, 1, count: count,
      blessing: Roguelike::Blessing::Blessed, blessing_known: true)
  end

  # Gives the character arrows of their own, so explore picks up more.
  def carry_arrows(run : Playing::Run) : Nil
    run.game.player.inventory.add fine_arrows(2)
  end

  # The text on the rule under the map, without the rule.
  def rule_text(run : Playing::Run) : String
    box = run.screen.rule.rect
    run.row(box.y).ljust(box.right)[box.x...box.right].strip(" ─")
  end

  describe "the text for each reason" do
    it "is plain words" do
      expect(Play.heading_for Reason::Pile, ["7 gold pieces"]).to eq "Picking up 7 gold pieces"
      expect(Play.heading_for Reason::Well).to eq "Walking to fountain"
      expect(Play.heading_for Reason::Room).to eq "Searching this room"
      expect(Play.heading_for Reason::Passage).to eq "Following the passage"
      expect(Play.heading_for Reason::Frontier).to eq "Exploring unknown areas"
      expect(Play.heading_for Reason::Unread, ["a dagger"]).to eq "Going to look at a dagger"
    end

    it "has nothing to say for a pile or an unread item with no names" do
      expect(Play.heading_for Reason::Pile).to be_nil
      expect(Play.heading_for Reason::Unread).to be_nil
    end

    it "names the first item and stands \"and more\" for the rest" do
      expect(Play.heading_for Reason::Pile, ["a dagger", "3 arrows"]).to eq "Picking up a dagger and more"
    end

    it "says what an unlogged step in place did" do
      expect(Play.doing_in_place Step::Drew).to eq "Filling your waterskin"
      expect(Play.doing_in_place Step::Moved).to be_nil
    end
  end

  describe "while explore walks" do
    it "says it is searching the room beside the floor" do
      run = exploring DARK, lit: false

      run.press "X"

      expect(run.play.doing).to eq "Searching this room"
      expect(rule_text run).to eq "Floor 1 - Searching this room"
    end

    it "says it is following the passage once in it" do
      run = exploring
      run.press "X"

      said = [] of String?
      while run.play.walking?
        said << run.play.doing
        stride run
      end

      expect(said).to contain "Following the passage"
    end

    it "says it is exploring unknown areas once the room has nothing left to see" do
      run = exploring

      run.press "X"

      expect(run.play.doing).to eq "Exploring unknown areas"
    end

    it "names gold it walks to" do
      run = exploring
      lay run, {6, 2}, Item.new(ItemKind::Gold, count: 7)

      run.press "X"

      expect(run.play.doing).to eq "Picking up 7 gold pieces"
    end

    it "keeps naming the gold on the step that picks it up" do
      run = exploring
      lay run, {6, 2}, Item.new(ItemKind::Gold, count: 7)
      run.press "X"

      until run.game.player.gold > 0 || !run.play.walking?
        stride run
      end

      expect(run.game.player.gold).to eq 7
      expect(run.play.doing).to eq "Picking up 7 gold pieces"
    end

    it "names a pile read in full with everything the character knows" do
      run = exploring
      carry_arrows run
      lay run, {6, 2}, fine_arrows(3)

      run.press "X"

      expect(run.play.doing).to eq "Picking up 3 blessed +1 arrows"
    end

    it "names a pile seen from too far off to read by its kind alone" do
      run = exploring
      carry_arrows run
      lay run, {20, 2}, fine_arrows(3)

      run.press "X"

      expect(run.play.doing).to eq "Picking up 3 arrows"
    end

    it "names an item it goes to look at by what the character made out" do
      run = exploring SHUT
      lay run, {27, 2}, Item.new(ItemKind::Dagger, 2, blessing: Roguelike::Blessing::Cursed, blessing_known: true)

      run.press "X"

      expect(run.play.doing).to eq "Going to look at a dagger"
    end

    it "says it is walking to a fountain for a dry skin" do
      run = exploring WELL
      run.game.player.sustenance.water = 0

      run.press "X"

      expect(run.play.doing).to eq "Walking to fountain"
    end
  end

  describe "a narrow screen" do
    it "keeps the floor and shortens the goal" do
      rule = AsideRule.new label: "Floor 7"
      rule.aside = "Walking to fountain"

      expect(rule.written 40).to eq " Floor 7 - Walking to fountain "
      expect(rule.written 25).to eq " Floor 7 - Walking to f… "
    end

    it "keeps the floor and drops the goal when little of it would fit" do
      rule = AsideRule.new label: "Floor 7"
      rule.aside = "Walking to fountain"

      expect(rule.written 18).to eq " Floor 7 "
      expect(rule.written 6).to eq " Floor"
    end

    it "keeps the floor under the narrowest map" do
      run = exploring columns: Roguelike::Ui::Screen::INFO_MINIMUM_COLUMNS
      carry_arrows run
      lay run, {6, 2}, fine_arrows(3)

      run.press "X"

      expect(run.play.doing).to eq "Picking up 3 blessed +1 arrows"
      expect(run.screen.rule.rect.width).to eq Roguelike::Ui::Screen::LEAST_MAP_COLUMNS
      expect(rule_text run).to eq "Floor 1 - Picking up 3 blessed +…"
    end
  end

  describe "a step taken in place" do
    it "leaves the rule alone when it writes to the log" do
      run = exploring
      run.press "X"
      before = run.play.doing
      run.game.player.sustenance.thirst = Roguelike::Sustenance::Tuning::THIRST_FIRST
      written = run.game.log.written

      stride run

      expect(run.said).to eq "You drink from your waterskin."
      expect(run.game.log.written).to be > written
      expect(run.play.doing).to eq before
      expect(run.armed_for Play::STRIDE).to_not be_empty
      expect(run.armed_for Play::HOLD).to be_empty
    end

    it "holds when it only says the last line again" do
      run = exploring DOORS
      run.press "X"

      held = [] of String?
      while run.play.walking?
        held << run.play.doing unless run.armed_for(Play::HOLD).empty?
        run.tick
      end

      expect(run.log).to contain "You open the door. (x 2)"
      expect(held).to eq ["Opening a door"]
    end

    it "says what it did and holds when it writes nothing" do
      run = exploring WELL
      run.game.player.sustenance.water = 0
      run.press "X"
      until run.at == BASIN
        stride run
      end
      until run.play.doing == "Filling your waterskin" || !run.play.walking?
        stride run
      end

      expect(run.play.doing).to eq "Filling your waterskin"
      expect(rule_text run).to eq "Floor 1 - Filling your waterskin"
      expect(run.armed_for Play::HOLD).to_not be_empty
      expect(run.armed_for Play::STRIDE).to be_empty
    end

    it "waits longer than a stride, about long enough to read" do
      expect(Play::HOLD).to be > Play::STRIDE
      expect(Play::HOLD).to eq 250.milliseconds
    end
  end

  describe "once explore stops" do
    it "shows the floor alone at once" do
      run = exploring
      run.press "X"
      stride run

      run.press "z"

      expect(run.play.doing).to be_nil
      expect(rule_text run).to eq "Floor 1"
      expect(run.play.trail).to_not be_nil
    end

    it "shows the floor alone after the walk ends by itself" do
      run = exploring clock: false

      run.press "X"

      expect(run.play.walking?).to be_false
      expect(run.play.doing).to be_nil
      expect(rule_text run).to eq "Floor 1"
    end

    it "says nothing for a travel" do
      run = exploring
      spot = run.map.screen_of(20, 2) || raise "not on the screen"
      run.click spot[0], spot[1]
      run.click spot[0], spot[1]

      until run.at == {20, 2}
        expect(run.play.doing).to be_nil
        stride run
      end
    end
  end

  describe "a replay" do
    # The acts and checks of a run recorded to *where* by *block*.
    def recorded(where : String, & : -> Game) : Array(String)
      Recording.recording(where) { yield }
      Recording.read(where).records.compact_map do |record|
        record.to_json if record.is_a?(Roguelike::Replay::Act) || record.is_a?(Roguelike::Replay::Check)
      end
    end

    it "is the same with the goal shown as with no screen at all" do
      shown_any = false
      shown = recorded((Recording.directory / "goal-shown-#{Random.rand UInt32}.jsonl").to_s) do
        game = Game.dug Roguelike::Rng.new(Recording::SEED)
        game.player.name = Recording::PLAYER
        game.floor.monsters.clear
        run = Playing.open game, 80, 30, clock: true
        8.times do
          run.press "X"
          while run.play.walking?
            shown_any ||= !run.play.doing.nil?
            run.tick
          end
        end
        game
      end

      bare = recorded((Recording.directory / "goal-bare-#{Random.rand UInt32}.jsonl").to_s) do
        game = Game.dug Roguelike::Rng.new(Recording::SEED)
        game.player.name = Recording::PLAYER
        game.floor.monsters.clear
        8.times do
          walk = game.exploring
          while game.stride walk
          end
        end
        game
      end

      expect(shown_any).to be_true
      expect(shown.size).to be > 5
      expect(shown).to eq bare
    end
  end
end
