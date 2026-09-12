module Roguelike::Ui
  # The bindings that belong to the whole application rather than to any one
  # widget.
  #
  # Kept apart from `Session` because `Session` owns a terminal and this does
  # not: a spec builds an `App` over a buffer, installs these, and drives them
  # with synthetic key events.
  #
  # Each set is built on its own and merged, so a spec can install the one it
  # is about and nothing else.
  module Keys
    # The eight keys that move, in the layout NetHack made standard: `hjkl`
    # for the cardinals and `yubn` for the corners, laid out the way they sit
    # on the keyboard.
    #
    # They move the examine cursor while it is on the map and the player
    # otherwise, which is why they are bound once and dispatched by whatever
    # is listening rather than bound twice.
    MOVES = {
      "h" => Direction::West,
      "j" => Direction::South,
      "k" => Direction::North,
      "l" => Direction::East,
      "y" => Direction::NorthWest,
      "u" => Direction::NorthEast,
      "b" => Direction::SouthWest,
      "n" => Direction::SouthEast,
    }

    # Binds the application's own keys on *app* and puts the help overlay on
    # `F1` and `?`, answering the overlay so a caller can ask whether it is up.
    #
    # *on_quit* runs when the player asks to leave. Ending the run is the
    # caller's to do, because what that means depends on what owns the loop.
    def self.install(app : Widgets::App, &on_quit : -> Nil) : Widgets::HelpOverlay
      app.keymap = app.keymap.merge application(&on_quit)
      Widgets::HelpOverlay.install app
    end

    # What the application answers under whatever a widget claims first.
    def self.application(&on_quit : -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Q"), "leave the game",
          ->(_context : Widgets::Context) { on_quit.call; nil }
      end
    end

    # The eight movement keys, each handing its direction to *on_move*.
    def self.moving(&on_move : Direction -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        MOVES.each do |key, direction|
          map.bind TermBuf::Key.parse(key), "move #{direction.label}",
            ->(_context : Widgets::Context) { on_move.call direction; nil }
        end
      end
    end

    # `x` to put the examine cursor on the map and take it off again, and
    # `Escape` to take it off whatever put it there.
    def self.examining(examiner : Examiner) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("x"), "look at a square",
          ->(_context : Widgets::Context) { examiner.toggle; nil }
        map.bind TermBuf::Key.parse("Escape"), "stop looking",
          ->(_context : Widgets::Context) { examiner.stop; nil }
      end
    end

    # `M` to turn mouse reporting on and off.
    #
    # It is a toggle because a terminal reporting the mouse no longer lets the
    # person select and copy with it, and reading the screen is worth more
    # than pointing at it often enough that the choice has to be theirs.
    def self.mousing(&on_toggle : -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("M"), "turn the mouse on or off",
          ->(_context : Widgets::Context) { on_toggle.call; nil }
      end
    end
  end
end
