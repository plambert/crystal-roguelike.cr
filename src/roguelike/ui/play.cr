module Roguelike::Ui
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

    def initialize(@game : Game)
      @screen = Screen.new
      @map = MapPane.new @game.level
      @screen.show @map.grid

      @examine = ExaminePane.new
      @screen.show_sidebar @examine.root
      @examiner = Examiner.new @map, @examine
      @pointer = Pointer.new

      @screen.scaffold @game.world.seed
      refresh
    end

    # The tree. A caller builds an `App` over it.
    def root : Widgets::Widget
      @screen.root
    end

    # The bindings that belong to the game rather than to the application.
    def bindings : Widgets::Bindings
      Keys.examining(@examiner).merge Keys.moving { |direction| step direction }
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
    # The key moves the examine cursor while that cursor is on the map. A
    # person reading the level is not walking about it. The key moves the
    # character otherwise. A step that does not happen costs no turn.
    def step(direction : Direction) : Nil
      if @examiner.cursoring?
        @examiner.move direction
        return
      end

      return unless @game.step direction

      @map.follow @game.player.x, @game.player.y
      refresh
    end

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
  end
end
