require "../../spec_helper"

Spectator.describe "the context menu on the map" do
  alias Action = TermBuf::Input::Mouse::Action
  alias Button = TermBuf::Input::Mouse::Button
  alias Terrain = Roguelike::Terrain
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Scheme = Roguelike::Options::ControlScheme
  alias Verb = Roguelike::Ui::ContextVerb
  alias Menu = Roguelike::Ui::ContextMenu
  alias Errand = Roguelike::Ui::ContextErrand
  alias Halt = Roguelike::Halt

  # The character stands on the up staircase at the west end.
  #
  #     (4, 4) a shut door     (6, 4) an open door
  #     (5, 2) a fountain      (2, 3) the staircase down
  #     (8, 2) a dagger
  ROOM = [
    "###########",
    "#<........#",
    "#....{....#",
    "#.>.......#",
    "####+#'####",
  ]

  # A long corridor with a shut door part way along it.
  CORRIDOR = [
    "#################",
    "#<.....+.......>#",
    "#################",
  ]

  # A run on *lines*, the character at *start*. The mouse is on.
  def room(lines : Array(String) = ROOM, start : {Int32, Int32} = {1, 1},
           carrying : Array(Item) = [] of Item, clock : Bool = false,
           mouse : Bool = true) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("room", lines)
    floor.drop 8, 2, Item.new(Kind::Dagger) if lines == ROOM
    player = Roguelike::Player.new "room", start[0], start[1], hit_points: hp(40)
    carrying.each { |item| player.inventory.add item }
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}), player

    run = Playing.open game, clock: clock
    run.clear_monsters
    run.play.mousing = mouse
    run
  end

  # A right click on square *spot* of the floor.
  def right_click(run : Playing::Run, spot : {Int32, Int32}) : Nil
    run.right_click *on_screen(run, spot)
  end

  # Where square *spot* of the floor is drawn.
  def on_screen(run : Playing::Run, spot : {Int32, Int32}) : {Int32, Int32}
    run.map.screen_of(spot[0], spot[1]) || raise "#{spot} is not on the screen"
  end

  # Whether any square of the room is lit as part of a route.
  def route_drawn?(run : Playing::Run) : Bool
    (0...11).any? { |column| (0...5).any? { |row| run.map.highlighted? column, row } }
  end

  # The labels of the menu that is up.
  def labels(run : Playing::Run) : Array(String)
    run.context_menu.items.map &.label
  end

  # Moves the highlight to *label* and chooses it.
  def choose(run : Playing::Run, label : String) : Nil
    12.times do
      break if run.context_menu.current.try(&.label) == label

      run.press "Down"
    end

    expect(run.context_menu.current.try(&.label)).to eq label
    run.press "Enter"
  end

  # The rows for *spot* with the plain character, as `{label, enabled}`.
  def rows(run : Playing::Run, spot : {Int32, Int32},
           scheme : Scheme = Scheme::Traditional) : Array({String, Bool})
    Menu.rows(run.game, spot, scheme).map { |row| {row.label, row.enabled} }
  end

  after_each { Roguelike::Options.current = nil }

  describe "the rows" do
    it "offers Walk here and Examine on bare floor" do
      run = room

      expect(rows run, {3, 2}).to eq [{"Walk here", true}, {"Examine", true}]
    end

    it "leaves Walk here off the character's own square" do
      run = room

      expect(rows run, {2, 2}).to eq [{"Walk here", true}, {"Examine", true}]
      expect(rows run, {1, 1}).to eq [{"Ascend", true}, {"Examine", true}]
    end

    it "offers nothing for a square the character knows nothing of" do
      lines = ["#########", "#<.....##", "#######.#", "#.....#.#", "#########"]
      run = room lines
      floor = run.game.floor

      hidden = {1, 3}
      expect(run.game.knowledge.known? hidden).to be_false
      expect(floor.contains? *hidden).to be_true
      expect(rows run, hidden).to be_empty
    end

    it "offers Open on a shut door" do
      run = room

      expect(rows run, {4, 4}).to eq [{"Open", true}, {"Walk here", true}, {"Examine", true}]
    end

    it "offers Spike on a shut door only to a character who carries a spike" do
      run = room carrying: [Item.new(Kind::Spike)]

      expect(rows run, {4, 4}).to eq [
        {"Open", true}, {"Spike", true}, {"Walk here", true}, {"Examine", true},
      ]
    end

    it "dims Spike on a door known to hold one" do
      run = room carrying: [Item.new(Kind::Spike)]
      run.game.knowledge.remember 4, 4,
        Roguelike::Memory.new(Terrain::ClosedDoor, turn: 1, spiked: true)

      expect(rows run, {4, 4}).to eq [
        {"Open", true}, {"Spike", false}, {"Walk here", true}, {"Examine", true},
      ]
    end

    it "offers Close on an open door" do
      run = room

      expect(rows run, {6, 4}).to eq [{"Close", true}, {"Walk here", true}, {"Examine", true}]
    end

    it "dims Close for a character standing in the doorway" do
      run = room start: {6, 4}

      expect(rows run, {6, 4}).to eq [{"Close", false}, {"Examine", true}]
    end

    it "offers the stairs verb for stairs down and for stairs up" do
      run = room start: {3, 2}

      expect(rows run, {2, 3}).to eq [{"Descend", true}, {"Walk here", true}, {"Examine", true}]
      expect(rows run, {1, 1}).to eq [{"Ascend", true}, {"Walk here", true}, {"Examine", true}]
    end

    it "offers Drink and Fill at a fountain, dimmed while they do nothing" do
      run = room

      expect(rows run, {5, 2}).to eq [
        {"Drink", false}, {"Fill waterskin", false}, {"Walk here", true}, {"Examine", true},
      ]
    end

    it "lights Drink when the character is thirsty and Fill when the skin is short" do
      run = room
      run.game.player.sustenance.parch 4_000
      run.game.player.sustenance.drink

      expect(rows run, {5, 2}).to eq [
        {"Drink", true}, {"Fill waterskin", true}, {"Walk here", true}, {"Examine", true},
      ]
    end

    it "offers Pick up where an item lies" do
      run = room

      expect(rows run, {8, 2}).to eq [{"Pick up", true}, {"Walk here", true}, {"Examine", true}]
    end

    it "offers no verb about a creature" do
      run = room
      run.game.floor.place Roguelike::Monster.new(Roguelike::Species::Goblin, 3, 3, "m1")
      run.play.refresh

      expect(rows run, {3, 3}).to eq [{"Walk here", true}, {"Examine", true}]
    end
  end

  describe "the key hints" do
    it "come from the traditional keys" do
      run = room
      hints = Menu.rows(run.game, {4, 4}, Scheme::Traditional).map &.hint

      expect(hints).to eq ["o", "_", "x"]
    end

    it "come from the modern keys, and are left off where there is none" do
      run = room
      expect(Menu.rows(run.game, {8, 2}, Scheme::Modern).map &.hint).to eq ["g", nil, nil]
      expect(Menu.rows(run.game, {2, 3}, Scheme::Modern).map &.hint).to eq [">", nil, nil]
    end

    # Every hint is a key the scheme binds, so a rebinding cannot leave one
    # behind.
    it "name keys the scheme binds" do
      {Scheme::Traditional, Scheme::Modern}.each do |scheme|
        options = Roguelike::Options.new
        options.control_scheme = scheme
        Roguelike::Options.current = options
        run = room

        bindings = run.play.sections.flat_map(&.bindings.bindings)
        bindings += Roguelike::Ui::Keys.examining(run.play).bindings if scheme.traditional?
        bound = bindings.map(&.to_s)
        keys = scheme.modern? ? Menu::MODERN_KEYS : Menu::TRADITIONAL_KEYS
        keys.each do |verb, key|
          expect(bound).to contain(key), "#{scheme} #{verb}: #{key} is not bound"
        end
      end
    end
  end

  describe "a right click" do
    it "opens the menu for the square" do
      run = room

      right_click run, {4, 4}

      expect(run.context_menu.open?).to be_true
      expect(labels run).to eq ["Open", "Walk here", "Examine"]
    end

    it "shows the hints against the rows" do
      run = room

      right_click run, {4, 4}

      expect(run.context_menu.items.map &.hint).to eq ["o", "_", "x"]
      expect(run.text).to contain "Open"
    end

    it "opens on a click that wobbles a cell, and leaves the view alone" do
      run = room
      before = run.map.camera
      from = on_screen run, {4, 4}

      run.mouse Button::Right, Action::Press, *from
      run.mouse Button::Right, Action::Motion, from[0] + 1, from[1]
      run.mouse Button::Right, Action::Release, from[0] + 1, from[1]

      expect(run.context_menu.open?).to be_true
      expect(labels run).to eq ["Open", "Walk here", "Examine"]
      expect(run.map.camera).to eq before
    end

    it "opens when the terminal does not say which button came up" do
      run = room
      from = on_screen run, {4, 4}

      run.mouse Button::Right, Action::Press, *from
      run.mouse Button::None, Action::Release, *from

      expect(run.context_menu.open?).to be_true
    end

    it "is a drag when the pointer goes further, and opens nothing" do
      run = Playing.open Playing.field(200, 80)
      run.play.mousing = true
      before = run.map.camera
      from = run.map.screen_of(*run.at) || raise "the character is off the map"

      run.right_drag from, {from[0] - 5, from[1] - 1}

      expect(run.context_menu.open?).to be_false
      expect(run.map.camera).not_to eq before
    end

    it "opens nothing when the right button went down off the map" do
      run = room

      run.right_click 0, 0

      expect(run.context_menu.open?).to be_false
    end

    it "opens nothing on a square the character knows nothing of" do
      lines = ["#########", "#<.....##", "#######.#", "#.....#.#", "#########"]
      run = room lines

      right_click run, {1, 3}

      expect(run.context_menu.open?).to be_false
    end

    it "opens nothing while the mouse is off" do
      run = room mouse: false

      right_click run, {4, 4}

      expect(run.context_menu.open?).to be_false
    end

    it "opens nothing while another box is up" do
      run = room
      run.press "i"
      expect(run.menu.showing?).to be_true

      right_click run, {4, 4}

      expect(run.context_menu.open?).to be_false
    end

    it "opens nothing once the run is over" do
      floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
      player = Roguelike::Player.new "room", 1, 1, hit_points: hp(40)
      game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}), player,
        outcome: Roguelike::Outcome::Died
      run = Playing.open game
      run.play.mousing = true
      expect(run.game.over?).to be_true

      right_click run, {4, 4}

      expect(run.context_menu.open?).to be_false
    end

    it "takes a left click outside as a dismissal and no more" do
      run = room
      right_click run, {4, 4}

      run.click *on_screen(run, {1, 1})

      expect(run.context_menu.open?).to be_false
      expect(run.play.walking?).to be_false
      expect(run.turn).to eq 0
    end

    it "keeps the keyboard inside the menu" do
      run = room
      right_click run, {4, 4}

      run.press "l"

      expect(run.at).to eq({1, 1})
      expect(run.context_menu.open?).to be_true
    end

    it "stays on the screen near an edge" do
      run = room
      from = on_screen run, {9, 3}

      run.right_click *from

      frame = run.context_menu.frame
      expect(frame.right).to be <= run.buffer.width
      expect(frame.bottom).to be <= run.buffer.height
    end
  end

  describe "the route" do
    it "is drawn when the menu opens on a square out of reach" do
      run = room

      right_click run, {8, 2}

      expect(route_drawn? run).to be_true
      expect(run.map.highlighted? 8, 2).to be_true
    end

    it "is left off a square beside the character" do
      run = room start: {3, 3}

      right_click run, {4, 4}

      expect(run.context_menu.open?).to be_true
      expect(route_drawn? run).to be_false
    end

    it "is not taken off by the fade timer while the menu is up" do
      run = room clock: true

      right_click run, {8, 2}
      run.run_timers

      expect(route_drawn? run).to be_true
    end

    it "comes off when the menu is closed without a choice" do
      run = room

      right_click run, {8, 2}
      run.press "Escape"

      expect(run.context_menu.open?).to be_false
      expect(route_drawn? run).to be_false
      expect(run.turn).to eq 0
    end

    it "comes off when a click outside closes the menu" do
      run = room

      right_click run, {8, 2}
      run.click *on_screen(run, {1, 3})

      expect(route_drawn? run).to be_false
    end
  end

  describe "choosing a row" do
    it "walks to a far square for Walk here" do
      run = room

      right_click run, {8, 3}
      choose run, "Walk here"

      expect(run.at).to eq({8, 3})
    end

    it "points the readout for Examine, and takes no turn" do
      run = room

      right_click run, {8, 2}
      choose run, "Examine"

      expect(run.examiner.spot).to eq({8, 2})
      expect(run.turn).to eq 0
      expect(run.at).to eq({1, 1})
    end

    it "opens a door beside the character at once" do
      run = room start: {3, 3}

      right_click run, {4, 4}
      choose run, "Open"

      expect(run.game.floor.terrain(4, 4)).to eq Terrain::OpenDoor
      expect(run.at).to eq({3, 3})
    end

    it "walks up to a far door and opens it" do
      run = room

      right_click run, {4, 4}
      choose run, "Open"

      expect(run.at).to eq({3, 3})
      expect(run.game.floor.terrain(4, 4)).to eq Terrain::OpenDoor
    end

    it "walks up to a far door and shuts it without stepping onto it" do
      run = room

      right_click run, {6, 4}
      choose run, "Close"

      expect(run.game.floor.terrain(6, 4)).to eq Terrain::ClosedDoor
      expect(run.game.floor.tile?(6, 4).try &.terrain).to eq Terrain::ClosedDoor
      expect(Roguelike::Notice.touching?(run.at, {6, 4})).to be_true
      expect(run.at).not_to eq({6, 4})
    end

    it "asks before spiking a door beside the character, and spikes it on yes" do
      run = room start: {3, 3}, carrying: [Item.new(Kind::Spike)]

      right_click run, {4, 4}
      choose run, "Spike"

      expect(run.prompt.asking?).to be_true
      expect(run.text).to contain "Spike the door?"
      expect(run.game.floor.spiked? 4, 4).to be_false

      run.press "y"

      expect(run.game.floor.spiked? 4, 4).to be_true
      expect(run.said).to eq "You drive a spike into the door."
    end

    it "leaves the door and the spike alone on no" do
      run = room start: {3, 3}, carrying: [Item.new(Kind::Spike)]

      right_click run, {4, 4}
      choose run, "Spike"
      run.press "n"

      expect(run.game.floor.spiked? 4, 4).to be_false
      expect(run.game.spike_carried).not_to be_nil
      expect(run.turn).to eq 0
    end

    it "walks to a far door, asks, and drives a spike into it on yes" do
      run = room carrying: [Item.new(Kind::Spike)]

      right_click run, {4, 4}
      choose run, "Spike"

      expect(Roguelike::Notice.touching?(run.at, {4, 4})).to be_true
      expect(run.prompt.asking?).to be_true
      expect(run.game.floor.spiked? 4, 4).to be_false

      run.press "y"

      expect(run.game.floor.spiked? 4, 4).to be_true
    end

    it "walks to the stairs and goes down" do
      game = Roguelike::Game.dug Roguelike::Rng.new(3_u64)
      stairs = game.floor.find(Terrain::StairsDown) || raise "no staircase down"
      game.player.move_to stairs
      run = Playing.open game
      run.clear_monsters
      run.play.mousing = true

      # One step off the staircase, onto a square the character knows.
      beside = Roguelike::Direction.values.map(&.from(stairs[0], stairs[1])).find do |spot|
        run.game.knowledge.walkable? spot
      end || raise "no known square beside the staircase"
      run.game.player.move_to beside
      run.play.refresh
      before = run.game.floor.id

      right_click run, stairs
      choose run, "Descend"

      expect(run.game.floor.id).not_to eq before
    end

    it "walks to an item and picks it up" do
      run = room

      right_click run, {8, 2}
      choose run, "Pick up"

      expect(run.at).to eq({8, 2})
      expect(run.game.player.inventory.entries.map(&.[1].kind)).to contain Kind::Dagger
    end

    it "walks to a fountain and drinks" do
      run = room
      run.game.player.sustenance.parch 4_000

      right_click run, {5, 2}
      choose run, "Drink"

      expect(run.at).to eq({5, 2})
      expect(run.game.player.sustenance.quenched?).to be_true
    end

    it "does a verb on its own square at once" do
      run = room start: {8, 2}

      right_click run, {8, 2}
      choose run, "Pick up"

      expect(run.game.player.inventory.entries.map(&.[1].kind)).to contain Kind::Dagger
    end

    it "says a door is shut already open when the character arrives" do
      run = room clock: true

      right_click run, {4, 4}
      choose run, "Open"
      expect(run.play.walking?).to be_true
      run.game.floor.set 4, 4, Terrain::OpenDoor
      run.run_timers

      expect(run.at).to eq({3, 3})
      expect(run.said).to eq "There is nothing to open beside you."
    end

    it "offers only Examine on a wall" do
      run = room

      right_click run, {0, 2}

      expect(labels run).to eq ["Examine"]
    end
  end

  describe "a pending verb" do
    # The walk ran a step at a time, so a spec can stop it part way.
    def started(run : Playing::Run, verb : String, spot : {Int32, Int32}) : Nil
      right_click run, spot
      choose run, verb
      expect(run.play.walking?).to be_true
    end

    it "waits for the walk to arrive" do
      run = room CORRIDOR, clock: true

      started run, "Open", {7, 1}
      expect(run.game.floor.terrain(7, 1)).to eq Terrain::ClosedDoor
      run.run_timers

      expect(run.game.floor.terrain(7, 1)).to eq Terrain::OpenDoor
      expect(run.at).to eq({6, 1})
    end

    it "is dropped by a key pressed on the way" do
      run = room CORRIDOR, clock: true

      started run, "Open", {7, 1}
      run.press "Escape"
      run.run_timers

      expect(run.play.walking?).to be_false
      expect(run.game.floor.terrain(7, 1)).to eq Terrain::ClosedDoor
      expect(run.at).not_to eq({6, 1})
    end

    it "is dropped by a click on the way" do
      run = room CORRIDOR, clock: true

      started run, "Open", {7, 1}
      run.click *on_screen(run, {10, 1})
      run.run_timers

      expect(run.game.floor.terrain(7, 1)).to eq Terrain::ClosedDoor
    end

    it "is dropped by a right click on the way, which opens no menu" do
      run = room CORRIDOR, clock: true

      started run, "Open", {7, 1}
      run.right_click *on_screen(run, {10, 1})
      run.run_timers

      expect(run.context_menu.open?).to be_false
      expect(run.game.floor.terrain(7, 1)).to eq Terrain::ClosedDoor
    end

    it "is dropped when the way is blocked" do
      run = room CORRIDOR, clock: true

      started run, "Open", {7, 1}
      run.game.floor.set 4, 1, Terrain::Granite
      run.run_timers

      expect(run.game.floor.terrain(7, 1)).to eq Terrain::ClosedDoor
      expect(run.at).to eq({3, 1})
    end

    # Every reason a walk stops drops the verb without a word, and arriving
    # is the only one that acts.
    it "is done on arriving and dropped silently for every other halt" do
      Halt.values.each do |halt|
        run = room start: {3, 3}
        errand = Errand.new Verb::Open, {4, 4}, {3, 3}, "room"
        walk = run.game.travelling({3, 3})
        walk.halt = halt
        said = run.log.dup

        run.play.finish_errand walk, errand

        if halt.arrived?
          expect(run.game.floor.terrain(4, 4)).to eq(Terrain::OpenDoor), "#{halt} should act"
        else
          expect(run.game.floor.terrain(4, 4)).to eq(Terrain::ClosedDoor), "#{halt} should drop"
          expect(run.log).to eq(said), "#{halt} should say nothing"
        end
      end
    end

    it "is dropped when the character is not where the walk was sent" do
      run = room
      errand = Errand.new Verb::Open, {4, 4}, {3, 3}, "room"
      walk = run.game.travelling({3, 3})
      walk.halt = Halt::Arrived

      run.play.finish_errand walk, errand

      expect(run.game.floor.terrain(4, 4)).to eq Terrain::ClosedDoor
    end
  end

  describe "the examine cursor" do
    def cursor_on(run : Playing::Run, spot : {Int32, Int32}) : Nil
      run.play.toggle_examine
      run.examiner.point_at spot[0], spot[1]
      run.play.refresh
      run.render
    end

    it "opens the menu on m in the traditional controls" do
      run = room
      run.press "x"
      run.examiner.point_at 4, 4
      run.play.refresh

      run.press "m"

      expect(run.context_menu.open?).to be_true
      expect(labels run).to eq ["Open", "Walk here", "Examine"]
    end

    it "opens the menu on m in the modern controls" do
      options = Roguelike::Options.new
      options.control_scheme = Scheme::Modern
      Roguelike::Options.current = options
      run = room
      cursor_on run, {4, 4}

      run.press "m"

      expect(run.context_menu.open?).to be_true
      expect(labels run).to eq ["Open", "Walk here", "Examine"]
      expect(run.context_menu.items.map &.hint).to eq [nil, nil, nil]
    end

    it "does nothing on m while the cursor is off the map" do
      run = room

      run.press "m"

      expect(run.context_menu.open?).to be_false
      expect(run.turn).to eq 0
    end

    it "carries out a verb from the cursor's menu" do
      run = room
      run.press "x"
      run.examiner.point_at 4, 4
      run.play.refresh

      run.press "m"
      choose run, "Open"

      expect(run.game.floor.terrain(4, 4)).to eq Terrain::OpenDoor
    end

    it "is listed with the keys of both schemes" do
      {Scheme::Traditional, Scheme::Modern}.each do |scheme|
        options = Roguelike::Options.new
        options.control_scheme = scheme
        Roguelike::Options.current = options
        run = room

        bindings = run.play.sections.flat_map(&.bindings.bindings)
        bindings += Roguelike::Ui::Keys.examining(run.play).bindings if scheme.traditional?
        found = bindings.select { |binding| binding.to_s == "m" }

        expect(found.map &.description).to eq ["open the menu for the square under the cursor"]
      end
    end

    it "lists right-click in the mouse section of the help" do
      expect(Roguelike::Ui::Keys::MOUSE_NOTES.map &.[0]).to contain "Right-click"
    end
  end

  describe "the screen" do
    it "draws the menu over the map" do
      run = room

      right_click run, {4, 4}

      drawn = run.text
      expect(drawn).to eq Fixture.expected("screen/context-menu.txt", drawn)
    end
  end
end
