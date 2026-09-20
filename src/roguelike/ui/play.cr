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

    # `r`, a scroll already read that wants a square.
    Read
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

    # The question a line is typed into, when there is one. The character's
    # name is asked for through this.
    getter entry : Widgets::Entry

    # Where the run is saved, or `nil` for a run that is not saved.
    #
    # `Session` gives a run the store under the person's home. A spec gives
    # one a store on a temporary directory, or none at all, so that nothing
    # a spec does writes to a person's saved characters.
    property store : Save::Store? = nil

    # How the flames waver. `Session` advances it on a timer.
    getter flicker : Flicker

    # The debug console. `nil` unless `--debug-console` was passed.
    #
    # Nothing is built when it is off, so there is no box in the tree and the
    # key that opens one is never bound.
    getter console : ConsolePane? = nil

    # The title screen, and the screen the run ends with.
    getter placard : Placard

    # What hangs beside a sidebar row the pointer is over.
    getter tooltip : Tooltip

    # What the pointer is over in the sidebar, as the rows last reported it.
    #
    # A row records itself here when the pointer crosses it, and `#pointed`
    # reads it once the event has been through the whole tree. That is the
    # one place that decides whether the box goes up or comes down.
    @detailed : {Widgets::Widget, Array(String)}? = nil

    # What the rows of the menu now up are about, by the key that picks each.
    #
    # A row with no item behind it is not in here. The apply menu has one row
    # per wall sconce, and a sconce is a fixture rather than something
    # carried.
    @listed : Hash(Char, Item) = {} of Char => Item

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

    # Whether the run has been written out since it ended.
    #
    # A run that ends on a staircase is saved twice: once by the command that
    # ended it and once by the screen that reports it. Retiring twice would
    # leave two endings on disk for one death.
    @retired : Bool = false

    # How many times the name question has been asked this run.
    #
    # It names the stream the offered name is rolled from, so every question
    # offers a different one.
    @suggested : Int32 = 0

    # The name the question is offering. `Enter` on an empty line takes it.
    @offered : String = ""

    # Which saved character each title row carries on, by the key that picks
    # it. The row that starts a new character is in no key here.
    @carrying : Hash(Char, String) = {} of Char => String

    # The scroll that has been read and is waiting for a square.
    @aimed : Item? = nil

    # The name the last run ended under, offered once to the next one.
    #
    # A character who died or won has had their file moved out of the way, so
    # the name is free again. Somebody who answered "play again" usually
    # wants the same name, and typing it out a second time is work the game
    # can do for them.
    property previous_name : String? = nil

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
      @entry = Widgets::Entry.new
      @menu = Widgets::Menu.new
      @placard = Placard.new
      @tooltip = Tooltip.new
      watch_the_sidebar

      if console
        pane = ConsolePane.new @game
        pane.on_command = -> { after_command }
        @console = pane
      end

      refresh
    end

    # Puts the pointer hooks on the rows of the character pane.
    #
    # A row says what it is about when the pointer crosses it. `#pointed`
    # decides what to do with that once the event has been through the tree.
    # The pack heading opens and shuts the pack when it is pressed.
    private def watch_the_sidebar : Nil
      Slot.listed.each do |slot|
        row = @character.slot_row slot
        row.on_point = -> { detail row, Detail.about(@game, slot); nil }
      end

      @character.pack.each_with_index do |row, index|
        row.on_point = -> { detail row, carried_detail(index); nil }
      end

      @character.pack_heading.on_press = -> { open_pack; nil }
      @character.pack_heading.on_point = -> { detail nil, nil; nil }
    end

    # What the pack row at *index* is about, or `nil` for an empty row.
    private def carried_detail(index : Int32) : Array(String)?
      found = @game.player.inventory.entries[index]?
      return unless found

      Detail.about @game, found[1]
    end

    # Records what the pointer is over. `nil` for a row about nothing.
    private def detail(row : Widgets::Widget?, lines : Array(String)?) : Nil
      @detailed = row && lines ? {row, lines} : nil
    end

    # Opens the pack, or shuts it, and lays the sidebar out again.
    def open_pack : Nil
      @character.toggle_pack
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
    # It is a menu. The first row starts a new character, which is what
    # `Enter` takes, and every row after it is a saved character to carry on,
    # most recently played first. `Escape` quits, and a person who quits here
    # leaves without a run having started, which `Outcome::Playing` already
    # says.
    #
    # The saves are rows rather than a list to read, so a name is picked
    # rather than typed. A person carrying a character on no longer has to
    # spell it the way they spelled it the first time.
    def show_title : Nil
      held = saved
      @carrying = {} of Char => String

      @menu.on_choose = ->(key : Char?) do
        chose_at_title key
        nil
      end

      # A narrow margin. The title screen is the whole screen, the title in
      # its border carries the seed, and a long character name should show
      # rather than scroll.
      @menu.column_margin = TITLE_MARGIN
      @menu.on_highlight = nil
      @menu.show application, Placards.title_bar(@game.world.seed),
        title_rows(held)
    end

    # The rows the title menu offers.
    #
    # A new character first, every saved character after it, and leaving
    # last. The two ends keep their keys whatever is in the store, so the
    # saves take what is left.
    private def title_rows(held : Array(Save::Held)) : Array(Widgets::Menu::Entry)
      rows = [Widgets::Menu::Entry.new Placards::NEW_KEY, Placards::NEW_ROW]
      keys = Widgets::Menu::LETTERS.reject do |key|
        key == Placards::NEW_KEY || key == Placards::QUIT_KEY
      end

      held.each_with_index do |found, index|
        key = keys[index]?
        break unless key

        @carrying[key] = found.name
        rows << Widgets::Menu::Entry.new key, Placards.saved_row(found)
      end

      rows << Widgets::Menu::Entry.new Placards::QUIT_KEY, Placards::QUIT_ROW
      rows
    end

    # What the row picked at the title screen does.
    private def chose_at_title(key : Char?) : Nil
      return @finished = true if key.nil? || key == Placards::QUIT_KEY

      name = @carrying[key]?
      return ask_the_name unless name

      answered_the_name name
    end

    # Starts as *name*, with no title screen and no question.
    #
    # `--character` passes a name from the command line. A name already in the
    # store carries that character on; any other name starts the run that was
    # dug, under that name.
    def play_as(name : String) : Nil
      answered_the_name name
    end

    # Every character in the store, or nothing when there is no store.
    private def saved : Array(Save::Held)
      @store.try(&.characters) || [] of Save::Held
    end

    # Asks who is playing.
    #
    # A name already in the store loads that character. Any other name starts
    # the run that was dug, under that name. `Escape` puts the title screen
    # back: a person who is not sure what to type has not decided to play.
    #
    # *complaint* replaces the question when the last answer was refused, so
    # the box says why rather than going blank and asking the same thing.
    # Asks who is playing, with a name offered for somebody who has not
    # thought of one.
    #
    # The offer sits where the placeholder goes, dimmed, rather than on the
    # line. A name on the line would have to be deleted before a person could
    # type their own, and most people have their own. `Enter` on an empty
    # line takes the offer.
    #
    # A question that was refused comes back with an empty line and a fresh
    # offer, rather than with what was refused still on it. Somebody told
    # their name is taken is about to type a different one.
    private def ask_the_name(complaint : String? = nil) : Nil
      @offered = suggestion

      @entry.on_answer = ->(answer : String?) do
        answered_the_name answer
        nil
      end

      @entry.ask application, complaint || Placards::NAME_QUESTION,
        placeholder: @offered
    end

    # A name to offer somebody who has not thought of one.
    #
    # It is rolled from the run's own seed, so `--seed N` twice offers the
    # same name twice. A name already saved under is rolled past rather than
    # offered, because the question would then refuse its own offer.
    #
    # The counter moves on with every question, so a person who does not like
    # what is offered can back out to the title screen and come in again.
    private def suggestion : String
      carried = @previous_name
      @previous_name = nil
      return carried if carried && !(@store.try(&.holds? carried) || false)

      found = Rng.new(@game.world.seed).derive "name", @suggested
      @suggested += 1

      Names.free found, @store
    end

    # What to do with what was typed at the name question.
    #
    # Two names can make one file name, so a name that would be written over
    # somebody else's save is refused rather than taken. Nobody types a new
    # character's name expecting to lose an old character.
    private def answered_the_name(typed : String?) : Nil
      return show_title if typed.nil?

      name = typed.strip
      name = @offered if name.empty?
      return ask_the_name Placards::NAME_UNUSABLE if Save.slug(name).empty?

      whose = @store.try &.taken_by(name)
      return ask_the_name Placards.taken(whose) if whose

      found = @store.try &.read(name)
      return start_as name unless found

      resume found
      say "Welcome back, #{found.player.name}. Turn #{found.turn}."
    end

    # Names the dug character and starts the run.
    private def start_as(name : String) : Nil
      @game.player.name = name
      say "#{name} enters the dungeon."
      keep
    end

    # Plays *game* instead of the one this was built on.
    #
    # Everything drawn is built from the game on each refresh, so the panes
    # need no rebuilding. What does need resetting is the state that belongs
    # to no game: a command waiting for a direction, a shot being aimed, and
    # whether the screen a run ends with has been put up.
    def resume(game : Game) : Nil
      @game = game
      @map.floor = game.floor
      @examiner.lore = game.lore
      @console.try &.game = game

      @pending = nil
      @aiming = nil
      @chosen = nil
      @reach = 0
      @parked = nil
      @detailed = nil
      @listed.clear
      @ended = false
      @retired = false

      refresh
      look_at_player
    end

    # Writes the run to the store, if there is one.
    #
    # A character with no name is not written. A run holds none until the
    # title screen has been answered, and a spec builds one that never will
    # be.
    #
    # A run that is over is written and then retired, so the last state of it
    # is kept and the name it used is free. A person whose character died
    # starts again under the same name.
    #
    # A store that will not take the file says so in the log and the run goes
    # on. Losing the turn a person is playing because a disk is full is worse
    # than losing the save.
    def keep : Nil
      store = @store
      return unless store
      return if @game.player.name.empty?

      return if @retired

      store.write @game
      return unless @game.over?

      store.retire @game.player.name, @game.outcome
      @retired = true
    rescue error : File::Error | IO::Error | ArgumentError
      @game.say "The game could not be saved: #{error.message}"
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
    #
    # *about* is what each row is about, by the key that picks it. A row named
    # in it hangs a box of detail beside the list while the highlight is on
    # it. A menu with nothing in *about* hangs no box at all.
    def choose(title : String, entries : Enumerable(Widgets::Menu::Entry),
               about : Hash(Char, Item)? = nil,
               &chosen : Char? -> Nil) : Nil
      @listed = about || {} of Char => Item
      @menu.column_margin = @listed.empty? ? Widgets::Menu::COLUMN_MARGIN : MENU_MARGIN
      @menu.on_highlight = ->(entry : Widgets::Menu::Entry?) do
        listed_detail entry
        nil
      end

      @menu.on_choose = ->(key : Char?) do
        @listed.clear
        @tooltip.hide
        park_camera_back
        chosen.call key
        nil
      end

      clear_the_character
      @menu.show application, title, entries
    end

    # How many columns a menu with a box beside it leaves clear on each side.
    #
    # The box hangs off the list, so the list cannot have the whole screen.
    # This is the narrowest box worth reading, and the gap between it and the
    # menu's border. A wide screen never reaches this: the menu is as wide as
    # its rows and no wider.
    MENU_MARGIN = Tooltip::LEAST_WIDTH + 4

    # How many columns the title menu leaves clear on each side.
    TITLE_MARGIN = 2

    # Hangs the box off the row the menu highlight is on, or takes it down.
    #
    # The box goes to the left of the list, clear of the border and the
    # padding, and level with the row. A row scrolled out of the window takes
    # the box with it, because the offset is from the top of the window rather
    # than from the top of the list.
    private def listed_detail(entry : Widgets::Menu::Entry?) : Nil
      app = @app
      item = entry ? @listed[entry.key]? : nil
      unless app && item
        @tooltip.hide
        return
      end

      list = @menu.list
      @tooltip.show app, list, Detail.about(@game, item),
        dx: -1 - @menu.gutter, dy: list.selected - list.scroll_y
    end

    # The items *entries* are about, by the letter each is carried under.
    private def about(entries : Array({Char, Item})) : Hash(Char, Item)
      found = {} of Char => Item
      entries.each { |letter, item| found[letter] = item }
      found
    end

    # The same for a list whose rows are numbered rather than lettered.
    private def about(items : Array(Item)) : Hash(Char, Item)
      found = {} of Char => Item
      items.each_with_index { |item, index| found[Widgets::Menu.letter index] = item }
      found
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
        next unless key == 'y'

        keep
        @finished = true
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
      @prompt.asking? || @entry.asking? || @menu.showing? || @pager.holding? ||
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

    # Passes the turn. `.` does this.
    #
    # A command waiting for a direction takes the key back instead, the way a
    # movement key does. Nothing else waits: a person reading the floor with
    # the examine cursor is not spending turns.
    def wait : Nil
      if @pending
        @pending = nil
        refresh
        return
      end

      @game.wait
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

      keep
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
        keep
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

      if @entry.asking?
        @entry.cancel
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

      choose("Pick up what?", entries, about(pile)) do |key|
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

      choose("Drop what?", carried, carried_about) do |key|
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

      choose("Inventory", carried, carried_about) { |_key| refresh }
    end

    # Every carried entry, as a menu row.
    private def carried : Array(Widgets::Menu::Entry)
      rows @game.player.inventory.entries
    end

    # The same rows, by the letter each is carried under.
    private def carried_about : Hash(Char, Item)
      about @game.player.inventory.entries
    end

    # *entries* as menu rows, each marked with the slot holding it.
    #
    # A person reading the list has to see which sword is in their hand.
    private def rows(entries : Array({Char, Item})) : Array(Widgets::Menu::Entry)
      entries.map do |letter, _item|
        slot = @game.slot_of letter
        label = @game.name_under letter
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
      scroll = @aimed
      return unless command && target

      @aimed = nil
      stop_aiming

      case command
      in .fire?  then @game.fire target
      in .throw? then @game.throw letter, target if letter
      in .zap?   then @game.zap letter, target if letter
      in .read?  then scroll.try { |found| @game.aim_reading found, target }
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

      # A scroll that was read and then backed out of does what it does with
      # nothing to aim at. It is spent either way, and being told it found
      # nothing beats losing it in silence.
      @aimed.try { |scroll| @game.aim_reading scroll, nil }
      @aimed = nil

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
      return if @aiming.try &.read?

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
        if @game.marks_first? letter
          bless_with letter
        elsif @game.target_needed? letter
          aim_with letter
        elsif @game.choice_needed? letter
          identify_with letter
        else
          @game.read letter
        end
      end
    end

    # Reads a scroll that wants a square, then puts the cursor up.
    #
    # The scroll is spent and the turn is taken before the question, because
    # what the scroll wants a square for depends on the blessing on it, and
    # reading it is how the character finds that out. Backing out of the aim
    # gives up what the scroll had left to do.
    private def aim_with(letter : Char) : Nil
      scroll = @game.start_aiming_read letter
      refresh
      return unless scroll

      @aimed = scroll
      start_aiming Aiming::Read, nil, 0
    end

    # Reads a scroll of blessing or of remove curse, then asks what it works
    # on.
    #
    # The scroll is spent and the marks are made before the question goes up,
    # because the marks are what the character picks by. `#refresh` between
    # the two puts them on screen.
    private def bless_with(letter : Char) : Nil
      scroll = @game.start_reading letter
      refresh
      return unless scroll

      ask_the_target scroll
    end

    # Asks which carried item the spent *scroll* works on.
    #
    # Backing out of this gives up what the scroll had left to do, so it asks
    # again before it lets go.
    private def ask_the_target(scroll : Item) : Nil
      found = @game.player.inventory.entries
      if found.empty?
        @game.finish_reading scroll, nil
        refresh
        return
      end

      title = scroll.kind.effect.remove_curse? ? "Lift a curse from what?" : "Bless what?"
      choose(title, rows(found), about(found)) do |key|
        if key
          @game.finish_reading scroll, key
          refresh
        else
          confirm_giving_up scroll
        end
      end
    end

    # Checks that backing out of the scroll's question was meant.
    #
    # The scroll is gone either way. What is being given up is the one thing
    # it had left to do.
    private def confirm_giving_up(scroll : Item) : Nil
      ask("Give up what the scroll has left? The marks stay either way.",
        "yn", default: 'n') do |key|
        if key == 'y'
          @game.finish_reading scroll, nil
          refresh
        else
          ask_the_target scroll
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

      choose("Identify what?", rows(found), about(found)) do |key|
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

      choose("Take off what?", entries, about(held.map &.[1])) do |key|
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

      choose("Apply what?", entries, applying_about(found)) do |key|
        next unless key

        target = found[Widgets::Menu.index key]?
        next unless target

        @game.apply target
        refresh
      end
    end

    # What each row of the apply menu is about.
    #
    # A row for a wall sconce is about no carried item, so it is left out and
    # the highlight on it hangs no box.
    private def applying_about(found : Array(Apply)) : Hash(Char, Item)
      detail = {} of Char => Item

      found.each_with_index do |target, index|
        letter = target.letter
        next unless letter

        item = @game.player.inventory[letter]
        next unless item

        detail[Widgets::Menu.letter index] = item
      end

      detail
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

      choose(title, rows(found), about(found)) do |key|
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
      restate_examine

      # The pane reads the floor for what is lying about and the knowledge for
      # what was lying about. A mark is something standing on a square, which
      # is the character now and the monsters later.
      @map.mark @game.player.x, @game.player.y, Palette::PLAYER
      offer_directions
      show_aim
      @pager.show @game.log.lines
      show_ending
    end

    # Writes the readout under the pointer again.
    #
    # Two things go stale between one refresh and the next. What is on the
    # square changes: a creature dies, an item is picked up, a door opens. And
    # the camera moves under a pointer that did not, so the cell the pointer
    # sits over is no longer the square the readout names.
    #
    # The keyboard cursor is moved by neither. It is held to a square rather
    # than to a cell, and `Examiner#move` brings that square into view rather
    # than letting the camera carry it off.
    private def restate_examine : Nil
      here = @pointer.spot
      return @examiner.restate if @examiner.cursoring? || here.nil?
      return if @examiner.point_at_screen here[0], here[1]

      @examiner.restate
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
      keep

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
      # A menu owns the screen while it is up, and it puts its own box up
      # from the row the highlight is on. The report has already moved that
      # highlight, so this leaves the box where the menu put it. What the
      # sidebar rows wrote down is dropped: they are behind the menu.
      if @menu.showing?
        @detailed = nil
        return @pointer.away
      end

      # Every other modal box owns the screen the same way, and none of them
      # has a box of its own to keep up.
      return pointer_away if modal?

      # The sidebar rows have already had this event and written down what
      # the pointer is over. A row with something to say puts the box up and
      # takes the pointer off the map: the pointer is not on the map.
      found = @detailed
      @detailed = nil
      app = @app

      if found && app
        @tooltip.show app, found[0], found[1]
        return @pointer.away
      end

      @tooltip.hide

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
    #
    # The tooltip goes with it. A box left hanging over a map nobody is
    # pointing at is a box in the way.
    def pointer_away : String?
      @tooltip.hide
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
      @entry.fit_into Rect.new(0, 0, columns, rows)

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
