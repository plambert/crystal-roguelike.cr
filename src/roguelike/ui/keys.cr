module Roguelike::Ui
  # The bindings that belong to the whole application.
  #
  # This module sits apart from `Session`. `Session` owns a terminal. This
  # module owns none. A spec builds an `App` over a buffer, installs these
  # bindings, and sends synthetic key events.
  #
  # Each set is built on its own. A caller merges the sets it wants. A spec
  # installs only the set it is about.
  module Keys
    # The eight keys that move.
    #
    # NetHack made this layout standard. `hjkl` are the cardinals. `yubn` are
    # the corners. Each key sits on the keyboard where its direction points.
    #
    # These keys are bound once. Whatever is listening decides what they move.
    # The examine cursor moves while it is on the map. The character moves
    # otherwise.
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

    # Binds the application's own keys on *app*. Puts the help overlay on `F1`
    # and `?`. Answers the overlay so a caller can ask whether it is up.
    #
    # *on_quit* runs when the player asks to leave. Ending the run belongs to
    # the caller. What ending means depends on what owns the loop.
    def self.install(app : Widgets::App, &on_quit : -> Nil) : Widgets::HelpOverlay
      app.keymap = app.keymap.merge application(&on_quit)
      Widgets::HelpOverlay.install app
    end

    # What the application answers after every widget declines a key.
    def self.application(&on_quit : -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Q"), "leave the game",
          ->(_context : Widgets::Context) { on_quit.call; nil }
      end
    end

    # The eight movement keys. Each hands its direction to *on_move*.
    def self.moving(&on_move : Direction -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        MOVES.each do |key, direction|
          map.bind TermBuf::Key.parse(key), "move #{direction.label}",
            ->(_context : Widgets::Context) { on_move.call direction; nil }
        end
      end
    end

    # `x` puts the examine cursor on the map and takes it off again. `Escape`
    # takes it off.
    def self.examining(examiner : Examiner) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("x"), "look at a square",
          ->(_context : Widgets::Context) { examiner.toggle; nil }
        map.bind TermBuf::Key.parse("Escape"), "stop looking",
          ->(_context : Widgets::Context) { examiner.stop; nil }
      end
    end

    # `M` turns mouse reporting on and off.
    #
    # This is a toggle. A terminal reporting the mouse no longer lets the
    # person select and copy with it. Reading the screen is worth more than
    # pointing at it often enough that the person must choose.
    def self.mousing(&on_toggle : -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("M"), "turn the mouse on or off",
          ->(_context : Widgets::Context) { on_toggle.call; nil }
      end
    end
  end
end
