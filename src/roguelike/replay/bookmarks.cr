require "../../roguelike"

module Roguelike
  module Replay
    # The run as it stood at each pause a resume goes back to.
    #
    # Everything that plays a file back holds one. A resume that follows its
    # pause directly carries the same run on, because a save and a load
    # change nothing about it. A resume that follows actions the save does
    # not hold puts the run back to the pause first, the way the process
    # that loaded the save did.
    #
    # Only the pauses `Reading#rewound` names are kept. A copy of the run is
    # about a hundred kilobytes a floor, and most files go back to none.
    class Bookmarks
      # The pauses a resume goes back to.
      getter wanted : Set(Int32)

      # The run at each wanted pause, as JSON.
      @kept = {} of Int32 => String

      # Every pause seen so far.
      @seen = Set(Int32).new

      def initialize(@wanted : Set(Int32))
      end

      # The bookmarks *reading* needs.
      def self.for(reading : Reading) : Bookmarks
        new reading.rewound
      end

      # Notes *pause*, and keeps the run when a resume goes back to it.
      def paused(pause : Pause, game : Game) : Nil
        @seen << pause.pause
        @kept[pause.pause] = game.to_json if @wanted.includes? pause.pause
      end

      # Whether the pause *resume* names has been seen.
      def seen?(resume : Resume) : Bool
        @seen.includes? resume.pause
      end

      # The run *resume* carries on.
      #
      # It is *game* itself unless the resume goes back past actions, and then
      # it is the run as it stood at the pause. Either way the character
      # looks, which is what a loaded run does before its first action.
      def resumed(resume : Resume, game : Game) : Game
        found = @kept[resume.pause]?
        game = Game.from_json found if found
        game.look
        game
      end
    end
  end
end
