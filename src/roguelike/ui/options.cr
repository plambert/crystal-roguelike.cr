require "../../crystal-roguelike"

module Roguelike
  class Options
    # Pushes each option that a module or the session holds.
    #
    # The game calls this once at start with no session, again for each
    # session it opens, and after every change on the options screen. Bar
    # color is read where the bars are drawn.
    def apply(session : Session? = nil) : Nil
      Ui::Motion.on = motion?
      return unless session

      apply_to session
    end

    # Applies the two session-owned display preferences to *display*.
    def apply_to(display) : Nil
      display.mousing = mouse?
      display.flickering = flicker?
    end
  end
end
