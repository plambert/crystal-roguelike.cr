require "../../spec_helper"
require "../../support/recording"

Spectator.describe "the way explore is heading" do
  alias Game = Roguelike::Game
  alias Play = Roguelike::Ui::Play
  alias Theme = Roguelike::Ui::Theme
  alias Library = Roguelike::Ui::ThemeLibrary
  alias Palette = Roguelike::Ui::Palette

  # A lit room with a way out at its east end that turns south out of sight.
  # Explore heads for the far end of the room first.
  HALL = [
    "################################",
    "#<.........................#####",
    "#...........................####",
    "#..........................#.###",
    "############################.###",
    "############################.###",
    "################################",
  ]

  # Where explore first heads on `HALL`.
  EXIT = {27, 2}

  # A run on *lines* with the character on the up staircase.
  def exploring(lines : Array(String) = HALL, clock : Bool = true) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("hall", lines)
    run = Playing.open Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}),
      Roguelike::Player.new("hall", *Game.entrance(floor), hit_points: hp(40))),
      60, 20, clock: clock
    run.clear_monsters
    run
  end

  # Takes one step of the walk under way. A step in place that wrote
  # nothing arms the next on `Play::HOLD` rather than `Play::STRIDE`.
  def stride(run : Playing::Run) : Nil
    run.tick(Play::STRIDE) || run.tick(Play::HOLD)
  end

  # The goal of the drawn trail. `nil` when none is drawn.
  def goal(run : Playing::Run) : {Int32, Int32}?
    run.play.trail.try &.route.last
  end

  # The style drawn on *spot* of the floor.
  def drawn_style(run : Playing::Run, spot : {Int32, Int32}) : TermBuf::Style
    cell = run.map.screen_of(*spot) || raise "#{spot} is not on the screen"
    found = run.buffer.hit *cell
    raise "nothing is drawn at #{cell}" unless found

    run.buffer.styles[found.cell.style]
  end

  # Drops something a walk stops for on *spot*.
  def drop_dagger(run : Playing::Run, spot : {Int32, Int32}) : Nil
    run.game.floor.drop *spot, Roguelike::Item.new(Roguelike::ItemKind::Dagger)
    run.game.enroll
  end

  describe "while explore walks" do
    it "draws the way to the goal" do
      run = exploring

      run.press "X"

      expect(run.play.walking?).to be_true
      expect(goal run).to eq EXIT
      expect(run.map.trailed? *EXIT).to be_true
      expect(run.map.trailed? 10, 1).to be_true
    end

    it "leaves the character's own square alone" do
      run = exploring

      run.press "X"

      expect(run.map.trailed? *run.at).to be_false
    end

    it "draws nothing when two steps or fewer are left" do
      run = exploring
      run.press "X"

      drawn = [] of Int32
      while run.play.walking?
        found = run.play.trail
        drawn << found.route.size - 1 if found
        expect(run.map.trail.size).to eq(found ? found.route.size - 1 : 0)
        stride run
      end

      expect(drawn.min).to eq Play::TRAIL_STEPS
      expect(drawn).to contain 3
    end

    it "draws the new way in place of the old when the goal changes" do
      run = exploring
      run.press "X"
      stride run
      run.game.floor.drop 8, 3, Roguelike::Item.new(Roguelike::ItemKind::Gold, count: 5)

      before = goal run
      while goal(run) == EXIT
        stride run
      end

      expect(before).to eq EXIT
      expect(goal run).to eq({8, 3})
      expect(run.map.trailed? 8, 3).to be_true
      expect(run.map.trailed? 20, 2).to be_false
    end

    it "draws on its own color, fainter than the person's way" do
      run = exploring

      run.press "X"
      run.render

      expect(drawn_style(run, {10, 1}).background).to eq Palette.explore_route
      expect(drawn_style(run, {10, 3}).background).to eq Palette.ground
    end

    it "draws under the examine cursor" do
      run = exploring
      run.press "X"
      plain = drawn_style run, {10, 1}

      run.map.cursor = {10, 1}
      run.render

      expect(drawn_style run, {10, 1}).to eq plain.reverse
    end
  end

  describe "once explore stops" do
    it "stays up after a halt until the fade timer fires" do
      run = exploring
      run.press "X"
      drop_dagger run, {12, 3}
      while run.play.walking?
        stride run
      end

      expect(run.said).to eq "A dagger comes into sight."
      expect(goal run).to eq EXIT
      expect(run.armed_for Play::ROUTE_FADE).to_not be_empty

      run.tick Play::ROUTE_FADE

      expect(run.play.trail).to be_nil
      expect(run.map.trail).to be_empty
    end

    it "stays up after a key stops the walk until the fade timer fires" do
      run = exploring
      run.press "X"
      stride run

      run.press "z"

      expect(run.play.walking?).to be_false
      expect(goal run).to eq EXIT
      expect(run.map.trailed? *EXIT).to be_true

      run.tick Play::ROUTE_FADE

      expect(run.map.trail).to be_empty
    end

    it "stays up after a click stops the walk" do
      run = exploring
      run.press "X"
      stride run

      spot = run.map.screen_of(5, 3) || raise "not on the screen"
      run.click spot[0], spot[1]

      expect(run.play.walking?).to be_false
      expect(goal run).to eq EXIT
    end

    it "comes off at once when a turn passes" do
      run = exploring
      run.press "X"
      stride run
      run.press "z"

      run.press "j"

      expect(run.play.trail).to be_nil
      expect(run.map.trail).to be_empty
    end

    it "comes off at once for a click on the map, which draws the person's way" do
      run = exploring
      run.press "X"
      stride run
      run.press "z"

      spot = run.map.screen_of(5, 3) || raise "not on the screen"
      run.click spot[0], spot[1]

      expect(run.play.trail).to be_nil
      expect(run.map.trail).to be_empty
      expect(run.map.highlighted? 5, 3).to be_true
    end

    it "comes off at once for a travel cursor" do
      run = exploring
      run.press "X"
      stride run
      run.press "z"

      run.press "_", "l"

      expect(run.map.trail).to be_empty
      expect(run.map.highlighted? run.at[0] + 1, run.at[1]).to be_true
    end

    it "comes off at once for Escape" do
      run = exploring
      run.press "X"
      stride run
      run.press "z"

      run.press "Escape"

      expect(run.map.trail).to be_empty
    end

    it "is replaced by the next explore" do
      run = exploring
      run.press "X"
      stride run
      run.press "z"
      run.press "X"

      expect(run.play.trail.try &.route.first).to eq run.at
    end

    it "is readable after a walk taken with no clock" do
      run = exploring clock: false
      drop_dagger run, {12, 3}

      run.press "X"

      expect(run.play.walking?).to be_false
      expect(run.said).to eq "A dagger comes into sight."
      expect(goal run).to eq EXIT
      expect(run.map.trailed? *EXIT).to be_true
    end
  end

  describe "a walk that is not an explore" do
    it "draws no trail for a travel" do
      run = exploring
      spot = run.map.screen_of(20, 2) || raise "not on the screen"
      run.click spot[0], spot[1]
      run.click spot[0], spot[1]

      until run.at == {20, 2}
        expect(run.play.trail).to be_nil
        stride run
      end
    end

    it "draws no trail for a visit, and takes the explore's off" do
      run = exploring clock: false
      drop_dagger run, {12, 3}
      run.press "X"
      expect(run.play.trail).to_not be_nil

      run.press "v"

      expect(run.at).to eq({12, 3})
      expect(run.play.trail).to be_nil
      expect(run.map.trail).to be_empty
    end
  end

  describe "its color" do
    it "has a value in every built-in theme, fainter than the player's way" do
      Library::BUILT_INS.each do |named|
        theme = named.theme
        trail = Palette.contrast theme.explore_route, theme.ground
        offered = Palette.contrast theme.offered, theme.ground

        expect(theme.explore_route).to_not eq theme.offered
        expect(trail).to be < offered, named.name
        expect(trail).to be > 1.05, named.name
      end
    end

    it "stands out from the default ground" do
      theme = Theme::DEFAULT

      expect(Palette.contrast theme.explore_route, theme.ground).to be >= 1.6
      expect(Palette.contrast theme.offered, theme.explore_route).to be >= 1.2
    end

    it "is listed in the theme editor" do
      expect(Theme::ENTRIES.map &.key).to contain "explore_route"
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

    it "is the same with the trail drawn as with no screen at all" do
      drawn = false
      shown = recorded((Recording.directory / "trail-shown-#{Random.rand UInt32}.jsonl").to_s) do
        game = Game.dug Roguelike::Rng.new(Recording::SEED)
        game.player.name = Recording::PLAYER
        game.floor.monsters.clear
        run = Playing.open game, 80, 30, clock: true
        8.times do
          run.press "X"
          while run.play.walking?
            drawn ||= !run.play.trail.nil?
            stride run
          end
        end
        game
      end

      bare = recorded((Recording.directory / "trail-bare-#{Random.rand UInt32}.jsonl").to_s) do
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

      expect(drawn).to be_true
      expect(shown.size).to be > 5
      expect(shown).to eq bare
    end
  end
end
