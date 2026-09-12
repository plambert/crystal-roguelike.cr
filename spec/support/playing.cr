require "./headless"

# A `Roguelike::Ui::Play` over a buffer, wired the way `Session` wires it.
#
# `Session` owns a terminal. `Play` owns everything else. So this module is
# the whole game short of the device. It builds the same widget tree, the same
# keymap and the same mouse handling. A spec presses keys at the code the game
# runs. It does not press keys at a copy.
module Playing
  # The seed every spec uses. A spec may pass another. A failure then names a
  # run a person can start.
  SEED = 20260911_u64

  # One wired game, and everything a spec needs to drive it.
  class Run
    # The game and everything it draws.
    getter play : Roguelike::Ui::Play

    # The buffer the game draws into.
    getter session : Headless::Session

    # Every sequence the terminal would have been sent. Oldest first. The
    # pointer shapes arrive here.
    getter told : Array(String)

    def initialize(@play : Roguelike::Ui::Play,
                   @session : Headless::Session,
                   @told : Array(String))
    end

    delegate game, screen, map, examine, examiner, pointer, prompt, pager, menu, to: @play

    # Whether the run should end.
    def finished? : Bool
      @play.finished?
    end

    delegate render, rows, row, text, buffer, to: @session

    # Where the character is.
    def at : {Int32, Int32}
      game.player.at
    end

    # What has just happened, oldest first.
    def log : Array(String)
      game.log.lines
    end

    # The most recent message.
    def said : String
      game.log.last? || ""
    end

    # How many turns have been taken.
    def turn : Int32
      game.turn
    end

    # Presses the keys *description* names.
    def press(description : String) : Nil
      @session.press description
      @session.render
    end

    # :ditto: Presses each in turn. A walk uses this.
    def press(*descriptions : String) : Nil
      descriptions.each { |description| press description }
    end

    # A motion report with no button held. Mode 1003 sends these.
    def hover(x : Int32, y : Int32) : Nil
      @session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::None, x, y,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Motion)
      @session.render
    end

    # The left button going down at *x*, *y* of the buffer.
    def click(x : Int32, y : Int32) : Nil
      @session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::Left, x, y,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Press)
      @session.render
    end

    # Resizes the terminal under the game. Dragging a window does the
    # same.
    def resize(columns : Int32, rows : Int32) : Nil
      @play.fit columns, rows
      @session.resize columns, rows
      @session.render
    end
  end

  # A game on one open room of *columns* by *rows*. The character starts in
  # the middle.
  #
  # The shipped floor has every door shut until phase 6 opens them. The
  # character cannot leave the room they start in. The camera never has to
  # move. A spec about walking a long way needs somewhere to walk.
  def self.field(columns : Int32 = 120, rows : Int32 = 60,
                 seed : UInt64 = SEED) : Roguelike::Game
    map = Array.new(rows) do |row|
      String.build(columns) do |line|
        columns.times do |column|
          edge = row.zero? || column.zero? || row == rows - 1 || column == columns - 1
          middle = row == rows // 2 && column == columns // 2
          line << (edge ? '#' : middle ? '<' : '.')
        end
      end
    end

    floor = Roguelike::Floor.parse "field", map
    world = Roguelike::World.new seed, {floor.id => floor}

    Roguelike::Game.new world,
      Roguelike::Player.new(floor.id, *Roguelike::Game.entrance(floor))
  end

  # A run on *game*, drawn in a window of *columns* by *rows*.
  def self.open(game : Roguelike::Game? = nil,
                columns : Int32 = 80,
                rows : Int32 = 24) : Run
    play = Roguelike::Ui::Play.new(game || Roguelike::Game.start(Roguelike::Rng.new(SEED)))
    play.fit columns, rows

    session = Headless.open play.root, columns, rows
    play.app = session.app
    told = [] of String

    session.app.keymap = session.app.keymap
      .merge(play.bindings)
      .merge(Roguelike::Ui::Keys.application { play.confirm_quit })
    session.app.on_event = ->(event : TermBuf::Event) do
      report = event.as? TermBuf::Events::Mouse

      if report
        sequence = play.pointed report.x, report.y,
          Roguelike::Session.click?(report)
        told << sequence if sequence
      end

      nil
    end

    # One layout runs before the camera is pointed. `Session` does the
    # same.
    session.render
    play.look_at_player
    session.render

    Run.new play, session, told
  end
end
