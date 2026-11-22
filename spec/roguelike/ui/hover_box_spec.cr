require "../../spec_helper"

Spectator.describe "the hover box" do
  alias Play = Roguelike::Ui::Play
  alias HoverBox = Roguelike::Ui::HoverBox
  alias Keys = Roguelike::Ui::Keys
  alias ConsolePane = Roguelike::Ui::ConsolePane
  alias Command = Roguelike::Ui::Command
  alias Commands = Roguelike::Ui::Commands
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Options = Roguelike::Options
  alias Scheme = Roguelike::Options::ControlScheme
  alias Rect = TermBuf::Rect

  # The character stands at the west end.
  #
  #     (4, 2) a dagger      (6, 2) a bow and a dozen arrows
  #     (5, 3) nothing       (16, 2) a spear by the east wall
  ROOM = [
    "###################",
    "#.................#",
    "#.................#",
    "#.................#",
    "###################",
  ]

  # A run on `ROOM` with a clock to fire by hand and the mouse on.
  def room(scheme : Scheme = Scheme::Traditional, clock : Bool = true,
           console : Bool = false) : Playing::Run
    options = Options.new
    options.control_scheme = scheme
    Options.current = options

    floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
    floor.drop 4, 2, Item.new(Kind::Dagger)
    floor.drop 6, 2, Item.new(Kind::Bow)
    floor.drop 6, 2, Item.new(Kind::Arrow, count: 12)
    floor.drop 16, 2, Item.new(Kind::Spear)
    player = Roguelike::Player.new "room", 1, 1, hit_points: 40
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}), player

    run = Playing.open game, clock: clock, console: console
    run.clear_monsters
    run.play.mousing = true
    run
  end

  # Where square *spot* of the floor is drawn.
  def on_screen(run : Playing::Run, spot : {Int32, Int32}) : {Int32, Int32}
    run.map.screen_of(spot[0], spot[1]) || raise "#{spot} is not on the screen"
  end

  # The pointer moving onto square *spot* of the floor.
  def hover(run : Playing::Run, spot : {Int32, Int32}) : Nil
    run.hover *on_screen(run, spot)
  end

  # The pointer resting on *spot* until the dwell is over.
  def rest(run : Playing::Run, spot : {Int32, Int32}) : Nil
    hover run, spot
    run.tick Play::HOVER_DWELL
    run.render
  end

  # Whether the box is on the screen.
  def up?(run : Playing::Run) : Bool
    box = run.play.hover_box
    box.showing? && !box.hidden?
  end

  # What the box says.
  def written(run : Playing::Run) : Array(String)
    run.play.hover_box.written
  end

  after_each { Options.current = nil }

  describe "the key" do
    it "is the backquote, listed in the help" do
      run = room

      found = run.play.sections.flat_map(&.bindings.bindings).select { |binding| binding.to_s == "`" }

      expect(Keys::HOVER).to eq "`"
      expect(found.map &.description).to eq ["show what is under the pointer beside it"]
    end

    it "turns hover mode on and off in both schemes" do
      {Scheme::Traditional, Scheme::Modern}.each do |scheme|
        run = room scheme

        run.press Keys::HOVER
        expect(run.play.hovering?).to be_true

        run.press Keys::HOVER
        expect(run.play.hovering?).to be_false
      end
    end

    it "is in the modern action catalog" do
      run = room Scheme::Modern

      expect(Commands.all.map &.id).to contain Command::HoverBox

      run.press "r"
      6.times { run.press "d" }
      index = run.menu.entries.index(&.text.starts_with?("Hover box"))
      expect(index).not_to be_nil
      run.play.selection_menu.select_index index || 0
      run.press "f"

      expect(run.play.hovering?).to be_true
    end

    it "does not open the debug console" do
      run = room console: true

      run.press "`"

      expect(run.console.try &.showing?).to be_false
      expect(run.play.hovering?).to be_true
    end

    it "leaves the console on the tilde" do
      run = room console: true

      run.press "~"

      expect(run.console.try &.showing?).to be_true
      expect(run.play.hovering?).to be_false
    end
  end

  describe "the info panel" do
    it "lists the items while hover mode is off" do
      run = room

      hover run, {4, 2}

      expect(run.examine.litter.hidden?).to be_false
      expect(run.examine.litter.text).to eq "Here: a dagger"
    end

    it "loses the list while hover mode is on and gets it back after" do
      run = room

      run.press Keys::HOVER
      hover run, {4, 2}
      expect(run.examine.litter.hidden?).to be_true
      expect(run.examine.items).to eq ["a dagger"]

      run.press Keys::HOVER
      expect(run.examine.litter.hidden?).to be_false
      expect(run.examine.litter.text).to eq "Here: a dagger"
    end

    it "keeps the list for the examine cursor" do
      run = room

      run.press Keys::HOVER
      run.press "x"

      run.press "l", "l", "l", "j"
      expect(run.examiner.spot).to eq({4, 2})
      expect(run.examine.litter.hidden?).to be_false
    end
  end

  describe "the dwell" do
    it "is about a third of a second" do
      expect(Play::HOVER_DWELL).to be >= 250.milliseconds
      expect(Play::HOVER_DWELL).to be <= 500.milliseconds
    end

    it "puts nothing up before the delay and the box after it" do
      run = room
      run.press Keys::HOVER

      hover run, {6, 2}
      expect(up? run).to be_false
      expect(run.armed_for(Play::HOVER_DWELL).size).to eq 1

      run.tick Play::HOVER_DWELL
      run.render

      expect(up? run).to be_true
      expect(written run).to eq ["Here", "a bow", "12 arrows"]
    end

    it "names each item as the character has made it out, as the panel does" do
      run = room
      run.press Keys::HOVER

      rest run, {16, 2}

      expect(written(run)[1..]).to eq run.examine.items
    end

    it "takes the box down on the next square and puts it up after a new dwell" do
      run = room
      run.press Keys::HOVER
      rest run, {4, 2}

      hover run, {6, 2}
      expect(up? run).to be_false
      expect(run.armed_for(Play::HOVER_DWELL).size).to eq 1

      run.tick Play::HOVER_DWELL
      run.render
      expect(up? run).to be_true
      expect(written(run)[1]).to eq "a bow"
    end

    it "draws nothing while the pointer sweeps across the map" do
      run = room
      run.press Keys::HOVER

      (2..16).each do |column|
        hover run, {column, 2}
        expect(up? run).to be_false
        expect(run.armed_for(Play::HOVER_DWELL).size).to eq 1
      end
    end

    it "keeps the box up while reports come from the same square" do
      run = room
      run.press Keys::HOVER
      rest run, {4, 2}

      hover run, {4, 2}

      expect(up? run).to be_true
      expect(run.armed_for(Play::HOVER_DWELL)).to be_empty
    end

    it "puts the box up at once on a terminal with no clock" do
      run = room clock: false
      run.press Keys::HOVER

      hover run, {4, 2}

      expect(up? run).to be_true
    end

    it "arms nothing while hover mode is off" do
      run = room

      hover run, {4, 2}

      expect(run.armed_for(Play::HOVER_DWELL)).to be_empty
      expect(up? run).to be_false
    end
  end

  describe "a square with nothing to list" do
    it "shows no box" do
      run = room
      run.press Keys::HOVER

      rest run, {5, 3}

      expect(up? run).to be_false
    end
  end

  describe "where the box goes" do
    it "never covers the square and stays on the screen" do
      run = room
      run.press Keys::HOVER

      {4, 16}.each do |column|
        rest run, {column, 2}
        cell = on_screen run, {column, 2}
        box = run.play.hover_box.rect
        screen = run.session.app.tree.screen

        expect(box.contains? cell[0], cell[1]).to be_false
        expect(box.x).to be >= screen.x
        expect(box.right).to be <= screen.right
        expect(box.y).to be >= screen.y
        expect(box.bottom).to be <= screen.bottom
      end
    end

    it "goes to the right of the square, a column clear of it" do
      expect(HoverBox.place(Rect.new(0, 0, 80, 24), {10, 5}, {20, 4})).to eq({12, 5})
    end

    it "flips to the left near the right edge" do
      expect(HoverBox.place(Rect.new(0, 0, 80, 24), {70, 5}, {20, 4})).to eq({49, 5})
    end

    it "moves up near the bottom edge, still beside the square" do
      expect(HoverBox.place(Rect.new(0, 0, 80, 24), {10, 22}, {20, 6})).to eq({12, 18})
    end

    it "goes below the square when neither side has room" do
      expect(HoverBox.place(Rect.new(0, 0, 30, 24), {15, 5}, {20, 4})).to eq({5, 6})
    end

    it "goes above the square when neither side nor below has room" do
      expect(HoverBox.place(Rect.new(0, 0, 30, 24), {15, 21}, {20, 4})).to eq({5, 17})
    end

    it "is sized to its widest line" do
      expect(HoverBox.size(["Here", "a long spear of some kind"])).to eq({29, 4})
      expect(HoverBox.size(["Here", "a bow"])).to eq({HoverBox::LEAST_WIDTH, 4})
    end

    it "names six items and says how many more there are" do
      items = (1..9).map { |count| "#{count} arrows" }

      expect(HoverBox.lines(items)).to eq ["Here"] + items.first(6) + ["and 3 more"]
      expect(HoverBox.lines(items.first(7)).size).to eq 8
      expect(HoverBox.lines([] of String)).to be_empty
    end
  end

  describe "coming down" do
    def shown : Playing::Run
      run = room
      run.press Keys::HOVER
      rest run, {6, 2}
      raise "the box did not go up" unless up? run
      run
    end

    it "comes down on any key" do
      run = shown

      run.press "Ctrl+G"

      expect(up? run).to be_false
    end

    it "comes down when a turn passes" do
      run = shown
      turn = run.turn

      run.play.live_wait
      run.render

      expect(run.turn).to be > turn
      expect(up? run).to be_false
    end

    it "is kept off the screen by a modal box and stays down after it" do
      run = shown

      run.play.show_options
      run.render
      expect(up? run).to be_false
      expect(run.text).not_to contain "12 arrows"

      run.press "Escape"
      expect(run.play.hover_box.showing?).to be_false
    end

    it "comes down when the pointer leaves the map" do
      run = shown

      run.hover 0, 0

      expect(up? run).to be_false
    end

    it "comes down when a drag starts" do
      run = shown
      at = on_screen run, {6, 2}

      run.mouse TermBuf::Input::Mouse::Button::Right, TermBuf::Input::Mouse::Action::Press, *at

      expect(up? run).to be_false
    end

    it "comes down when mouse reporting is turned off" do
      run = shown

      run.play.mousing = false
      run.render

      expect(up? run).to be_false
    end

    it "comes down when hover mode is turned off" do
      run = shown

      run.press Keys::HOVER

      expect(up? run).to be_false
    end

    it "comes back only after a new dwell" do
      run = shown

      run.press "Ctrl+G"
      hover run, {6, 2}
      expect(up? run).to be_false

      hover run, {4, 2}
      expect(up? run).to be_false
      run.tick Play::HOVER_DWELL
      run.render
      expect(up? run).to be_true
    end
  end

  describe "the screen" do
    it "draws the box over the map beside the pointer" do
      run = room
      run.press Keys::HOVER
      rest run, {6, 2}

      drawn = run.text
      expect(drawn).to eq Fixture.expected("screen/hover-box.txt", drawn)
    end
  end

  describe "the game" do
    it "takes no turn and changes nothing in the run" do
      run = room
      turn = run.turn
      log = run.log.dup

      run.press Keys::HOVER
      rest run, {6, 2}
      rest run, {4, 2}
      run.press Keys::HOVER

      expect(run.turn).to eq turn
      expect(run.log).to eq log
      expect(run.at).to eq({1, 1})
    end
  end
end
