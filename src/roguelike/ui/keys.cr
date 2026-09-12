module Roguelike::Ui
  # The bindings that belong to the whole application.
  #
  # This module sits apart from `Session`. `Session` owns a terminal. This
  # module owns none. A spec builds an `App` over a buffer, installs these
  # bindings, and sends synthetic key events.
  #
  # Each set is built on its own. A caller merges whichever sets apply. A spec
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

    # The eight movement keys. Each passes its direction to *on_move*.
    def self.moving(&on_move : Direction -> Nil) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        MOVES.each do |key, direction|
          map.bind TermBuf::Key.parse(key), "move #{direction.label}",
            ->(_context : Widgets::Context) { on_move.call direction; nil }
        end
      end
    end

    # `x` puts the examine cursor on the map and takes it off again. `Escape`
    # takes back whatever is waiting.
    def self.examining(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("x"), "look at a square",
          ->(_context : Widgets::Context) { play.examiner.toggle; nil }
        map.bind TermBuf::Key.parse("Escape"), "stop what is waiting",
          ->(_context : Widgets::Context) { play.cancel; nil }
      end
    end

    # `o` opens a door. `c` closes one. `<` and `>` take a staircase.
    #
    # *play* answers each of these. A door needs a direction, and `Play` finds
    # it or asks for it.
    def self.acting(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("o"), "open a door",
          ->(_context : Widgets::Context) { play.open_door; nil }
        map.bind TermBuf::Key.parse("c"), "close a door",
          ->(_context : Widgets::Context) { play.close_door; nil }
        map.bind TermBuf::Key.parse(","), "pick up what is here",
          ->(_context : Widgets::Context) { play.pick_up; nil }
        map.bind TermBuf::Key.parse("d"), "drop something",
          ->(_context : Widgets::Context) { play.drop; nil }
        map.bind TermBuf::Key.parse("i"), "look at what you are carrying",
          ->(_context : Widgets::Context) { play.show_inventory; nil }
        map.bind TermBuf::Key.parse(">"), "go down the staircase",
          ->(_context : Widgets::Context) { play.descend; nil }
        map.bind TermBuf::Key.parse("<"), "climb out of the dungeon",
          ->(_context : Widgets::Context) { play.ascend; nil }
      end
    end

    # The keys that are only there to try something out.
    #
    # `Ctrl+E` grants experience, so that levelling can be watched before
    # there is anything to kill. It goes when there is.
    def self.debugging(play : Play) : Widgets::Bindings
      Widgets::Bindings.build do |map|
        map.bind TermBuf::Key.parse("Ctrl+E"), "grant experience (debug)",
          ->(_context : Widgets::Context) { play.grant 10; nil }
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
