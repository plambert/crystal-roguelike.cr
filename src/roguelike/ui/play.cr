module Roguelike::Ui
  # A command waiting for a direction.
  enum Pending
    Open
    Close

    # What the command is called, for a message.
    def verb : String
      case self
      in .open?  then "open"
      in .close? then "close"
      end
    end

    # The terrain this command acts on. Every square holding it beside the
    # character is an answer.
    def terrain : Terrain
      case self
      in .open?  then Terrain::ClosedDoor
      in .close? then Terrain::OpenDoor
      end
    end
  end

  # Everything the game shows. Everything the keys do. No device anywhere.
  #
  # `Session` owns a terminal, a frame loop and the mouse. This class owns the
  # rest. The split lets a spec press keys at the code the game runs. A spec
  # does not press keys at a copy of that wiring.
  #
  # This class decides nothing about the game. Every rule belongs to `Game`.
  # This class reads the answer, puts it on the screen, and tells the caller
  # what the terminal needs to hear.
  class Play
    # The run.
    getter game : Game

    # The regions being drawn in.
    getter screen : Screen

    # The window the floor is played in.
    getter map : MapPane

    # The readout of what is on one square.
    getter examine : ExaminePane

    # What points the readout. The pointer or the keyboard.
    getter examiner : Examiner

    # What the mouse pointer is doing.
    getter pointer : Pointer

    # What the character is, on one row.
    getter status_line : StatusLine

    # What has just happened, held at a page boundary when a turn says more
    # than the pane shows at once.
    getter pager : Widgets::Pager

    # The list of things to choose from, when there is one.
    getter menu : Widgets::Menu

    # The one-key question, when there is one.
    getter prompt : Widgets::Prompt

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

    # Whether the run should end.
    #
    # The person asked to leave, or the game ended, and the final question has
    # been answered.
    getter? finished : Bool = false

    # Where the camera was before a question moved it. `nil` when no question
    # has moved it.
    @parked : {Int32, Int32}? = nil

    # The size of the screen, as `#fit` was last told it.
    @columns : Int32 = 0
    @rows : Int32 = 0

    def initialize(@game : Game)
      @screen = Screen.new
      @map = MapPane.new @game.floor
      @screen.show @map.grid

      @examine = ExaminePane.new
      @screen.show_sidebar @examine.root
      @examiner = Examiner.new @map, @examine
      @examiner.lore = @game.lore
      @pointer = Pointer.new

      @screen.scaffold @game.world.seed

      @status_line = StatusLine.new
      @screen.show_status @status_line.bar

      @pager = Widgets::Pager.new
      @screen.show_log @pager

      # Both are floats. `Overlay#open` puts one in the tree the first time it
      # is used.
      @prompt = Widgets::Prompt.new
      @menu = Widgets::Menu.new

      refresh
    end

    # The tree. A caller builds an `App` over it.
    def root : Widgets::Widget
      @screen.root
    end

    # The bindings that belong to the game rather than to the application.
    def bindings : Widgets::Bindings
      Keys.examining(self)
        .merge(Keys.moving { |direction| step direction })
        .merge(Keys.acting(self))
        .merge(Keys.debugging(self))
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
    # so a pointer over the map is on the examine cursor's own square anyway.
    # A pointer that is resting while the keyboard moves the cursor is a
    # pointer the person is not using.
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
      @prompt.asking? || @menu.showing? || @pager.holding?
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
        return
      end

      # A blocked step says why. The pane has to be redrawn either way.
      done = @game.step direction
      @map.follow @game.player.x, @game.player.y unless done.blocked?
      refresh
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

      finish "You climb down and out of the dungeon. You win.", 'y'
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
        finish "You climb out and go home."
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

      @game.floor.each_pile do |column, row, pile|
        last = pile.last?
        @map.mark column, row, Palette[last] if last
      end

      @map.mark @game.player.x, @game.player.y, Palette::PLAYER
      offer_directions
      @pager.show @game.log.lines
      @status_line.show @game
    end

    # Lights up every square that answers the command waiting for a direction.
    #
    # A person asked which way has to see which way. Four doors around one
    # square are four answers, and the question is which of them.
    private def offer_directions : Nil
      waiting = @pending
      return unless waiting

      @game.doors(waiting.terrain).each do |direction|
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
    def fit(columns : Int32, rows : Int32) : Nil
      @columns = columns
      @rows = rows
      @screen.fit columns, rows
      @pager.resize Screen.log_width(columns), Screen::LOG_ROWS
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

    # Whether the log is holding a page that has not been read.
    def holding? : Bool
      @pager.holding?
    end

    # Runs *command* on the door *direction*.
    private def act(command : Pending, direction : Direction) : Nil
      done = case command
             in .open?  then @game.open direction
             in .close? then @game.close direction
             end

      unless done
        say "There is nothing to #{command.verb} that way."
        return
      end

      refresh
    end

    # Ends the run. Holds *line* on the screen until the person presses a key.
    private def finish(line : String, key : Char = 'q') : Nil
      ask(line, key.to_s, default: key) { @finished = true }
    end

    # Writes whether the terminal is reporting the mouse.
    def mousing=(wanted : Bool) : Nil
      @status_line.mousing = wanted
    end

    # Grants *amount* experience and says what that did.
    #
    # A debug binding. Levelling is worth watching before there is anything to
    # kill, and this is how phase 8 watches it.
    def grant(amount : Int32) : Nil
      gained = @game.player.gain amount
      @game.say "You gain #{amount} experience."
      @game.say "Welcome to level #{@game.player.level}." if gained > 0
      refresh
    end

    # Adds *line* to the log.
    private def say(line : String) : Nil
      @game.say line
      refresh
    end
  end
end
