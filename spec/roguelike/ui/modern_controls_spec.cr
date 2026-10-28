require "../../spec_helper"
require "../../support/recording"

Spectator.describe "the modern controls" do
  alias Options = Roguelike::Options
  alias Scheme = Roguelike::Options::ControlScheme
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Viewer = Roguelike::Replay::Viewer
  alias Monster = Roguelike::Monster

  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  def modern(game : Roguelike::Game? = nil, columns : Int32 = 80,
             rows : Int32 = 24, kitty_keyboard : Bool = false) : Playing::Run
    options = Options.new
    options.control_scheme = Scheme::Modern
    Options.current = options
    Playing.open(game, columns: columns, rows: rows,
      kitty_keyboard: kitty_keyboard)
  end

  def carrying(items : Array(Item)) : Roguelike::Game
    floor = Playing.daylight Roguelike::Floor.parse("modern", HALL)
    player = Roguelike::Player.new floor.id, 1, 1
    items.each { |item| player.inventory.add item }
    Roguelike::Game.new Roguelike::World.new(Playing::SEED, {floor.id => floor}), player
  end

  def modernize(run : Playing::Run) : Nil
    options = Options.new
    options.control_scheme = Scheme::Modern
    Options.current = options
    run.play.controls_changed
    Roguelike::Ui::Keys.install(run.session.app, Roguelike::Ui::Help.new,
      run.play) { run.play.confirm_quit }
  end

  def archer : Playing::Run
    Options.current = Options.new
    run = Playing.open carrying([Item.new(Kind::Bow), Item.new(Kind::Arrow, count: 12)])
    run.press "w", "a", "w", "b"
    run.game.floor.place Monster.new(Roguelike::Species::Goblin, 6, 1, "modern-test", hit_points: 200)
    run.play.refresh
    run.render
    run
  end

  after_each { Options.current = nil }

  describe "map and panel input" do
    it "moves in all eight directions without using shifted movement" do
      moves = Roguelike::Ui::Controls.moves(Scheme::Modern)
      pairs = [
        {"q", "x"}, {"w", "s"}, {"e", "z"}, {"a", "d"},
      ]

      pairs.each do |(first, second)|
        run = modern Playing.field(80, 40)
        start = run.at
        run.press first, second

        expect(run.at).to eq start
        expect(run.turn).to eq 2
      end

      expect(moves.size).to eq 8
    end

    it "walks in each direction from uppercase and modifier-aware events" do
      directions = ["Q", "W", "E", "A", "D", "Z", "S", "X"]
      directions.each do |key|
        run = modern Playing.field(32, 24)
        run.clear_monsters
        start = run.at
        run.press key
        expect(run.turn).to be > 1
        expect(run.at).not_to eq start
      end

      modified = modern Playing.field(32, 24)
      modified.clear_monsters
      start = modified.at
      modified.press "Shift+q"
      expect(modified.turn).to be > 1
      expect(modified.at[0]).to be < start[0]
      expect(modified.at[1]).to be < start[1]
    end

    it "distinguishes Ctrl+X exploration from Shift+X walking" do
      walked = modern Playing.field(32, 24)
      walked.clear_monsters
      start = walked.at
      walked.press "X"
      expect(walked.turn).to be > 1
      expect(walked.at).not_to eq start

      explored = modern
      explored.clear_monsters
      explored.press "Ctrl+X"
      expect(explored.turn).to be >= 0
      expect(explored.play.walking?).to be_false
    end

    it "waits on dot, pages messages with Space, and gates Shift+Space" do
      plain = modern
      plain.press "Space"
      expect(plain.turn).to eq 0
      plain.press "Shift+Space"
      expect(plain.turn).to eq 0
      plain.press "."
      expect(plain.turn).to eq 1

      kitty = modern kitty_keyboard: true
      kitty.press "Space"
      expect(kitty.turn).to eq 0
      kitty.press "Shift+Space"
      expect(kitty.turn).to eq 1
      kitty.press "."
      expect(kitty.turn).to eq 2
    end

    it "uses Tab for panels while inventory remains letterless" do
      run = modern carrying([Item.new(Kind::Dagger), Item.new(Kind::HealingPotion)])
      run.press "i"
      expect(run.menu.showing?).to be_true
      expect(run.menu.navigation.display_shortcuts).to be_false
      expect(run.menu.entries.map(&.key).uniq!).to eq ['\0']
      run.press "d"
      expect(run.menu.page_name).to eq "weapons"
      run.press "Escape"

      run.press "Tab"
      expect(run.play.ring.current.info?).to be_true
      run.press "Shift+Tab"
      expect(run.play.ring.current.map?).to be_true
    end
  end

  describe "action menus and item flows" do
    it "opens the complete catalog from F2 in both schemes" do
      traditional = Playing.open
      traditional.press "F2"
      expect(traditional.menu.title).to eq "Action catalog"

      modern_run = modern
      modern_run.press "F2"
      expect(modern_run.menu.title).to eq "Action catalog"
    end

    it "shows unavailable commands through r but filters them from f" do
      run = modern
      run.press "r"
      run.press "d", "d", "d"
      read_index = run.menu.entries.index(&.text.starts_with?("Read a scroll"))
      expect(read_index).not_to be_nil
      run.play.selection_menu.select_index read_index || 0
      run.press "f"

      expect(run.menu.title).to contain "Read a scroll"
      expect(run.menu.entries.first.enabled).to be_false
      expect(run.menu.selected_index).to be_nil
      expect(run.text).to contain "You have nothing to read"
      run.press "Escape"
      expect(run.menu.page_name).to eq "Items"
      expect(run.menu.selected_index).to eq read_index

      run.press "Escape", "Escape", "f"
      expect(run.menu.title).to eq "Available actions"
      expect(run.menu.pages.flat_map(&.[1]).map(&.text).join(" ")).not_to contain "Read a scroll"
    end

    it "uses the same equip action in traditional and modern inventory flows" do
      Options.current = Options.new
      traditional = Playing.open carrying([Item.new(Kind::Dagger)])
      traditional.press "w", "a"

      modern_run = modern carrying([Item.new(Kind::Dagger)])
      modern_run.press "i", "f", "f"

      expect(traditional.game.slot_of('a')).to eq Roguelike::Slot::Melee
      expect(modern_run.game.slot_of('a')).to eq Roguelike::Slot::Melee
      expect(modern_run.turn).to eq traditional.turn
      expect(modern_run.play.character.letterless?).to be_true
    end

    it "keeps drink and drop outcomes the same across profiles" do
      Options.current = Options.new
      traditional_drink = Playing.open carrying([Item.new(Kind::HealingPotion)])
      traditional_drink.press "q", "a"
      modern_drink = modern carrying([Item.new(Kind::HealingPotion)])
      modern_drink.press "i", "f", "s", "f"
      expect(modern_drink.game.fingerprint).to eq traditional_drink.game.fingerprint

      Options.current = Options.new
      Options.current = Options.new
      traditional_drop = Playing.open carrying([Item.new(Kind::Dagger)])
      traditional_drop.press "d", "a"
      modern_drop = modern carrying([Item.new(Kind::Dagger)])
      modern_drop.press "i", "f", "s", "f"
      expect(modern_drop.game.fingerprint).to eq traditional_drop.game.fingerprint
    end

    it "keeps read follow-ups and thrown-item targeting letterless" do
      Options.current = Options.new
      traditional_read = Playing.open carrying([Item.new(Kind::IdentifyScroll), Item.new(Kind::HealingPotion)])
      traditional_read.press "r", "a", "b"
      modern_read = modern carrying([Item.new(Kind::IdentifyScroll), Item.new(Kind::HealingPotion)])
      modern_read.press "i", "f", "s", "f", "f"
      expect(modern_read.game.fingerprint).to eq traditional_read.game.fingerprint

      Options.current = Options.new
      traditional_throw = Playing.open carrying([Item.new(Kind::Dagger)])
      traditional_throw.press "t", "a", "l", "Enter"
      modern_throw = modern carrying([Item.new(Kind::Dagger)])
      modern_throw.press "i", "f", "s", "s", "f", "d", "f"
      expect(modern_throw.game.fingerprint).to eq traditional_throw.game.fingerprint
    end

    it "returns to the read action when canceling an identify follow-up" do
      run = modern carrying([Item.new(Kind::IdentifyScroll), Item.new(Kind::HealingPotion)])
      turn = run.turn

      run.press "i", "f", "s", "f"
      expect(run.menu.title).to eq "Identify what?"
      run.press "Escape"

      expect(run.menu.title).to contain "scroll of identify"
      expect(run.menu.entries[run.menu.selected_index || 0].text).to start_with "Read a scroll"
      expect(run.game.player.inventory.has? 'a').to be_true
      expect(run.turn).to eq turn

      run.press "Escape"
      expect(run.menu.title).to eq "Inventory"
    end

    it "restores every read target when canceling a catalog read follow-up" do
      run = modern carrying([
        Item.new(Kind::IdentifyScroll), Item.new(Kind::RepairScroll),
        Item.new(Kind::HealingPotion),
      ])
      run.press "r", "d", "d", "d"
      read_index = run.menu.entries.index(&.text.starts_with?("Read a scroll"))
      expect(read_index).not_to be_nil
      run.play.selection_menu.select_index read_index || 0
      run.press "f"
      target_count = run.menu.entries.size
      expect(target_count).to eq 2

      run.press "f", "Escape"

      expect(run.menu.title).to contain "choose a target"
      expect(run.menu.entries.size).to eq target_count
      expect(run.menu.selected_index).to eq 0
    end

    it "does not spend a repair scroll when its follow-up is canceled" do
      damaged = Item.new(Kind::Mace, condition: Roguelike::Condition::Damaged)
      run = modern carrying([Item.new(Kind::RepairScroll), damaged])
      turn = run.turn

      run.press "i", "f", "s", "f"
      expect(run.menu.title).to eq "Repair what?"
      run.press "Escape"

      expect(run.menu.title).to contain "scroll of repair"
      expect(run.menu.entries[run.menu.selected_index || 0].text).to start_with "Read a scroll"
      expect(run.game.player.inventory.has? 'a').to be_true
      expect(run.game.player.inventory['b'].try(&.condition)).to eq Roguelike::Condition::Damaged
      expect(run.turn).to eq turn
    end

    it "fires through the available-action menu with the same result as traditional aiming" do
      traditional = archer
      traditional.press "f", "Enter"

      modern_run = archer
      modernize modern_run
      modern_run.press "f"
      expect(modern_run.play.aiming).to be_nil
      5.times { modern_run.press "d" }
      modern_run.press "f"
      expect(modern_run.play.aiming).to eq Roguelike::Ui::Aiming::Fire
      modern_run.press "f"

      expect(modern_run.game.turn).to eq traditional.game.turn
      expect(modern_run.game.fingerprint).to eq traditional.game.fingerprint
    end

    it "fires at the nearest monster on F, as the traditional scheme does" do
      traditional = archer
      traditional.press "F"

      modern_run = archer
      modernize modern_run
      before = modern_run.turn
      modern_run.press "F"

      expect(modern_run.turn).to be > before
      expect(modern_run.play.aiming).to be_nil
      expect(modern_run.game.turn).to eq traditional.game.turn
      expect(modern_run.game.fingerprint).to eq traditional.game.fingerprint
    end

    it "refuses F with nothing readied and spends no turn" do
      run = modern carrying([Item.new(Kind::Arrow, count: 5)])
      run.press "F"

      expect(run.said).to contain "nothing readied"
      expect(run.turn).to eq 0
      expect(run.play.aiming).to be_nil
    end

    it "does not offer item actions while browsing a replay" do
      reading = Roguelike::Replay::Reading.read Recording.golden
      viewer = Viewer.new reading
      options = Options.new
      options.control_scheme = Scheme::Modern
      Options.current = options
      run = Playing.open viewer: viewer
      inventory_size = run.game.player.inventory.size
      run.press "i", "f"

      expect(run.game.player.inventory.size).to eq inventory_size
      expect(run.play.menu.showing?).to be_true
      expect(run.play.menu.title).to eq "Inventory"
      expect(run.play.menu.entries.map(&.text).join(" ")).not_to contain "Drop"
      expect(run.play.menu.entries.map(&.text).join(" ")).not_to contain "Equip"
    end

    it "replaces owned bindings when the Options scheme changes" do
      run = modern carrying([Item.new(Kind::Dagger)])
      calls = 0
      caller = TermBuf::Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Ctrl+K"), "caller binding",
          ->(_context : TermBuf::Widgets::Context) { calls += 1; nil }
      end
      run.session.app.keymap = run.session.app.keymap.merge caller
      run.press "r", "d", "d", "d", "d", "d", "d", "d", "f"
      run.press "End", "Up", "Up", "Up", "Up"
      expect(run.play.options_screen.focused_row.try(&.key)).to eq "control_scheme"
      run.press "Left"
      expect(Options.current.try(&.control_scheme)).to eq Scheme::Traditional
      expect(run.session.app.keymap.bindings.any? do |binding|
        binding.description == "open the complete action catalog" ||
          binding.description == "open actions or confirm the target"
      end).to be_false
      expect(run.session.app.keymap.bindings.any? do |binding|
        binding.description == "leave the game"
      end).to be_true
      expect(run.session.app.keymap.bindings.any? do |binding|
        binding.description == "caller binding"
      end).to be_true
      run.press "Escape"
      expect(run.menu.title).to eq "Action catalog"
      run.press "Escape", "Ctrl+K"
      expect(calls).to eq 1
      run.press "w"
      expect(run.menu.title).to eq "Wield or wear what?"
      expect(run.turn).to eq 0
    end

    it "opens the comparison from Options and preserves the form" do
      run = modern
      run.press "r", "d", "d", "d", "d", "d", "d", "d", "f"
      run.press "Down", "Down", "Down", "Down", "Down", "Down", "Enter"
      form = run.play.options_screen.form
      expect(run.play.options_screen.control_setup.picker.showing?).to be_true
      run.press "a", "f"
      expect(Options.current.try(&.control_scheme)).to eq Scheme::Traditional
      expect(run.play.options_screen.form.same? form).to be_true
      expect(run.play.options_screen.focused_row.try(&.key)).to eq "compare_controls"
    end
  end

  describe "startup chooser" do
    def state : Path
      root = Path[File.tempname "modern-controls", nil]
      Dir.mkdir_p root
      root
    end

    it "fits 40x16, saves an accepted choice, and supports Escape cancellation" do
      { {40, 16}, {80, 24} }.each do |(columns, rows)|
        root = state
        run = Playing.open(columns: columns, rows: rows, startup_controls: true,
          control_options: Options.new, options_root: root)
        expect(run.text).to contain "Traditional"
        expect(run.text).to contain "Modern"
        run.press "f"
        expect(Options.read(root).control_scheme).to eq Scheme::Modern
        expect(run.play.finished?).to be_false
        FileUtils.rm_rf root.to_s
      end

      root = state
      run = Playing.open(columns: 40, rows: 16, startup_controls: true,
        control_options: Options.new, options_root: root)
      run.press "Escape"
      expect(run.play.finished?).to be_true
      expect(File.exists?(Options.path root)).to be_false
      FileUtils.rm_rf root.to_s
    end

    it "keeps the runtime choice and reports a failed write" do
      root = state
      Dir.mkdir Options.path(root).to_s
      run = Playing.open(startup_controls: true,
        control_options: Options.new, options_root: root)

      run.press "f"

      expect(Options.current.try(&.control_scheme)).to eq Scheme::Modern
      expect(run.log.join(" ")).to contain "could not be saved"
      expect(run.play.finished?).to be_false
      FileUtils.rm_rf root.to_s
    end
  end
end
