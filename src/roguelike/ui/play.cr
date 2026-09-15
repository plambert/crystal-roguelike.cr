module Roguelike::Ui
  # A command waiting for a direction.
  enum Pending
    Open
    Close

    # `G`, running that way until something is worth stopping for.
    Run

    # The terrain this command acts on. Every square holding it beside the
    # character is an answer, and the map lights those squares up.
    #
    # `nil` for a command that takes any direction. Running takes all eight,
    # so lighting up the ones it would take would light up the whole ring.
    def terrain : Terrain?
      case self
      in .open?  then Terrain::ClosedDoor
      in .close? then Terrain::OpenDoor
      in .run?   then nil
      end
    end
  end

  # A command waiting for a square to be aimed at.
  enum Aiming
    # `f`, firing the readied ranged weapon.
    Fire

    # `t`, throwing what the person chose.
    Throw

    # `z`, zapping a wand that needs a square to aim at.
    Zap
  end

  # Everything the game shows. Everything the keys do. No device anywhere.
  #
  # `Session` owns a terminal, a frame loop and the mouse. This class owns the
  # rest. The split lets a spec press keys at the code the game runs. A spec
  # does not press keys at a copy of that wiring.
  #
  # This class decides nothing about the game. Every rule belongs to `Game`.
  # This class reads what `Game` did, puts it on the screen, and tells the
  # caller what the terminal needs to hear.
  class Play
    # The run.
    getter game : Game

    # The regions being drawn in.
    getter screen : Screen

    # The window the floor is played in.
    getter map : MapPane

    # The readout of what is on one square.
    getter examine : ExaminePane

    # What is underfoot and what is in sight.
    getter nearby : NearbyPane

    # What points the readout. The pointer or the keyboard.
    getter examiner : Examiner

    # What the mouse pointer is doing.
    getter pointer : Pointer

    # What the character is, stacked down the sidebar.
    getter character : CharacterPane

    # What has just happened, held at a page boundary when a turn says more
    # than the pane shows at once.
    getter pager : Widgets::Pager

    # The list of things to choose from, when there is one.
    getter menu : Widgets::Menu

    # The one-key question, when there is one.
    getter prompt : Widgets::Prompt

    # How the flames waver. `Session` advances it on a timer.
    getter flicker : Flicker

    # The debug console. `nil` unless `--debug-console` was passed.
    #
    # Nothing is built when it is off, so there is no box in the tree and the
    # key that opens one is never bound.
    getter console : ConsolePane? = nil

    # The title screen, and the screen the run ends with.
    getter placard : Placard

    # Whether the person asked for another run when this one ended.
    #
    # `Session` reads this once `#finished?` is true. A run that was quit
    # rather than ended answers false.
    getter? again : Bool = false

    # The application this play is drawn on.
    #
    # The owner sets this once it has built an `App`. A question and a held
    # page each need it to push a focus scope.
    def app=(app : Widgets::App?) : Widgets::App?
      @pager.app = app
      @app = app
    end

    # The application, or a failure saying the owner never set one.
    private def application : Widgets::App
      app = @app
      raise "Play#app has not been set" unless app

      app
    end

    # :ditto:
    getter app : Widgets::App? = nil

    # A command waiting for a direction. `nil` when none is.
    getter pending : Pending? = nil

    # A command waiting for a square to be aimed at. `nil` when none is.
    getter aiming : Aiming? = nil

    # The letter of what is being thrown or zapped. `nil` while firing,
    # which takes its ammunition from the quiver rather than from a letter.
    @chosen : Char? = nil

    # How far what is being aimed goes.
    @reach : Int32 = 0

    # Whether the run should end.
    #
    # The person asked to leave, or the game ended, and the final question has
    # been answered.
    getter? finished : Bool = false

    # Where the camera was before a question moved it. `nil` when no question
    # has moved it.
    @parked : {Int32, Int32}? = nil

    # Whether the screen the run ends with has been put up.
    @ended : Bool = false

    # The size of the screen, as `#fit` was last told it.
    @columns : Int32 = 0
    @rows : Int32 = 0

    def initialize(@game : Game, console : Bool = false)
      @screen = Screen.new
      @map = MapPane.new @game.floor
      @screen.show @map.grid

      @character = CharacterPane.new
      @examine = ExaminePane.new
      @nearby = NearbyPane.new
      @screen.show_sidebar @character.root, @nearby.root, @examine.root
      @examiner = Examiner.new @map, @examine
      @examiner.lore = @game.lore
      @pointer = Pointer.new

      @flicker = Flicker.new @game.world.seed
      @map.flicker = @flicker

      @pager = Widgets::Pager.new
      @screen.show_log @pager

      # Both are floats. `Overlay#open` puts one in the tree the first time it
      # is used.
      @prompt = Widgets::Prompt.new
      @menu = Widgets::Menu.new
      @placard = Placard.new

      if console
        pane = ConsolePane.new @game
        pane.on_command = -> { after_command }
        @console = pane
      end

      refresh
    end

    # The tree. A caller builds an `App` over it.
    def root : Widgets::Widget
      @screen.root
    end

    # The bindings that belong to the game rather than to the application.
    def bindings : Widgets::Bindings
      found = Keys.examining(self)
        .merge(Keys.moving { |direction| step direction })
        .merge(Keys.acting(self))
        .merge(Keys.aiming(self))

      @console ? found.merge(Keys.debugging(self)) : found
    end

    # Puts the title screen up. The owner calls this once, before the run.
    #
    # `p` plays and `q` quits. A person who quits here leaves without a run
    # having started, which `Game::Outcome::Playing` already says.
    def show_title : Nil
      @placard.on_answer = ->(key : Char?) do
        @finished = true unless key == Placards::START_DEFAULT
        nil
      end

      @placard.show application, Placards::NAME,
        Placards.title(@game.world.seed), Placards::START_KEYS,
        default: Placards::START_DEFAULT, footer: Placards::START_FOOTER
    end

    # Puts the debug console up, or takes it down. `` ` `` does this.
    #
    # Nothing happens in a run opened without the console, because the key is
    # not bound in one.
    def toggle_console : Nil
      pane = @console
      return unless pane

      pane.fit_into Rect.new(0, 0, @columns, @rows)
      pane.toggle application
    end

    # Puts the floor back on the screen after a console command.
    #
    # `goto` moves the character, `reveal` fills in the map and `light`
    # changes what can be seen. Each shows on the next frame rather than on
    # the next turn, because a command takes no turn.
    private def after_command : Nil
      @map.follow @game.player.x, @game.player.y
      refresh
    end

    # Asks *question*. Runs *answered* with the key the person pressed.
    #
    # The prompt is a modal overlay. It draws a box in the middle of the
    # screen and dims what is behind it.
    def ask(question : String, keys : String, default : Char? = nil,
            &answered : Char? -> Nil) : Nil
      @prompt.on_answer = ->(key : Char?) do
        park_camera_back
        answered.call key
        nil
      end

      clear_the_character
      @prompt.ask application, question, keys, default
    end

    # Puts *entries* up under *title*. Runs *chosen* with the key pressed.
    def choose(title : String, entries : Enumerable(Widgets::Menu::Entry),
               &chosen : Char? -> Nil) : Nil
      @menu.on_choose = ->(key : Char?) do
        park_camera_back
        chosen.call key
        nil
      end

      clear_the_character
      @menu.show application, title, entries
    end

    # Moves the camera so that a modal box does not cover the character.
    #
    # A box is drawn in the middle of the screen. The map pane fills the top
    # left of it. A character standing in the middle of the pane would be
    # behind the box, and a person answering a question about what is around
    # them has to see what is around them.
    #
    # The camera goes back where it was once the question is answered.
    private def clear_the_character : Nil
      return if @parked

      here = @map.camera
      return unless @map.avoid @game.player.x, @game.player.y, modal_area

      @parked = here
    end

    # Puts the camera back where a question found it.
    private def park_camera_back : Nil
      parked = @parked
      return unless parked

      @parked = nil
      @map.camera = parked
    end

    # How tall a band a modal box is assumed to need.
    #
    # A question is one row of text in a bordered box. Three rows hold it.
    # Seven leaves the character clear of it rather than beside it.
    MODAL_ROWS = 7

    # The part of the map pane a modal box covers, in window coordinates.
    #
    # The box is centred on the screen, not on the map pane. The pane starts
    # at the top left corner of the buffer, so a window coordinate of the pane
    # is a buffer coordinate.
    #
    # The band is three quarters of the screen wide. A question sized to its
    # own text is narrower than that. Reserving more than the box needs costs
    # one camera move and never leaves the character behind the box.
    private def modal_area : Rect
      room = @map.grid.viewport_size
      return Rect.new(0, 0, 0, 0) if room[0] <= 0 || room[1] <= 0 || @columns <= 0

      width = Math.max @columns * 3 // 4, 1
      left = (@columns - width) // 2
      top = (@rows - MODAL_ROWS) // 2

      Rect.new(left, top, width, MODAL_ROWS)
        .intersect Rect.new(0, 0, room[0], room[1])
    end

    # Asks the person whether to leave. Leaves on yes.
    def confirm_quit : Nil
      ask("Really leave the dungeon?", "yn", default: 'n') do |key|
        @finished = true if key == 'y'
      end
    end

    # Puts the examine cursor on the map, or takes it off. `x` does this.
    #
    # A cursor with nowhere else to be starts on the character. The middle of
    # the window is not on the floor at all when the window is larger than the
    # floor.
    def toggle_examine : Nil
      @examiner.toggle @game.player.at
    end

    # Where the terminal's own cursor belongs, in buffer coordinates. `nil`
    # hides it.
    #
    # The examine cursor wins. Both it and the pointer point at one readout,
    # so a pointer over the map is on the examine cursor's own square
    # anyway.
    #
    # The pointer takes it when there is no examine cursor. Reverse video
    # alone is easy to miss on a screen full of glyphs.
    #
    # A modal takes it back. Whatever has the focus inside the box is what the
    # person is answering. A cursor left out on the map says the map is what
    # they are answering.
    def cursor : {Int32, Int32}?
      return if modal?

      @examiner.screen_spot || @pointer.cursor
    end

    # Whether a box is holding the keyboard. A question, a list and a held
    # page each do.
    def modal? : Bool
      @prompt.asking? || @menu.showing? || @pager.holding? ||
        @placard.showing? || (@console.try &.showing? || false)
    end

    # Puts the camera on the character.
    #
    # The owner calls this once the tree has been laid out. It cannot run
    # before. An unmeasured window is nothing by nothing. Centring on a square
    # in a window of no size leaves the camera on the square. It does not
    # clamp against the edge of the floor.
    def look_at_player : Nil
      @map.center_on @game.player.x, @game.player.y
    end

    # One step of a movement key.
    #
    # A command waiting for a direction takes the key first. The examine
    # cursor takes it next. A person reading the floor is not walking about
    # it. The character takes it otherwise.
    #
    # A step that does not happen takes no turn.
    def step(direction : Direction) : Nil
      waiting = @pending
      if waiting
        @pending = nil
        act waiting, direction
        return
      end

      if @examiner.cursoring?
        @examiner.move direction
        show_aim if @aiming
        return
      end

      # A blocked step says why. The pane has to be redrawn either way.
      done = @game.step direction
      @map.follow @game.player.x, @game.player.y unless done.blocked?
      refresh
    end

    # Waits for a direction to run in. `G` does this.
    #
    # Every direction is an answer, so there is nothing to find and nothing
    # to light up. The next movement key runs rather than steps.
    def start_running : Nil
      @pending = Pending::Run
      say "Run which way? Press a direction, or Escape."
    end

    # Opens a door.
    #
    # One shut door beside the character needs no question. More than one
    # does. None is said and nothing else happens.
    def open_door : Nil
      start Pending::Open, Terrain::ClosedDoor, "open"
    end

    # Closes a door. It works the same way as `#open_door`.
    def close_door : Nil
      start Pending::Close, Terrain::OpenDoor, "close"
    end

    # Goes down the staircase the character stands on.
    def descend : Nil
      unless @game.descend
        say "There is no staircase down here."
        return
      end

      refresh
    end

    # Climbs out of the dungeon, after asking.
    def ascend : Nil
      unless @game.standing_on.stairs_up?
        say "There is no staircase up here."
        return
      end

      ask("Leave the dungeon by this staircase?", "yn", default: 'n') do |key|
        next unless key == 'y'

        @game.ascend
        refresh
      end
    end

    # Takes back whatever is waiting for a key. `Escape` does this.
    #
    # A pending command goes first. The prompt goes next. The examine cursor
    # goes last. One press takes back one thing.
    def cancel : Nil
      if @pending
        @pending = nil
        refresh
        return
      end

      if @aiming
        stop_aiming
        say "Never mind."
        return
      end

      if @prompt.asking?
        @prompt.cancel
        return
      end

      if @menu.showing?
        @menu.cancel
        return
      end

      @examiner.stop
    end

    # ---------------------------------------------------------------- items

    # Picks up what is on the square the character stands on.
    #
    # Nothing there says so. One thing is taken without a question. More than
    # one is a menu, because a person standing on a pile has to say which.
    def pick_up : Nil
      pile = @game.here

      case pile.size
      when 0
        say "There is nothing here to pick up."
      when 1
        @game.pick_up pile.first
        refresh
      else
        choose_from pile
      end
    end

    # Asks which of *pile* to pick up.
    private def choose_from(pile : Array(Item)) : Nil
      entries = pile.each_with_index.map do |item, index|
        Widgets::Menu::Entry.new Widgets::Menu.letter(index), @game.name(item)
      end

      choose("Pick up what?", entries) do |key|
        next unless key

        index = Widgets::Menu.index key
        item = pile[index]?
        next unless item

        @game.pick_up item
        refresh
      end
    end

    # Asks which carried item to drop.
    def drop : Nil
      inventory = @game.player.inventory
      if inventory.empty?
        say "You are carrying nothing."
        return
      end

      choose("Drop what?", carried) do |key|
        next unless key

        @game.drop key
        refresh
      end
    end

    # Shows what the character carries.
    def show_inventory : Nil
      if @game.player.inventory.empty?
        say "You are carrying nothing."
        return
      end

      choose("Inventory", carried) { |_key| refresh }
    end

    # Every carried entry, as a menu row.
    private def carried : Array(Widgets::Menu::Entry)
      rows @game.player.inventory.entries
    end

    # *entries* as menu rows, each marked with the slot holding it.
    #
    # A person reading the list has to see which sword is in their hand.
    private def rows(entries : Array({Char, Item})) : Array(Widgets::Menu::Entry)
      entries.map do |letter, item|
        slot = @game.slot_of letter
        label = @game.name item
        label = "#{label} (#{slot.note})" if slot

        Widgets::Menu::Entry.new letter, label
      end
    end

    # ------------------------------------------------------------- shooting

    # Fires the readied ranged weapon. `f` does this.
    #
    # A second press looses the shot, so a person can press `f`, pick a
    # monster with `Tab` and press `f` again without reaching for `Enter`.
    def fire : Nil
      if @aiming
        loose
        return
      end

      complaint = @game.cannot_fire
      if complaint
        say complaint
        return
      end

      start_aiming Aiming::Fire, nil, @game.firing_reach
    end

    # Throws a carried item. `t` does this.
    #
    # Anything can be thrown. A rock and a dart go furthest, and anything
    # not made for throwing goes a square or two.
    def throw : Nil
      if @aiming
        loose
        return
      end

      offer "Throw what?", "You are carrying nothing to throw.",
        ->(_item : Item) { true } do |letter|
        item = @game.player.inventory[letter]
        start_aiming Aiming::Throw, letter, item.kind.reach if item
      end
    end

    # Aims at the next monster in sight. `Tab` does this.
    #
    # Nearest first, and round again from the end. The nearest monster is
    # the one about to reach the character, so it is offered first.
    #
    # Answers whether it moved the cursor. `Tab` means "the next widget"
    # everywhere else, and the binding hands the key back when this says no.
    def next_target : Bool
      return false unless @aiming

      found = targets
      return false if found.empty?

      here = @examiner.spot
      index = here ? found.index(here) : nil
      wanted = found[index ? (index + 1) % found.size : 0]

      @examiner.point_at wanted[0], wanted[1]
      @map.follow wanted[0], wanted[1]
      refresh
      true
    end

    # Looses what is being aimed. `Enter` does this.
    def loose : Nil
      command = @aiming
      target = @examiner.spot
      letter = @chosen
      return unless command && target

      stop_aiming

      case command
      in .fire?  then @game.fire target
      in .throw? then @game.throw letter, target if letter
      in .zap?   then @game.zap letter, target if letter
      end

      refresh
    end

    # Starts *command* aiming at the nearest monster in sight.
    #
    # The cursor falls back to the character's own square. A person shooting
    # down an empty corridor walks the cursor out along it.
    private def start_aiming(command : Aiming, letter : Char?, reach : Int32) : Nil
      @aiming = command
      @chosen = letter
      @reach = reach

      @examiner.start @game.player.at
      wanted = targets.first?
      @examiner.point_at wanted[0], wanted[1] if wanted

      say "Aim with the movement keys. Tab picks a monster, Enter looses, Escape stops."
    end

    # Takes the targeting cursor off and forgets what was being aimed.
    private def stop_aiming : Nil
      @aiming = nil
      @chosen = nil
      @reach = 0

      @examiner.stop
      @examine.aiming = nil
      @map.clear_flight
    end

    # Every monster in sight, nearest first.
    #
    # Ties go to the lower row and then to the lower column, so `Tab` walks
    # the same ring in the same order every time.
    private def targets : Array({Int32, Int32})
      here = @game.player.at

      @game.monsters_in_sight.map(&.at).sort_by! do |spot|
        across = spot[0] - here[0]
        down = spot[1] - here[1]

        {across * across + down * down, spot[1], spot[0]}
      end
    end

    # Draws the line the shot would take and says where it would stop.
    private def show_aim : Nil
      @map.clear_flight
      @examine.aiming = nil

      return unless @aiming

      target = @examiner.spot
      return unless target

      shot = @game.flight target, @reach
      shot.path.each { |spot| @map.aim spot[0], spot[1], Palette::FLIGHT }

      stop = shot.at
      @map.aim stop[0], stop[1], Palette::IMPACT unless stop == @game.player.at

      @examine.aiming = aimed shot
    end

    # What the readout says about *shot*.
    private def aimed(shot : Flight) : String
      return "The shot is clear." if shot.clear?

      case shot.landing
      in .struck?
        in_the_way = @game.floor.monster shot.at[0], shot.at[1]
        "The #{in_the_way.try(&.label) || "creature"} is in the way."
      in .blocked? then "Something is in the way."
      in .spent?   then "That is out of range."
      in .reached? then "The shot is clear."
      end
    end

    # ---------------------------------------------------------- consumables

    # Asks which potion to drink, then drinks it. `q` does this.
    def quaff : Nil
      offer "Drink what?", "You have nothing to drink.",
        ->(item : Item) { item.kind.item_class.potion? } do |letter|
        @game.quaff letter
      end
    end

    # Asks which scroll to read, then reads it. `r` does this.
    #
    # A scroll of identify needs a second question: which carried item it
    # names. `Game#effect_of` says so before the turn is spent.
    def read : Nil
      complaint = @game.cannot_read
      if complaint
        say complaint
        return
      end

      offer "Read what?", "You have nothing to read.",
        ->(item : Item) { item.kind.item_class.scroll? } do |letter|
        if @game.effect_of(letter).chosen?
          identify_with letter
        else
          @game.read letter
        end
      end
    end

    # Asks which carried item the scroll under *letter* names.
    #
    # The scroll itself is not offered. It is about to be used up, and a
    # person who spent it naming it would have learned nothing.
    #
    # Nothing else to name reads the scroll anyway. It is used up either way,
    # and saying so is clearer than refusing to read it.
    private def identify_with(letter : Char) : Nil
      found = @game.player.inventory.entries.select do |held, item|
        held != letter && !@game.lore.known?(item.kind)
      end

      if found.empty?
        @game.read letter
        return
      end

      choose("Identify what?", rows(found)) do |key|
        @game.read letter, key
        refresh
      end
    end

    # Asks which wand to zap, then zaps it. `z` does this.
    #
    # A wand that needs a square to aim at puts the targeting cursor up
    # instead. A second press of `z` looses it, the way `f` does.
    def zap : Nil
      if @aiming
        loose
        return
      end

      offer "Zap what?", "You have nothing to zap.",
        ->(item : Item) { item.kind.item_class.wand? } do |letter|
        item = @game.player.inventory[letter]
        next unless item

        effect = @game.effect_of letter
        if effect.aimed?
          start_aiming Aiming::Zap, letter, item.kind.reach
        else
          @game.zap letter
        end
      end
    end

    # ------------------------------------------------------------ equipment

    # Asks which carried item to ready, then readies it.
    #
    # Only what can be held is offered. `Game#wield` picks the slot from what
    # the item is, so one key readies a sword, a bow and a quiver of arrows.
    def wield : Nil
      offer "Wield what?", "You have nothing to wield.",
        ->(item : Item) { Slot.for(item).try(&.weapon?) || false } do |letter|
        @game.wield letter
      end
    end

    # Asks which carried piece of armour to put on, then puts it on.
    def wear : Nil
      offer "Wear what?", "You have nothing to wear.",
        ->(item : Item) { Slot.for(item).try(&.armour?) || false } do |letter|
        @game.wear letter
      end
    end

    # Asks what to take off, then takes it off.
    #
    # One thing readied needs no question. More than one does. Nothing is
    # said and nothing else happens.
    def take_off : Nil
      held = @game.readied

      case held.size
      when 0
        say "You are not wearing or holding anything."
      when 1
        @game.take_off held.first[0]
        refresh
      else
        choose_slot held
      end
    end

    # Asks which of *held* to take off.
    private def choose_slot(held : Array({Slot, Item})) : Nil
      entries = held.each_with_index.map do |(slot, item), index|
        Widgets::Menu::Entry.new Widgets::Menu.letter(index),
          "#{slot.label}: #{@game.name item}"
      end

      choose("Take off what?", entries) do |key|
        next unless key

        found = held[Widgets::Menu.index key]?
        next unless found

        @game.take_off found[0]
        refresh
      end
    end

    # Lights or puts out a torch, a candle or a wall sconce.
    #
    # One thing to apply needs no question. More than one does. Nothing is
    # said and nothing else happens.
    def apply : Nil
      found = @game.appliable

      case found.size
      when 0
        say "You have nothing to light and there is no sconce beside you."
      when 1
        @game.apply found.first
        refresh
      else
        choose_target found
      end
    end

    # Asks which of *found* to apply.
    private def choose_target(found : Array(Apply)) : Nil
      entries = found.each_with_index.map do |target, index|
        Widgets::Menu::Entry.new Widgets::Menu.letter(index), applying(target)
      end

      choose("Apply what?", entries) do |key|
        next unless key

        target = found[Widgets::Menu.index key]?
        next unless target

        @game.apply target
        refresh
      end
    end

    # What one row of the apply menu says.
    private def applying(target : Apply) : String
      letter = target.letter

      if letter
        item = @game.player.inventory[letter]
        return "#{letter} - #{item ? @game.name(item) : "nothing"}"
      end

      fitting = @game.floor.fixture target.x, target.y
      return "nothing" unless fitting

      where = target.x == @game.player.x && target.y == @game.player.y ? "here" : "beside you"

      "the #{fitting.label} #{where}"
    end

    # Asks which carried item answering *wanted* to use. Runs *chosen* with
    # the letter. Says *nothing* when the character carries none.
    private def offer(title : String, nothing : String, wanted : Item -> Bool,
                      &chosen : Char -> Nil) : Nil
      found = @game.player.inventory.select { |item| wanted.call item }

      if found.empty?
        say nothing
        return
      end

      choose(title, rows(found)) do |key|
        next unless key

        chosen.call key
        refresh
      end
    end

    # Puts the camera on the character.

    # Puts what the game holds back on the screen.
    #
    # Everything shown comes from `Game`. This method is the one place the two
    # are put in step. It runs after anything that changes the game.
    def refresh : Nil
      @map.clear_marks
      @map.clear_highlights
      seen = @game.look
      @map.sight = seen
      @map.knowledge = @game.knowledge

      # The character block writes itself, then gives up whatever rows the
      # window has no room for. What is left over is what the two readouts
      # under it get, so the order here decides the sidebar.
      @character.show @game
      @character.fit Play.character_rows @rows
      @nearby.budget = Play.nearby_budget @rows, @character.height
      @nearby.show @game, seen

      # The pane reads the floor for what is lying about and the knowledge for
      # what was lying about. A mark is something standing on a square, which
      # is the character now and the monsters later.
      @map.mark @game.player.x, @game.player.y, Palette::PLAYER
      offer_directions
      show_aim
      @pager.show @game.log.lines
      show_ending
    end

    # Puts the screen the run ends with up, once.
    #
    # Everything that changes the game ends with `#refresh`, so this is the
    # one place that has to notice. Dying, climbing down and climbing out all
    # arrive here, and the heading is what tells them apart.
    #
    # An owner that has not built an `App` yet has nowhere to put a modal.
    # `#initialize` refreshes before there is one, and a run cannot be over at
    # that point anyway.
    private def show_ending : Nil
      return unless @game.over?
      return if @ended || @app.nil?

      @ended = true
      stop_aiming

      @placard.on_answer = ->(key : Char?) do
        @again = key == 'y'
        @finished = true
        nil
      end

      @placard.show application, Placards.heading(@game.outcome),
        Placards.ending(@game), Placards::AGAIN_KEYS,
        default: Placards::AGAIN_DEFAULT, footer: Placards::AGAIN_FOOTER
    end

    # Lights up every square the command waiting for a direction would take.
    #
    # Four doors around one square are four answers, and a person has to see
    # which is which before they pick one.
    private def offer_directions : Nil
      waiting = @pending
      return unless waiting

      wanted = waiting.terrain
      return unless wanted

      @game.doors(wanted).each do |direction|
        spot = direction.from @game.player.x, @game.player.y
        @map.highlight spot[0], spot[1]
      end
    end

    # Records that the pointer is at *x*, *y* of the buffer. *click* says the
    # person pressed a button rather than moved the pointer.
    #
    # Answers the sequence the terminal needs. Answers `nil` when it needs
    # none.
    #
    # A pointer moving over the map points the readout, until `x` puts the
    # cursor on the map. A person who pressed `x` is reading with the
    # keyboard. A pointer brushing past would take the cursor off what they
    # are reading. So while the cursor is on the map, only a click moves it.
    def pointed(x : Int32, y : Int32, click : Bool = false) : String?
      # A modal box owns the screen. Nothing else answers a pointer while one
      # is up.
      return pointer_away if modal?

      if @examiner.cursoring? && !click
        # The shape still follows the pointer. The pointer is over the map,
        # whatever the readout is pointing at.
        return @map.cell_at_screen(x, y) ? @pointer.over(x, y) : pointer_away
      end

      return pointer_away unless @examiner.point_at_screen x, y

      @pointer.over x, y
    end

    # Records that the pointer is off the map. Also used when the mouse is
    # turned off and when the run ends.
    def pointer_away : String?
      @pointer.away
    end

    # Answers the layout to a screen of *columns* by *rows*.
    #
    # A menu that is up is sized again. The owner calls this before it tells
    # the application about the new size, so the new rectangle is passed
    # rather than read back off the tree.
    def fit(columns : Int32, rows : Int32) : Nil
      @columns = columns
      @rows = rows
      @screen.fit columns, rows
      @pager.resize Screen.log_width(columns), Screen::LOG_ROWS

      @placard.fit_into Rect.new(0, 0, columns, rows)

      app = @app
      @menu.refit Rect.new(0, 0, columns, rows), app.tree.policy if app

      refresh
    end

    # Starts *command*. Finds the one door of *terrain* beside the character,
    # or asks which one.
    private def start(command : Pending, terrain : Terrain, verb : String) : Nil
      found = @game.doors terrain

      case found.size
      when 0
        say "There is nothing to #{verb} beside you."
      when 1
        act command, found.first
      else
        @pending = command
        say "Which way? Press a direction, or Escape."
      end
    end

    # How many rows the sidebar's two lists get on a screen of *rows*.
    #
    # Whatever the sidebar has left, less the headings and rules of the two
    # sections and the most `ExaminePane` writes. A shorter screen gives them
    # less, and `NearbyPane` elides what does not fit rather than pushing the
    # readout off the bottom.
    def self.nearby_budget(rows : Int32, character : Int32 = 0) : Int32
      Math.max Screen.map_rows(rows) - character - SIDEBAR_CHROME - EXAMINE_ROWS, 2
    end

    # How many rows `CharacterPane` may take of a screen of *rows*.
    #
    # What is left over once the two readouts under it have what they need.
    # The character block is the one that can give rows up: it knows what it
    # would drop first, and a person who wants all of it can make the window
    # taller.
    def self.character_rows(rows : Int32) : Int32
      Math.max Screen.map_rows(rows) - LEAST_READOUTS, CharacterPane::LEAST
    end

    # Rows the three sidebar headings and the rules under them take.
    SIDEBAR_CHROME = 6

    # The most rows `ExaminePane` writes at once.
    EXAMINE_ROWS = 6

    # The fewest rows the three readouts are left with.
    #
    # A heading, a rule and one row each for Here, Seen and Look, and the two
    # blank rows between the three panes. The character block takes
    # everything above that and gives rows back when there are not enough.
    LEAST_READOUTS = SIDEBAR_CHROME + 3 + 3

    # Whether the log is holding a page that has not been read.
    def holding? : Bool
      @pager.holding?
    end

    # Runs *command* on the door *direction*.
    #
    # `Game` says what happened either way. A door that will not shut says
    # why, and this method must not write over that with a guess.
    private def act(command : Pending, direction : Direction) : Nil
      case command
      in .open?  then @game.open direction
      in .close? then @game.close direction
      in .run?   then dash direction
      end

      refresh
    end

    # Runs *direction*. `G` and then a direction key does this.
    #
    # The whole run happens inside one key press, so the screen is drawn once
    # at the end rather than once per step. `Play` holds no terminal and
    # cannot send a frame partway through a handler.
    private def dash(direction : Direction) : Nil
      went = @game.run direction
      @map.follow @game.player.x, @game.player.y if went.moved?
    end

    # Records whether the terminal is reporting the mouse.
    #
    # Nothing writes it on the screen now. The status row it was on is gone,
    # and `M` says what it did in the log.
    def mousing=(wanted : Bool) : Nil
      @mousing = wanted
    end

    # :ditto:
    getter? mousing : Bool = false

    # Moves the flames on one tick.
    #
    # This changes nothing the game decides. No square comes into sight or
    # goes out of it, nothing is remembered, and no turn is taken. The next
    # frame draws the same map a shade differently.
    def waver : Nil
      @flicker.tick += 1
    end

    # Adds *line* to the log.
    private def say(line : String) : Nil
      @game.say line
      refresh
    end
  end
end
