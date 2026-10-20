require "../../spec_helper"
require "../../support/recording"

Spectator.describe "the info panel selection" do
  alias InfoPanel = Roguelike::Ui::InfoPanel
  alias Line = Roguelike::Ui::Line
  alias Palette = Roguelike::Ui::Palette
  alias Panel = Roguelike::Ui::FocusRing::Panel
  alias Viewer = Roguelike::Replay::Viewer

  # A run with the info panel focused.
  def focused(rows : Int32 = 24, motion : Bool = false, clock : Bool = false,
              store : Roguelike::Save::Store? = nil) : Playing::Run
    run = Playing.open rows: rows, motion: motion, clock: clock, store: store
    run.press "Tab"
    run
  end

  # The section titles in the order they are stacked.
  def titles(run : Playing::Run) : Array(String)
    run.play.info_panel.sections.map &.title
  end

  # The title of the section the selection is in, and the selected row.
  def where(run : Playing::Run) : {String, Int32?}
    panel = run.play.info_panel
    {panel.section.title, panel.row}
  end

  # The background drawn at *x*, *y*.
  def ground(run : Playing::Run, x : Int32, y : Int32) : TermBuf::Color
    found = run.buffer.hit x, y
    raise "nothing is drawn at #{x},#{y}" unless found

    run.buffer.styles[found.cell.style].background
  end

  # The screen, then a blank row, then one row of marks for each row of the
  # screen. `S` is a cell on either selection ground, `H` a cell on the
  # header ground, and `.` any other cell.
  def marked(run : Playing::Run) : String
    marks = (0...run.buffer.height).map do |row|
      String.build do |line|
        run.buffer.width.times do |column|
          found = ground run, column, row
          line << if found == Palette.selected_header || found == Palette.selected_row
            'S'
          elsif found == Palette.header_ground
            'H'
          else
            '.'
          end
        end
      end
    end

    "#{run.text}\n\n#{marks.join '\n'}"
  end

  # Presses `Down` until the selection is on the header titled *title*.
  def down_to(run : Playing::Run, title : String) : Nil
    (titles(run).index!(title) - run.play.info_panel.at).times { run.press "Down" }
  end

  # The first row of the pack.
  def first_pack_row(run : Playing::Run) : Line
    run.play.character.pack.first
  end

  describe "on the headers" do
    it "selects the first header when the panel gains the focus" do
      run = focused
      header = run.play.character.scoring.header

      expect(where run).to eq({"Scores", nil})
      expect(run.play.info_panel.lit).to be header
      expect(ground run, header.rect.x + 3, header.rect.y).to eq Palette.selected_header
    end

    it "moves among the headers on Down and Up, and stops at the ends" do
      run = focused

      run.press "Up"
      expect(where run).to eq({"Scores", nil})

      seen = [] of String
      6.times do
        run.press "Down"
        seen << where(run)[0]
      end
      expect(seen).to eq %w[Equipment Pack Here Seen Look Look]

      run.press "Up"
      expect(where run).to eq({"Seen", nil})
    end

    it "hides the selection when the focus leaves and shows it again on return" do
      run = focused
      run.press "Down", "Down"
      header = run.play.character.packed.header

      run.press "Tab"
      expect(run.play.info_panel.lit).to be_nil
      expect(ground run, header.rect.x + 3, header.rect.y).to eq Palette.header_ground

      run.press "Shift+Tab"
      expect(where run).to eq({"Pack", nil})
      expect(run.play.info_panel.lit).to be header
    end

    it "leaves the keys alone while the map has the focus" do
      run = Playing.open
      run.press "Down", "Right", "Enter"

      expect(where run).to eq({"Scores", nil})
      expect(run.play.character.packed.expanded?).to be_false
      expect(run.turn).to eq 0
    end
  end

  describe "closing and opening" do
    it "closes on Left, opens on Right and toggles on Enter, and keeps the state" do
      store = Playing.store
      run = focused store: store
      scores = run.play.character.scoring

      run.press "Left"
      expect(scores.expanded?).to be_false
      expect(run.play.info_panel.state["scores"]).to be_false
      expect(File.read store.root / InfoPanel::FILE).to contain %("scores":false)

      run.press "Right"
      expect(scores.expanded?).to be_true
      expect(where run).to eq({"Scores", nil})

      run.press "Enter"
      expect(scores.expanded?).to be_false

      run.press "Enter"
      expect(scores.expanded?).to be_true
      expect(File.read store.root / InfoPanel::FILE).to contain %("scores":true)
    end

    it "opens a closed section on Right without going into its rows" do
      run = focused
      down_to run, "Pack"

      run.press "Right"

      expect(run.play.character.packed.expanded?).to be_true
      expect(where run).to eq({"Pack", nil})
    end
  end

  describe "in the rows" do
    it "goes into the first row on Right and walks the rows on Down" do
      run = focused

      run.press "Right"
      expect(where run).to eq({"Scores", 0})
      expect(run.play.info_panel.lit).to be run.play.character.number_names

      run.press "Down", "Down", "Down"
      expect(where run).to eq({"Scores", 3})

      run.press "Down"
      expect(where run).to eq({"Equipment", nil})
    end

    it "goes up from the first row to its own header" do
      run = focused
      run.press "Right", "Down"

      run.press "Up"
      expect(where run).to eq({"Scores", 0})

      run.press "Up"
      expect(where run).to eq({"Scores", nil})
    end

    it "goes back to the header on Left from any row" do
      run = focused
      run.press "Right", "Down", "Down"

      run.press "Left"

      expect(where run).to eq({"Scores", nil})
      expect(run.play.character.scoring.expanded?).to be_true
    end

    it "draws the selected row on the selection ground" do
      run = focused
      run.press "Right"
      row = run.play.character.number_names

      expect(ground run, row.rect.right - 2, row.rect.y).to eq Palette.selected_row
    end

    it "goes back to the header when the section closes under it" do
      run = focused
      run.press "Right", "Down"

      run.play.character.scoring.toggle
      run.render

      expect(where run).to eq({"Scores", nil})
    end
  end

  describe "a selected row" do
    it "puts the item's box up beside a pack row" do
      run = focused
      down_to run, "Pack"
      run.press "Right", "Right"

      expect(run.play.tooltip.showing?).to be_true
      expect(run.play.tooltip.target).to be first_pack_row(run)
      expect(run.play.tooltip.written.first).to eq run.game.player.inventory.entries.first[1]
        .try { |item| Roguelike::Ui::Detail.about(run.game, item).first }
    end

    it "lights the square of a Seen row on the map" do
      run = focused
      down_to run, "Seen"
      run.press "Right"
      spot = run.nearby.spot

      expect(spot).not_to be_nil
      expect(run.map.spotlight).to eq spot
    end

    it "takes the box and the light down when the focus leaves" do
      run = focused
      down_to run, "Seen"
      run.press "Right"

      run.press "Escape"

      expect(run.play.tooltip.showing?).to be_false
      expect(run.map.spotlight).to be_nil
    end
  end

  describe "with the pointer" do
    it "gives the box to the pointer over the panel and takes it back off it" do
      run = focused
      down_to run, "Pack"
      run.press "Right", "Right"
      header = run.play.character.scoring.header.rect

      run.hover header.x + 2, header.y
      expect(run.play.tooltip.showing?).to be_false

      run.hover_map 3, 3
      expect(run.play.tooltip.target).to be first_pack_row(run)
    end

    it "takes the box back on a selection key while the pointer is over the panel" do
      run = focused
      down_to run, "Pack"
      run.press "Right", "Right"
      header = run.play.character.scoring.header.rect
      run.hover header.x + 2, header.y

      run.press "Down", "Up"

      expect(run.play.tooltip.target).to be first_pack_row(run)
    end
  end

  describe "Enter on a row" do
    it "puts up the menu for a pack row" do
      run = focused
      down_to run, "Pack"
      run.press "Right", "Right"

      run.press "Enter"

      expect(run.menu.showing?).to be_true
      expect(run.menu.title.to_s).to contain "#{run.game.player.inventory.entries.first[0]} - "
    end

    it "walks to a Seen row's square on the second press, as a click does" do
      run = focused
      down_to run, "Seen"
      run.press "Right"
      start = run.at

      run.press "Enter"
      expect(run.at).to eq start

      run.press "Enter"
      expect(run.at).not_to eq start
    end

    it "walks to a picked square first" do
      run = Playing.open Playing.field(200, 80)
      run.press "_"
      run.play.ring.focus Panel::Info
      start = run.at

      run.press "l", "Enter"

      expect(run.play.aiming).to be_nil
      expect(run.at).not_to eq start
      expect(run.play.character.scoring.expanded?).to be_true
    end
  end

  describe "scrolling" do
    it "scrolls the panel to show a selection that moved off it" do
      run = focused rows: 16
      look = run.play.examine.section.header

      down_to run, "Look"

      info = run.screen.info.rect
      expect(run.screen.info.scroll_y).to be > 0
      expect(look.rect.y).to be >= info.y
      expect(look.rect.y).to be < info.y + info.height
    end

    it "eases the scroll when motion is on" do
      run = focused rows: 16, motion: true, clock: true
      run.run_timers

      down_to run, "Look"
      expect(run.armed).not_to be_empty

      run.run_timers
      run.render
      look = run.play.examine.section.header.rect
      info = run.screen.info.rect
      expect(look.y).to be < info.y + info.height
    end

    it "scrolls on Shift+Down without moving the selection" do
      run = focused rows: 16

      run.press "Shift+Down"

      expect(run.screen.info.scroll_y).to eq 1
      expect(where run).to eq({"Scores", nil})
    end
  end

  describe "the keys" do
    it "lists the selection keys under the info panel" do
      bindings = Roguelike::Ui::Keys.info_panel(Playing.open.play)
      keys = bindings.bindings.map &.to_s

      expect(keys).to contain "Up", "Down", "Left", "Right", "Enter"
    end

    it "keeps Left and Right stepping in the replay viewer off the info panel" do
      run = Playing.open viewer: Viewer.open(Recording.golden)

      run.press "Right"
      expect(run.viewer.try(&.at)).to eq 1

      run.press "Tab", "Right"
      expect(run.viewer.try(&.at)).to eq 1
      expect(run.play.info_panel.row).to eq 0
      run.viewer.try &.close
    end
  end

  describe "drawn" do
    it "draws a selected pack row and its box at 80 by 24" do
      run = focused
      down_to run, "Pack"
      run.press "Right", "Right"
      drawn = marked run

      expect(drawn).to eq Fixture.expected("screen/info-select-pack.txt", drawn)
    end
  end
end
