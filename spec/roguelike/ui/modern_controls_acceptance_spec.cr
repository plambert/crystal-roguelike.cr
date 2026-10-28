require "../../spec_helper"
require "../../support/recording"

Spectator.describe "approved modern controls" do
  alias Game = Roguelike::Game
  alias Item = Roguelike::Item
  alias ItemKind = Roguelike::ItemKind
  alias Menu = TermBuf::Widgets::Menu
  alias Options = Roguelike::Options
  alias Panel = Roguelike::Ui::FocusRing::Panel
  alias Player = Roguelike::Player
  alias Scheme = Options::ControlScheme
  alias Slot = Roguelike::Slot
  alias Widget = TermBuf::Widgets::Widget

  ROOM = [
    "#####",
    "#...#",
    "#...#",
    "#...#",
    "#####",
  ]

  EXPLORE_ROOM = [
    "#################",
    "#....############",
    "#<...'.........##",
    "#....#########.##",
    "##############.##",
    "##############.##",
    "#################",
  ]

  MODERN_MOVES = {
    "q" => {-1, -1},
    "w" => {0, -1},
    "e" => {1, -1},
    "a" => {-1, 0},
    "d" => {1, 0},
    "z" => {-1, 1},
    "s" => {0, 1},
    "x" => {1, 1},
  }

  after_each { Options.current = nil }

  def playing(scheme : Scheme, items : Array(Item) = [] of Item,
              map : Array(String) = ROOM,
              start : {Int32, Int32} = {2, 2},
              clock : Bool = false, hit_points : Int32 = 20) : Playing::Run
    options = Options.new
    options.control_scheme = scheme
    Options.current = options

    floor = Playing.daylight Roguelike::Floor.parse("controls-acceptance", map)
    player = Player.new(floor.id, start[0], start[1], hit_points: hit_points)
    items.each { |item| player.inventory.add item }
    game = Game.new Roguelike::World.new(Playing::SEED, {floor.id => floor}), player
    game.enroll

    Playing.open game, 80, 24, clock: clock
  end

  def visible_menu(widget : Widget) : Menu?
    if menu = widget.as?(Menu)
      return menu if menu.showing?
    end

    widget.children.reverse_each do |child|
      if found = visible_menu(child)
        return found
      end
    end

    nil
  end

  def active_menu(run : Playing::Run) : Menu?
    visible_menu run.session.app.focus.top.root
  end

  def require_menu(run : Playing::Run) : Menu
    active_menu(run) || raise "The active interaction has no visible menu"
  end

  def menu_labels(menu : Menu) : Array(String)
    if menu.pages.empty?
      menu.entries.map(&.text)
    else
      menu.pages.flat_map { |page| page[1].map(&.text) }
    end
  end

  def has_label?(labels : Array(String), fragment : String) : Bool
    wanted = fragment.downcase
    labels.any?(&.downcase.includes?(wanted))
  end

  def select_menu_label(run : Playing::Run, fragment : String) : Nil
    menu = require_menu run
    page_count = Math.max menu.pages.size, 1
    selected_index : Int32? = nil

    page_count.times do
      menu = require_menu run
      selected_index = menu.entries.index do |entry|
        entry.text.downcase.includes? fragment.downcase
      end
      break if selected_index

      run.press "d"
    end

    target = selected_index || raise "No visible menu row matches #{fragment.inspect}"
    selected = require_menu(run).selected_index || 0

    while selected < target
      run.press "s"
      selected += 1
    end
    while selected > target
      run.press "w"
      selected -= 1
    end

    expect(require_menu(run).selected_index).to eq target
  end

  def inventory_state(game : Game) : Array(String)
    game.player.inventory.items.map(&.[1].to_json)
  end

  def items_for_legacy_letters : Array(Item)
    [
      Item.new(ItemKind::Dagger),
      Item.new(ItemKind::HealingPotion),
      Item.new(ItemKind::IdentifyScroll),
      Item.new(ItemKind::LightWand),
      Item.new(ItemKind::Torch),
    ]
  end

  def use_modern_item_action(run : Playing::Run, item : String, action : String) : Nil
    run.press "i"
    select_menu_label run, item
    run.press "f"
    select_menu_label run, action
    run.press "f"
  end

  def recorded_item_actions(scheme : Scheme, modern : Bool) : {Array(String), String, Int32, {Int32, Int32, Int32, Int32}}
    path = Recording.directory / "modern-controls-#{Random.rand UInt32}.jsonl"

    game = Recording.recording(path.to_s) do
      run = playing scheme,
        [Item.new(ItemKind::Dagger), Item.new(ItemKind::HealingPotion)],
        hit_points: 2

      if modern
        use_modern_item_action run, "potion", "drink"
        use_modern_item_action run, "dagger", "wield"
      else
        potion_key = run.game.player.inventory.items.find! do |entry|
          entry[1].kind == ItemKind::HealingPotion
        end[0]
        dagger_key = run.game.player.inventory.items.find! do |entry|
          entry[1].kind == ItemKind::Dagger
        end[0]

        run.press "q", potion_key.to_s
        run.press "w", dagger_key.to_s
      end

      run.game
    end

    reading = Recording.read path, fingerprints: false
    actions = reading.records.compact_map do |record|
      record.as?(Roguelike::Replay::Act).try(&.action.to_json)
    end

    {actions, game.fingerprint, game.turn,
     {game.blows, game.uses, game.wanders, game.handled}}
  end

  def recorded_viewer_run : Playing::Run
    path = Recording.directory / "modern-controls-viewer-#{Random.rand UInt32}.jsonl"
    Recording.recording(path.to_s) do
      run = playing Scheme::Traditional,
        [Item.new(ItemKind::Dagger), Item.new(ItemKind::HealingPotion)]
      run.press "."
      run.game
    end

    reading = Recording.read path, fingerprints: false
    viewer = Roguelike::Replay::Viewer.new reading
    options = Options.new
    options.control_scheme = Scheme::Modern
    Options.current = options
    Playing.open viewer: viewer
  end

  describe "map movement" do
    it "moves in all eight spatial directions without running old item commands" do
      MODERN_MOVES.each do |key, delta|
        run = playing Scheme::Modern, items_for_legacy_letters, hit_points: 1
        before = run.at
        held = inventory_state run.game
        equipment = run.game.player.equipment.to_json

        run.press key

        expect(run.at).to eq({before[0] + delta[0], before[1] + delta[1]})
        expect(run.turn).to eq 1
        expect(inventory_state run.game).to eq held
        expect(run.game.player.equipment.to_json).to eq equipment
      end
    end

    it "walks in all eight directions from uppercase shifted keys and consumes the interrupt" do
      MODERN_MOVES.each do |key, delta|
        run = playing Scheme::Modern, clock: true
        before = run.at
        shifted = TermBuf::Key.character(key.upcase[0])
        run.session.send TermBuf::Events::Key.new(shifted, Bytes.empty)
        run.render

        expect(run.at).to eq({before[0] + delta[0], before[1] + delta[1]})
        expect(run.play.walking?).to be_true
        expect(run.turn).to eq 1

        here = run.at
        run.press "."

        expect(run.at).to eq here
        expect(run.turn).to eq 1
        expect(run.play.walking?).to be_false
      end
    end

    it "distinguishes Ctrl+X exploration from shifted X walking" do
      exploring = playing Scheme::Modern, map: EXPLORE_ROOM, start: {1, 2}
      exploring.press "Ctrl+X"

      expect(exploring.game.knowledge.seen? 14, 5).to be_true
      expect(exploring.turn).to be > 0

      walking = playing Scheme::Modern, clock: true
      before = walking.at

      walking.session.send TermBuf::Events::Key.new(
        TermBuf::Key.character('X'), Bytes.empty)
      walking.render

      expect(walking.at).to eq({before[0] + 1, before[1] + 1})
      expect(walking.play.walking?).to be_true
      expect(walking.game.knowledge.seen? 14, 5).to be_false
    end
  end

  describe "inventory and action lists" do
    it "selects an item with w/s, opens its actions with f, and backs out without a turn" do
      run = playing Scheme::Modern,
        [Item.new(ItemKind::Dagger), Item.new(ItemKind::HealingPotion)]
      run.press "i"

      select_menu_label run, "potion"
      selected = require_menu(run).selected_index
      run.press "f"

      actions = menu_labels(require_menu(run))
      expect(has_label?(actions, "drink")).to be_true
      expect(has_label?(actions, "drop")).to be_true
      expect(run.turn).to eq 0

      run.press "Escape"
      expect(require_menu(run).selected_index).to eq selected
      run.press "Escape"

      expect(active_menu(run)).to be_nil
      expect(run.turn).to eq 0
      expect(run.game.player.inventory.items.size).to eq 2
    end

    it "uses a and d for inventory tabs while retaining empty categories" do
      run = playing Scheme::Modern,
        [Item.new(ItemKind::Dagger), Item.new(ItemKind::HealingPotion)]
      run.press "i"
      expect(require_menu(run).page_name.try(&.downcase)).to eq "all"

      run.press "d", "d"
      expect(require_menu(run).page_name.try(&.downcase)).to eq "armor"
      expect(has_label?(menu_labels(require_menu(run)), "nothing")).to be_true

      run.press "a", "a"
      expect(require_menu(run).page_name.try(&.downcase)).to eq "all"
      expect(run.turn).to eq 0
      run.press "Escape"
    end

    it "shows Read in the complete catalog with an empty target explanation, but not in available actions" do
      run = playing Scheme::Modern
      run.press "r"

      expect(has_label?(menu_labels(require_menu(run)), "read")).to be_true
      select_menu_label run, "read"
      run.press "f"

      expect(run.text.downcase).to contain "read"
      expect(run.text.downcase).to contain "no scrolls to read"
      expect(run.text.downcase).to contain "escape"
      expect(run.turn).to eq 0

      run.press "Escape"
      expect(has_label?(menu_labels(require_menu(run)), "read")).to be_true
      run.press "Escape"

      available = playing Scheme::Modern
      available.press "f"
      labels = menu_labels(require_menu(available))
      expect(has_label?(labels, "wait")).to be_true
      expect(has_label?(labels, "read")).to be_false
      expect(available.turn).to eq 0
    end
  end

  describe "panels and time" do
    it "cycles panels with Tab and waits with period without opening inventory" do
      run = playing Scheme::Modern
      start = run.at

      run.press "."
      run.press "Tab"
      expect(run.play.ring.current).to eq Panel::Info
      expect(active_menu(run)).to be_nil
      run.press "."

      run.press "Tab"
      expect(run.play.ring.current).to eq Panel::Log
      expect(active_menu(run)).to be_nil
      run.press "."

      run.press "Shift+Tab", "Shift+Tab"
      expect(run.play.ring.current).to eq Panel::Map
      expect(active_menu(run)).to be_nil
      expect(run.turn).to eq 3
      expect(run.at).to eq start
    end

    it "uses w/s to navigate the info panel and scroll the log, not move the character" do
      run = playing Scheme::Modern
      12.times do |number|
        run.game.log.add "Acceptance message #{number}."
      end
      run.play.refresh
      run.pager.to_newest
      run.render
      start = run.at

      run.press "Tab"
      section = run.play.info_panel.at
      run.press "s"
      expect(run.play.info_panel.at).not_to eq section
      run.press "w"
      expect(run.play.info_panel.at).to eq section
      expect(run.at).to eq start

      run.press "Shift+Tab"
      expect(run.play.ring.current).to eq Panel::Log
      run.press "w"
      expect(run.pager.back).to be > 0
      run.press "s"
      expect(run.at).to eq start
      expect(run.turn).to eq 0
    end

    it "pages messages with Space without waiting on the map or log" do
      run = playing Scheme::Modern
      12.times { |number| run.game.log.add "Acceptance message #{number}." }
      run.play.refresh
      run.pager.to_newest
      run.render

      run.press "Shift+Tab", "PageUp"
      older = run.pager.back
      expect(older).to be > 0
      run.press "Tab", "Space"
      expect(run.pager.back).to be < older
      expect(run.turn).to eq 0

      run.press "Shift+Tab", "PageUp"
      before_page = run.pager.back
      expect(before_page).to be > 0
      run.press "Space"
      expect(run.pager.back).to be < before_page
      expect(run.turn).to eq 0
    end
  end

  describe "text and replay viewing" do
    it "keeps modern control letters as text in an entry field" do
      run = playing Scheme::Modern
      start = run.at
      answers = [] of String?
      run.play.entry.on_answer = ->(answer : String?) { answers << answer; nil }
      run.play.entry.ask run.session.app, "Enter the reserved control letters."

      run.type "wsrf"
      expect(run.play.entry.text).to eq "wsrf"
      run.press "Enter"

      expect(answers).to eq ["wsrf"]
      expect(run.at).to eq start
      expect(run.turn).to eq 0
    end

    it "keeps replay catalogs and inventory browsing read-only" do
      run = recorded_viewer_run
      viewer = run.viewer || raise "The replay viewer was not opened"
      before = run.game.fingerprint

      run.press "r"
      complete = menu_labels(require_menu(run))
      {"wait", "drop", "drink", "read", "explore", "equip", "zap"}.each do |action|
        expect(has_label?(complete, action)).to be_false
      end

      run.press "Escape", "f"
      available = menu_labels(require_menu(run))
      expect(has_label?(available, "wait")).to be_false
      expect(has_label?(available, "drop")).to be_false
      run.press "Escape", "i"
      select_menu_label run, "dagger"
      run.press "f"

      item_actions = active_menu(run).try { |menu| menu_labels(menu) } || [] of String
      {"drop", "drink", "wield", "read", "zap"}.each do |action|
        expect(has_label?(item_actions, action)).to be_false
      end

      run.press "Escape", "Escape"
      {"q", "w", "a", "d", "z", "x"}.each { |key| run.press key }

      expect(run.game.turn).to eq 0
      expect(run.game.fingerprint).to eq before
      viewer.close
    end
  end

  describe "traditional compatibility and shared model actions" do
    it "keeps traditional movement and wielding on their existing keys" do
      run = playing Scheme::Traditional, [Item.new(ItemKind::Dagger)]
      before = run.at

      run.press "h"
      expect(run.at).to eq({before[0] - 1, before[1]})

      dagger_key = run.game.player.inventory.items.first[0]
      run.press "w", dagger_key.to_s
      expect(run.game.slot_of(dagger_key)).to eq Slot::Melee
    end

    it "produces the same potion and equipment actions under both schemes" do
      modern = recorded_item_actions Scheme::Modern, true
      traditional = recorded_item_actions Scheme::Traditional, false

      expect(modern[0]).to eq traditional[0]
      expect(modern[1]).to eq traditional[1]
      expect(modern[2]).to eq traditional[2]
      expect(modern[3]).to eq traditional[3]
      expect(modern[2]).to eq 2
    end
  end
end
