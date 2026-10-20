require "../../crystal-roguelike"

module Roguelike
  class Options
    # Pushes each option that a module or the session holds.
    #
    # The game calls this once at start with no session, and again for each
    # session it opens. Bar color is read where the bars are drawn. Flicker
    # is passed to the session when it opens.
    def apply(session : Session? = nil) : Nil
      Ui::Motion.on = motion?
      session.mousing = mouse? if session
    end
  end
end
