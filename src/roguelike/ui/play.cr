module Roguelike::Ui
  # Everything the game shows and everything the keys do, with no device
  # anywhere.
  #
  # `Session` owns a terminal, a frame loop and the mouse; this owns the rest.
  # Splitting them is what lets a spec press `hjkl` at the thing the game
  # actually runs, rather than at a copy of its wiring assembled beside it.
  #
  # It decides nothing about the game. Every rule is `Game`'s; this reads the
  # answer, puts it on the screen, and tells the caller what the terminal
  # needs to hear.
  class Play
    # The run.
    getter game : Game

    # The regions being drawn in.
    getter screen : Screen

    # The window the level is played in.
    getter map : MapPane

    # The readout of what is on one square.
    getter examine : ExaminePane

    # What points the readout, from the pointer or from the keyboard.
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

    # Puts the camera on the character.
    #
    # Called by the owner once the tree has been laid out, and not before: a
    # window that has not been measured is nothing by nothing, and centring on
    # a square in a window of no size leaves the camera on the square rather
    # than clamped against the edge of the level.
    def look_at_player : Nil
      @map.center_on @game.player.x, @game.player.y
    end

    # The tree, for an `App` to be built over.
    def root : Widgets::Widget
      @screen.root
    end

    # The bindings that are the game's rather than the application's.
    def bindings : Widgets::Bindings
      Keys.examining(@examiner).merge Keys.moving { |direction| step direction }
    end

    # One step of a movement key.
    #
    # It moves the examine cursor while that is on the map, because somebody
    # reading the level is not walking about it. Everywhere else it is the
    # character, and a step that does not happen costs no turn.
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
    # Everything shown comes from `Game`, so this is the one place the two are
    # put in step, and it runs after anything that changes the game rather
    # than being remembered in half a dozen places.
    def refresh : Nil
      @map.clear_marks
      @map.mark @game.player.x, @game.player.y, Palette::PLAYER
      @screen.status_text.text = status
    end

    # The status line. *mouse* is the terminal's to know, so it is passed in.
    def status(mouse : Bool = true) : String
      player = @game.player

      "seed #{@game.world.seed}    turn #{@game.turn}    " \
      "at #{player.x},#{player.y}    " \
      "mouse #{mouse ? "on" : "off"}    " \
      "x to look, ? for the keys"
    end

    # The pointer is at *x*, *y* of the buffer.
    #
    # Answers the sequence the terminal needs, or `nil` when it needs none.
    def pointed(x : Int32, y : Int32) : String?
      return pointer_away unless @examiner.point_at_screen x, y

      @pointer.over x, y
    end

    # The pointer is somewhere the map is not, or the mouse has been turned
    # off, or the run is ending.
    def pointer_away : String?
      @pointer.away
    end

    # Answers the layout to a screen of *columns* by *rows*.
    def fit(columns : Int32, rows : Int32) : Nil
      @screen.fit columns, rows
    end
  end
end
