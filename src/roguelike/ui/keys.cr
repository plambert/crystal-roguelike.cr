module Roguelike::Ui
  # The bindings that belong to the whole application rather than to any one
  # widget.
  #
  # Kept apart from `Session` because `Session` owns a terminal and this does
  # not: a spec builds an `App` over a buffer, installs these, and drives them
  # with synthetic key events.
  module Keys
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
  end
end
