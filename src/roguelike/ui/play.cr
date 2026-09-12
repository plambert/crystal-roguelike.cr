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

    # The one-key question, when there is one.
    getter prompt : Widgets::Prompt

    # The application this play is drawn on.
    #
    # The owner sets this once it has built an `App`. A question needs it to
    # push a focus scope. Nothing else here uses it.
    property app : Widgets::App? = nil

    # A command waiting for a direction. `nil` when none is.
    getter pending : Pending? = nil

    # Whether the run should end.
    #
    # The person asked to leave, or the game ended, and the final question has
    # been answered.
    getter? finished : Bool = false

    def initialize(@game : Game)
      @screen = Screen.new
      @map = MapPane.new @game.level
      @screen.show @map.grid

      @examine = ExaminePane.new
      @screen.show_sidebar @examine.root
      @examiner = Examiner.new @map, @examine
      @pointer = Pointer.new

      @screen.scaffold @game.world.seed

      @prompt = Widgets::Prompt.new
      @screen.show_status @prompt

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
    end

    # Asks *question*. Runs *answered* with the key the person pressed.
    #
    # The prompt takes the row the status text is on. The status text hides
    # while the question is up.
    def ask(question : String, keys : String, default : Char? = nil,
            &answered : Char? -> Nil) : Nil
      app = @app
      raise "Play#app has not been set" unless app

      @screen.status_text.hidden = true
      @prompt.on_answer = ->(key : Char?) do
        @screen.status_text.hidden = false
        answered.call key
        nil
      end

      @prompt.ask app, question, keys, default
    end

    # Asks whether the person wants to leave. Leaves on yes.
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
    # A step that does not happen costs no turn.
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

      return if @game.step(direction).blocked?

      @map.follow @game.player.x, @game.player.y
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
      @map.mark @game.player.x, @game.player.y, Palette::PLAYER
      @screen.status_text.text = status
    end

    # The status line. *mouse* belongs to the terminal. A caller passes it
    # in.
    def status(mouse : Bool = true) : String
      player = @game.player

      "seed #{@game.world.seed}    turn #{@game.turn}    " \
      "at #{player.x},#{player.y}    " \
      "mouse #{mouse ? "on" : "off"}    " \
      "x to look, ? for the keys"
    end

    # Records that the pointer is at *x*, *y* of the buffer.
    #
    # Answers the sequence the terminal needs. Answers `nil` when it needs
    # none.
    def pointed(x : Int32, y : Int32) : String?
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
      @screen.fit columns, rows
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

    # Writes *line* where the status text goes, until the next `#refresh`.
    private def say(line : String) : Nil
      @screen.status_text.text = line
    end
  end
end
