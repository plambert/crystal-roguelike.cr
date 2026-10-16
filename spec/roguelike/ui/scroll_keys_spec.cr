require "../../spec_helper"
require "../../support/recording"

Spectator.describe "the scrolling keys" do
  alias Panel = Roguelike::Ui::FocusRing::Panel
  alias Viewer = Roguelike::Replay::Viewer

  # A run on a field far larger than the map pane.
  def field(motion : Bool = false, clock : Bool = false) : Playing::Run
    Playing.open Playing.field(200, 80), motion: motion, clock: clock
  end

  # A run on a short screen, so the info panel has more than it can show.
  def crowded : Playing::Run
    run = Playing.open rows: 16
    run.play.ring.focus Panel::Info
    run
  end

  # A run with *count* messages said, with the log at its newest line.
  def talkative(count : Int32 = 40) : Playing::Run
    run = Playing.open
    run.clear_monsters
    count.times { |number| run.game.log.add "Something number #{number} happened." }
    run.play.refresh
    run.render

    run.pager.to_newest

    run.play.ring.focus Panel::Log
    run
  end

  describe "on the map" do
    it "scrolls a row on Shift+Down and Shift+Up, and moves nobody" do
      run = field
      start = run.map.camera

      run.press "Shift+Down"
      expect(run.map.camera).to eq({start[0], start[1] + 1})

      run.press "Shift+Up"
      expect(run.map.camera).to eq start
      expect(run.turn).to eq 0
    end

    it "scrolls a column on Shift+Right and Shift+Left" do
      run = field
      start = run.map.camera

      run.press "Shift+Right"
      expect(run.map.camera).to eq({start[0] + 1, start[1]})

      run.press "Shift+Left"
      expect(run.map.camera).to eq start
    end

    it "scrolls a page on PageDown" do
      run = field
      start = run.map.camera

      run.press "PageDown"

      expect(run.map.camera).to eq({start[0], start[1] + run.map.grid.page})
    end

    it "goes to the top of the floor on Home and the bottom on End" do
      run = field
      column = run.map.camera[0]

      run.press "Home"
      expect(run.map.camera).to eq({column, 0})

      run.press "End"
      expect(run.map.camera).to eq({column, run.map.grid.max_scroll[1]})
    end

    it "stops at the edge of the floor" do
      run = field
      run.press "Home"

      run.press "Shift+Up"

      expect(run.map.camera[1]).to eq 0
    end

    it "lets the next turn put the camera back" do
      run = field
      start = run.map.camera

      run.press "End"
      run.press "."

      expect(run.map.camera).to eq start
    end

    it "keeps the view where it was scrolled while no turn passes" do
      run = field

      run.press "End"
      scrolled = run.map.camera
      run.press "Shift+Left"
      run.hover 5, 5

      expect(run.map.camera).to eq({scrolled[0] - 1, scrolled[1]})
    end

    it "scrolls in the replay viewer, where Left and Right keep stepping" do
      run = Playing.open viewer: Viewer.open(Recording.golden)
      start = run.map.camera

      run.press "Right"
      expect(run.viewer.try(&.at)).to eq 1
      expect(run.map.camera).to eq start

      run.press "Shift+Right"
      expect(run.viewer.try(&.at)).to eq 1
      run.viewer.try &.close
    end
  end

  describe "Enter on the map" do
    it "does nothing while the character is on screen" do
      run = field
      start = run.map.camera

      run.press "Enter"

      expect(run.map.camera).to eq start
      expect(run.turn).to eq 0
    end

    it "centers on the character who is off screen" do
      run = field
      start = run.map.camera
      run.press "End"
      expect(run.map.screen_of(*run.at)).to be_nil

      run.press "Enter"

      expect(run.map.screen_of(*run.at)).not_to be_nil
      expect(run.map.camera).to eq start
    end

    it "keeps the camera there on the next turn" do
      run = field
      run.press "End"
      run.press "Enter"
      centered = run.map.camera

      run.press "."

      expect(run.map.camera).to eq centered
    end

    it "looses a shot that is waiting, with the character on screen" do
      run = Playing.open Playing.field(200, 80)
      run.press "_"
      expect(run.play.aiming).not_to be_nil
      start = run.at

      run.press "l", "Enter"

      expect(run.play.aiming).to be_nil
      expect(run.at).not_to eq start
    end

    it "walks to the picked square from any panel" do
      run = Playing.open Playing.field(200, 80)
      run.press "_"
      run.play.ring.focus Panel::Log
      start = run.at

      run.press "l", "Enter"

      expect(run.play.aiming).to be_nil
      expect(run.at).not_to eq start
    end
  end

  describe "animated" do
    it "writes the first frame at once and arrives on timers" do
      run = field motion: true, clock: true
      start = run.map.camera

      run.press "PageDown"
      first = run.map.camera
      expect(first[1]).to be > start[1]
      expect(run.armed).not_to be_empty

      run.run_timers
      expect(run.map.camera).to eq({start[0], start[1] + run.map.grid.page})
    end

    it "arrives in one frame with motion off" do
      run = field motion: false, clock: true

      run.press "PageDown"

      expect(run.armed).to be_empty
    end
  end

  describe "on the info panel" do
    it "scrolls a row on Shift+Down and back on Shift+Up" do
      run = crowded
      expect(run.screen.info.max_scroll[1]).to be > 1

      run.press "Shift+Down"
      expect(run.screen.info.scroll_y).to eq 1

      run.press "Shift+Up"
      expect(run.screen.info.scroll_y).to eq 0
    end

    it "scrolls a page on PageDown, and to either end on End and Home" do
      run = crowded
      limit = run.screen.info.max_scroll[1]

      run.press "PageDown"
      expect(run.screen.info.scroll_y).to eq Math.min(run.screen.info.page, limit)

      run.press "End"
      expect(run.screen.info.scroll_y).to eq limit

      run.press "Home"
      expect(run.screen.info.scroll_y).to eq 0
    end

    it "leaves the map camera alone" do
      run = crowded
      start = run.map.camera

      run.press "Shift+Down", "PageDown", "End"

      expect(run.map.camera).to eq start
    end

    it "does not scroll sideways, and takes no turn on Enter" do
      run = crowded
      before = run.rows

      run.press "Shift+Right"
      expect(run.rows).to eq before

      run.press "Enter"
      expect(run.turn).to eq 0
    end
  end

  describe "on the log" do
    it "scrolls a line on Shift+Up and back on Shift+Down" do
      run = talkative

      run.press "Shift+Up"
      expect(run.pager.back).to eq 1

      run.press "Shift+Down"
      expect(run.pager.back).to eq 0
    end

    it "scrolls a page on PageUp" do
      run = talkative

      run.press "PageUp"

      expect(run.pager.back).to eq run.pager.page
    end

    it "goes to the oldest line on Home and the newest on End" do
      run = talkative

      run.press "Home"
      expect(run.pager.scroll_y).to eq 0

      run.press "End"
      expect(run.pager.back).to eq 0
    end

    it "scrolls to the end on Enter" do
      run = talkative
      run.press "PageUp", "Shift+Up"

      run.press "Enter"

      expect(run.pager.back).to eq 0
      expect(run.turn).to eq 0
    end

    it "leaves the character where they are" do
      run = talkative
      start = run.at

      run.press "Shift+Up", "End", "Enter"

      expect(run.at).to eq start
    end

    it "reads on past a turn that said more than fits" do
      run = Playing.open
      run.clear_monsters
      run.play.ring.focus Panel::Log
      12.times { |number| run.game.log.add "Something number #{number} happened." }
      run.play.refresh
      run.render
      parked = run.pager.back
      expect(parked).to be > 0

      run.press "Shift+Down"

      expect(run.pager.back).to eq parked - 1
    end
  end

  describe "the wheel" do
    it "scrolls the log under the pointer without moving the focus" do
      run = talkative
      run.play.ring.focus Panel::Map

      run.wheel 40, 21, up: true

      expect(run.pager.back).to be > 0
      expect(run.play.ring.current).to eq Panel::Map
    end

    it "scrolls the map under the pointer without moving the focus" do
      run = field
      run.play.ring.focus Panel::Log
      start = run.map.camera
      spot = run.on_map 10, 5

      run.wheel *spot, up: false

      expect(run.map.camera[1]).to be > start[1]
      expect(run.play.ring.current).to eq Panel::Log
    end

    it "scrolls the info panel under the pointer without moving the focus" do
      run = crowded
      run.play.ring.focus Panel::Map
      box = run.screen.info.rect

      run.wheel box.x + 2, box.y + 2, up: false

      expect(run.screen.info.scroll_y).to be > 0
      expect(run.play.ring.current).to eq Panel::Map
    end
  end
end
