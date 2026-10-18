require "../../roguelike"

module Roguelike
  module Submit
    # What a parcel says about the run it carries, without opening the log.
    class Meta
      include JSON::Serializable

      # The game's version.
      getter version : String

      # What the binary was built for. See `Submit::PLATFORM`.
      getter platform : String

      # How the run stood when the parcel was packed: `playing`, `died`,
      # `won` or `left`.
      getter outcome : String

      # The turn the run was on.
      getter turn : Int32

      # The run's seed.
      getter seed : UInt64

      # The character's name.
      getter character : String

      # The identity of the log for the server. See `Submit.log_id`.
      getter log : String

      # Who is playing. Left out when this process has no tester.
      @[JSON::Field(emit_null: false)]
      getter tester : Tester?

      def initialize(@version : String, @platform : String, @outcome : String,
                     @turn : Int32, @seed : UInt64, @character : String,
                     @log : String, @tester : Tester? = nil)
      end

      # What *game* is described as now, for the log called *log*.
      def self.of(game : Game, log : String) : Meta
        new VERSION, PLATFORM, game.outcome.to_s.downcase, game.turn,
          game.world.seed, game.player.name, log, Tester.current
      end
    end
  end
end
