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

    # The window the level is played in.
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
      @map = MapPane.new @game.level
      @screen.show @map.grid

      @examine = ExaminePane.new
      @screen.show_sidebar @examine.root
      @examiner = Examiner.new @map, @examine
      @pointer = Pointer.new

      @screen.scaffold @game.world.seed

      @status_line = StatusLine.new
      @screen.show_status @status_line.bar

      @pager = Widgets::Pager.new
      @screen.show_log @pager

      # The prompt is a float. `Overlay#open` puts it in the tree the first
      # time a question is asked.
      @prompt = Widgets::Prompt.new

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
      app = @app
      raise "Play#app has not been set" unless app

      @prompt.on_answer = ->(key : Char?) do
        park_camera_back
        answered.call key
        nil
      end

      clear_the_character
      @prompt.ask app, question, keys, default
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

    # Puts the camera on the character.
    #
    # The owner calls this once the tree has been laid out. It cannot run
    # before. An unmeasured window is nothing by nothing. Centring on a square
    # in a window of no size leaves the camera on the square. It does not
    # clamp against the edge of the level.
    def look_at_player : Nil
      @map.center_on @game.player.x, @game.player.y
    end

    # One step of a movement key.
    #
    # A command waiting for a direction takes the key first. The examine
    # cursor takes it next. A person reading the level is not walking about
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

      @examiner.stop
    end

    # Puts the camera on the character.

    # Puts what the game holds back on the screen.
    #
    # Everything shown comes from `Game`. This method is the one place the two
    # are put in step. It runs after anything that changes the game.
    def refresh : Nil
      @map.clear_marks
      @map.clear_highlights
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

    # Records that the pointer is at *x*, *y* of the buffer.
    #
    # Answers the sequence the terminal needs. Answers `nil` when it needs
    # none.
    def pointed(x : Int32, y : Int32) : String?
      # A question and a held page are modal. Nothing else answers a pointer
      # while one is up.
      return pointer_away if @prompt.asking? || @pager.holding?
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
