require "./headless"

# A `Roguelike::Ui::Play` over a buffer, wired the way `Session` wires it.
#
# `Session` owns a terminal and `Play` owns everything else, so this is the
# whole game short of the device: the same widget tree, the same keymap, the
# same mouse handling. A spec presses keys at the thing that runs rather than
# at a copy of it.
module Playing
  # The seed every spec uses unless it wants another, so that a failure names
  # a run somebody can start.
  SEED = 20260911_u64

  # One wired game, and everything a spec needs to poke it.
  class Run
    # The game and everything it draws.
    getter play : Roguelike::Ui::Play

    # The buffer it is drawn into.
    getter session : Headless::Session

    # Every sequence the terminal would have been sent, oldest first, which is
    # where the pointer shapes go.
    getter told : Array(String)

    def initialize(@play : Roguelike::Ui::Play,
                   @session : Headless::Session,
                   @told : Array(String))
    end

    delegate game, screen, map, examine, examiner, pointer, to: @play
    delegate render, rows, row, text, buffer, to: @session

    # Where the character is.
    def at : {Int32, Int32}
      game.player.at
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

    # :ditto: for each of them in turn, which is what a walk is.
    def press(*descriptions : String) : Nil
      descriptions.each { |description| press description }
    end

    # A motion report with no button held, which is what mode 1003 sends.
    def hover(x : Int32, y : Int32) : Nil
      @session.send TermBuf::Events::Mouse.new(
        TermBuf::Input::Mouse::Button::None, x, y,
        TermBuf::Modifiers::None,
        TermBuf::Input::Mouse::Action::Motion)
      @session.render
    end

    # Resizes the terminal under it, as a window being dragged would.
    def resize(columns : Int32, rows : Int32) : Nil
      @play.fit columns, rows
      @session.resize columns, rows
      @session.render
    end
  end

  # A game on one open room of *columns* by *rows*, with the character in the
  # middle of it.
  #
  # The shipped level has every door shut until phase 6 opens them, so the
  # character cannot leave the room they start in and the camera never has to
  # move. Anything about walking a long way wants somewhere to walk.
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

    level = Roguelike::Level.parse "field", map
    world = Roguelike::World.new seed, {level.id => level}

    Roguelike::Game.new world,
      Roguelike::Player.new(level.id, *Roguelike::Game.entrance(level))
  end

  # A run on *game*, drawn in a window of *columns* by *rows*.
  def self.open(game : Roguelike::Game? = nil,
                columns : Int32 = 80,
                rows : Int32 = 24) : Run
    play = Roguelike::Ui::Play.new(game || Roguelike::Game.start(Roguelike::Rng.new(SEED)))
    play.fit columns, rows

    session = Headless.open play.root, columns, rows
    told = [] of String

    session.app.keymap = session.app.keymap.merge play.bindings
    session.app.on_event = ->(event : TermBuf::Event) do
      report = event.as? TermBuf::Events::Mouse

      if report
        sequence = play.pointed report.x, report.y
        told << sequence if sequence
      end

      nil
    end

    # One layout before the camera is pointed, the way `Session` does it.
    session.render
    play.look_at_player
    session.render

    Run.new play, session, told
  end
end
