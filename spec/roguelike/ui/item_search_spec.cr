require "../../spec_helper"

Spectator.describe "the item search" do
  alias Play = Roguelike::Ui::Play
  alias ItemSearch = Roguelike::Ui::ItemSearch
  alias ItemSearchPane = Roguelike::Ui::ItemSearchPane
  alias ItemSearchBar = Roguelike::Ui::ItemSearchBar
  alias Keys = Roguelike::Ui::Keys
  alias Command = Roguelike::Ui::Command
  alias Commands = Roguelike::Ui::Commands
  alias Palette = Roguelike::Ui::Palette
  alias Theme = Roguelike::Ui::Theme
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Regard = Roguelike::Regard
  alias Options = Roguelike::Options
  alias Scheme = Roguelike::Options::ControlScheme
  alias Fingerprint = Roguelike::Fingerprint

  # The character stands at (1, 1) in the west room. A wall splits the floor,
  # and the only way east is round the bottom. The pocket at column 10 has no
  # way in.
  #
  #     (3, 3) a spear and a dagger   (1, 7) a spear, 6 steps
  #     (6, 1) a +1 dagger, east of the wall, seen only as a dagger
  #     (10, 3) a mace in the pocket
  ROOM = [
    "############",
    "#....#...#.#",
    "#....#...#.#",
    "#....#...#.#",
    "#....#...#.#",
    "#....#...#.#",
    "#....#...#.#",
    "#........#.#",
    "############",
  ]

  # A run on `ROOM` with the whole floor remembered as of turn 0, and
  # *waits* turns waited after that.
  def room(scheme : Scheme = Scheme::Traditional, waits : Int32 = 0) : Playing::Run
    options = Options.new
    options.control_scheme = scheme
    Options.current = options

    floor = Playing.daylight Roguelike::Floor.parse("room", ROOM)
    floor.drop 3, 3, Item.new(Kind::Spear)
    floor.drop 3, 3, Item.new(Kind::Dagger)
    floor.drop 1, 7, Item.new(Kind::Spear)
    floor.drop 6, 1, Item.new(Kind::Dagger, enchantment: 1)
    floor.drop 10, 3, Item.new(Kind::Mace)
    player = Roguelike::Player.new "room", 1, 1, hit_points: hp(40)
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"room" => floor}), player

    run = Playing.open game, columns: 120, rows: 40
    run.clear_monsters
    run.play.mousing = true

    knowledge = game.knowledge
    ROOM.each_with_index do |line, row|
      line.size.times do |column|
        regard = column > 5 && column < 9 ? Regard::Kind : Regard::Everything
        knowledge.see floor, column, row, 0, regard
      end
    end

    waits.times { run.press "." }
    run.play.refresh
    run.render
    run
  end

  # What the panel lists, one name to a row.
  def listed(run : Playing::Run) : Array(String)
    run.play.search_pane.shown.map &.name
  end

  after_each { Options.current = nil }

  describe "the entries" do
    it "lists every remembered item by walking distance, with no way last" do
      run = room
      found = ItemSearch.entries run.game

      expect(found.map &.spot).to eq [{3, 3}, {3, 3}, {1, 7}, {6, 1}, {10, 3}]
      expect(found.first(3).map &.steps).to eq [2, 2, 6]
      expect(found[3].steps || 0).to be > 6
      expect(found[4].steps).to be_nil
    end

    it "names each item as well as it was made out" do
      run = room
      far = ItemSearch.entries(run.game).find!(&.spot.==({6, 1}))

      expect(far.name).to eq run.game.name(far.item, regard: Regard::Kind)
      expect(far.name).to eq "a dagger"
    end

    it "says how long ago each was seen, ten seconds a turn" do
      run = room waits: 3
      far = ItemSearch.entries(run.game).find!(&.spot.==({6, 1}))

      expect(far.age).to eq run.game.turn
      expect(ItemSearch.ago(far.age)).to eq "#{run.game.turn * 10}s ago"
    end
  end

  describe "the words" do
    it "matches part of a name, whatever the case" do
      expect(ItemSearch.matches?("a Small Cap", "cap")).to be_true
      expect(ItemSearch.matches?("a spear", "CAP")).to be_false
      expect(ItemSearch.matches?("a spear", "  ")).to be_true
    end

    it "puts matching names first and keeps each part in order" do
      names = ["a spear", "a dagger", "a mace", "a +1 dagger"]

      expect(ItemSearch.matches_first(names, "dag")).to eq ["a dagger", "a +1 dagger", "a spear", "a mace"]
      expect(ItemSearch.matches_first(names, "")).to eq names
    end

    it "says how far" do
      expect(ItemSearch.distance(nil)).to eq "no path"
      expect(ItemSearch.distance(0)).to eq "here"
      expect(ItemSearch.distance(1)).to eq "1 step"
      expect(ItemSearch.distance(12)).to eq "12 steps"
    end

    it "says how long ago" do
      expect(ItemSearch.ago(0)).to eq "now"
      expect(ItemSearch.ago(3)).to eq "30s ago"
      expect(ItemSearch.ago(6)).to eq "1m ago"
      expect(ItemSearch.ago(360)).to eq "1h ago"
      expect(ItemSearch.ago(375)).to eq "1h2m ago"
      expect(ItemSearch.ago(3700)).to eq "10h ago"
    end
  end

  describe "the key" do
    it "is the slash, listed in the help" do
      run = room

      found = run.play.sections.flat_map(&.bindings.bindings).select { |binding| binding.to_s == "/" }

      expect(ItemSearchPane::KEY).to eq "/"
      expect(found.map &.description).to eq ["find an item you remember on this floor"]
      expect(run.play.sections.map &.title).to contain "in the item search"
    end

    it "opens the panel in both schemes" do
      {Scheme::Traditional, Scheme::Modern}.each do |scheme|
        run = room scheme

        run.press "/"

        expect(run.play.searching?).to be_true
        expect(run.play.search_pane.showing?).to be_true
        expect(run.play.modal?).to be_true
      end
    end

    it "is in the modern action catalog" do
      run = room Scheme::Modern

      expect(Commands.all.map &.id).to contain Command::ItemSearch

      run.press "r"
      6.times { run.press "d" }
      index = run.menu.entries.index(&.text.starts_with?("Find an item"))
      expect(index).not_to be_nil
      run.play.selection_menu.select_index index || 0
      run.press "f"

      expect(run.play.search_pane.showing?).to be_true
    end
  end

  describe "the panel" do
    it "lists every item nearest first" do
      run = room
      run.press "/"

      expect(listed run).to eq ["a dagger", "a spear", "a spear", "a dagger", "a mace"]
      expect(run.text).to contain "5 items, nearest first"
      expect(run.text).to contain "no path"
    end

    it "narrows the list as letters are typed, and backspace widens it" do
      run = room
      run.press "/"

      run.type "SPE"
      expect(listed run).to eq ["a spear", "a spear"]
      expect(run.text).to contain "2 of 5 match"

      run.press "Backspace", "Backspace", "Backspace"
      expect(listed(run).size).to eq 5
    end

    it "says when nothing matches" do
      run = room
      run.press "/"
      run.type "wand"

      expect(listed run).to be_empty
      expect(run.text).to contain "Nothing you remember matches."
    end

    it "draws the way to the chosen item and walks nowhere" do
      run = room
      run.press "/"
      run.type "spear"
      run.press "Down"

      expect(run.play.search_pane.chosen.try &.spot).to eq({1, 7})
      expect(run.map.highlighted?(1, 7)).to be_true
      expect(run.map.highlighted?(1, 5)).to be_true
      expect(run.at).to eq({1, 1})
      expect(run.turn).to eq 0
    end

    it "chooses a row that is clicked" do
      run = room
      run.press "/"

      list = run.play.search_pane.list.rect
      run.click list.x + 2, list.y + 2

      expect(run.play.search_pane.chosen.try &.spot).to eq({1, 7})
    end

    it "closes with Escape and takes the way off the map" do
      run = room
      run.press "/"
      run.press "Down"
      run.press "Escape"

      expect(run.play.searching?).to be_false
      expect(run.play.modal?).to be_false
      expect(run.map.highlights).to be_empty
      expect(run.map.found).to be_empty
    end

    it "keeps text in the default theme readable" do
      theme = Theme::DEFAULT

      expect(Palette.contrast(theme.plain, theme.selected_row)).to be >= 4.5
      expect(Palette.contrast(theme.header_text, theme.header_ground)).to be >= 4.5
      expect(Palette.contrast(theme.ground, theme.spotlight)).to be >= 4.5
    end
  end

  describe "the map" do
    it "swaps the panel for the map with Tab and lights every match" do
      run = room
      run.press "/"
      run.type "spear"
      run.press "Tab"

      expect(run.play.searching_map?).to be_true
      expect(run.play.search_pane.showing?).to be_false
      expect(run.play.modal?).to be_false
      expect(run.map.found).to eq Set.new([{3, 3}, {1, 7}])
      expect(run.text).to contain ItemSearchBar.said("spear", 2).strip
    end

    it "turns hover mode on while the matches show, and back off after" do
      run = room
      run.press "/"
      run.press "Tab"
      expect(run.play.hovering?).to be_true

      run.press "Tab"
      expect(run.play.hovering?).to be_false
      expect(run.play.search_pane.showing?).to be_true
    end

    it "leaves hover mode on when it was on already" do
      run = room
      run.press Keys::HOVER
      run.press "/"
      run.press "Tab"
      run.press "Escape"
      run.press "Escape"

      expect(run.play.searching?).to be_false
      expect(run.play.hovering?).to be_true
    end

    it "pans with the movement keys and takes no turn" do
      {Scheme::Traditional, Scheme::Modern}.each do |scheme|
        options = Options.new
        options.control_scheme = scheme
        Options.current = options
        run = Playing.open columns: 60, rows: 20
        run.clear_monsters
        at = run.at
        turn = run.turn
        run.press "/"
        run.press "Tab"
        before = run.map.camera

        keys = scheme.modern? ? {"d", "a", "s", "w"} : {"l", "h", "j", "k"}
        keys.each do |key|
          run.press key
          break unless run.map.camera == before
        end

        expect(run.map.camera).not_to eq before
        expect(run.at).to eq at
        expect(run.turn).to eq turn
      end
    end

    it "goes back to the panel with Escape, with a click on the bar, and with the slash" do
      run = room
      run.press "/"
      run.press "Tab"
      run.press "Escape"
      expect(run.play.search_pane.showing?).to be_true

      run.press "Tab"
      bar = run.play.search_bar.label.rect
      run.click bar.x + 2, bar.y
      expect(run.play.search_pane.showing?).to be_true

      run.press "Tab"
      run.press "/"
      expect(run.play.search_pane.showing?).to be_true
    end

    it "goes to the map with a click on the panel's map button" do
      run = room
      run.press "/"

      button = run.play.search_pane.map_button.rect
      run.click button.x + 1, button.y

      expect(run.play.searching_map?).to be_true
    end

    it "works the list out again after a turn passes" do
      run = room
      run.press "/"
      run.press "Tab"
      run.press "."

      expect(run.turn).to eq 1
      run.press "Tab"
      expect(run.text).to contain "10s ago"
    end
  end

  describe "the hover box" do
    # A strip of floor with a spear on the top row, which the bar covers.
    def strip : Playing::Run
      options = Options.new
      options.control_scheme = Scheme::Traditional
      Options.current = options

      floor = Playing.daylight Roguelike::Floor.parse("strip", [
        "....................",
        "....................",
        "....................",
      ])
      floor.drop 3, 0, Item.new(Kind::Spear)
      player = Roguelike::Player.new "strip", 1, 2, hit_points: hp(40)
      game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"strip" => floor}), player

      run = Playing.open game, columns: 60, rows: 20, clock: true
      run.clear_monsters
      run.play.mousing = true
      run
    end

    # Rests the pointer on square *spot* until the dwell is over.
    def rest(run : Playing::Run, spot : {Int32, Int32}) : Nil
      cell = run.map.screen_of(spot[0], spot[1]) || raise "#{spot} is not on the screen"
      run.hover cell[0] + 1, cell[1]
      run.hover *cell
      run.tick Play::HOVER_DWELL
      run.render
    end

    # Whether the hover box is on the screen.
    def up?(run : Playing::Run) : Bool
      box = run.play.hover_box
      box.showing? && !box.hidden?
    end

    it "does not show for a square under the bar" do
      run = strip
      run.press Keys::HOVER
      rest run, {3, 0}
      expect(up? run).to be_true

      run.press "/"
      run.press "Tab"
      cell = run.map.screen_of(3, 0) || raise "not on the screen"
      expect(run.play.search_bar.frame.contains?(*cell)).to be_true

      rest run, {3, 0}
      expect(up? run).to be_false
    end
  end

  describe "piles" do
    it "lists the matching items first in the info panel while the search is open" do
      run = room
      run.hover_map 3, 3
      expect(run.examine.items).to eq ["a spear", "a dagger"]

      run.press "/"
      run.type "dag"
      run.press "Tab"
      run.hover_map 3, 3
      expect(run.examine.items).to eq ["a dagger", "a spear"]

      run.press "Escape", "Escape"
      run.hover_map 4, 3
      run.hover_map 3, 3
      expect(run.examine.items).to eq ["a spear", "a dagger"]
    end
  end

  describe "the game" do
    it "is left as it was" do
      run = room
      before = Fingerprint.of run.game
      said = run.log.size

      run.press "/"
      run.type "dag"
      run.press "Down", "Up", "Tab", "l", "Tab", "Escape"

      expect(Fingerprint.of run.game).to eq before
      expect(run.log.size).to eq said
      expect(run.turn).to eq 0
    end
  end
end
