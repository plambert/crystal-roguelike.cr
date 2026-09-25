require "./game"

module Roguelike
  # Plays the game without a terminal and says how it went.
  #
  # This is an instrument for tuning rather than a way to play. A change to a
  # number somewhere in the rules moves what comes out of here, and two sets
  # of runs are what say whether it made the game harder or easier.
  #
  # `Bot` plays badly and plays the same way every time. So the numbers say
  # how punishing the game is to somebody who walks into every fight and never
  # retreats. The size of a number here means little on its own. The
  # difference between two sets of runs is what to read.
  module Trial
    # What one run came to.
    record Played,
      seed : UInt64,
      turns : Int32,
      level : Int32,
      gold : Int32,
      reached : Int32,
      outcome : Outcome,
      killer : String?

    # What a set of runs came to.
    record Report, played : Array(Played) do
      # How many runs there were.
      def runs : Int32
        @played.size
      end

      # The runs that ended in a death.
      def deaths : Array(Played)
        @played.select &.outcome.died?
      end

      # The runs that reached the down staircase.
      def wins : Array(Played)
        @played.select &.outcome.won?
      end

      # How many runs out of a hundred ended in a death.
      def death_rate : Float64
        return 0.0 if runs.zero?

        100.0 * deaths.size / runs
      end

      # What killed the character, most often first.
      def killers : Array({String, Int32})
        found = Hash(String, Int32).new 0
        deaths.each { |run| found[run.killer || "something"] += 1 }

        found.to_a.sort_by { |pair| -pair[1] }
      end

      def to_s(io : IO) : Nil
        io << runs << " runs"
        io << '\n'
        count io, "died", deaths.size
        count io, "won", wins.size
        count io, "gave up", runs - deaths.size - wins.size

        spread io, "turns until death", deaths.map &.turns
        spread io, "squares from start", @played.map &.reached
        mean io, "level reached", @played.map &.level
        mean io, "gold", @played.map &.gold

        io << "  killed by           "
        io << killers.map { |name, many| "#{name} #{many}" }.join(", ")
        io << '\n'
      end

      # One row: how many runs, and how many out of a hundred.
      private def count(io : IO, label : String, many : Int32) : Nil
        io << "  " << label.ljust(20) << many.to_s.rjust(5)
        io << (runs.zero? ? 0 : 100 * many // runs).to_s.rjust(5) << "%\n"
      end

      # One row: the middle of *numbers* and the two ends of them.
      private def spread(io : IO, label : String, numbers : Array(Int32)) : Nil
        return if numbers.empty?

        sorted = numbers.sort
        io << "  " << label.ljust(20)
        io << "median " << sorted[sorted.size // 2]
        io << "   range " << sorted.first << ".." << sorted.last << '\n'
      end

      # One row: the mean of *numbers* and the largest of them.
      private def mean(io : IO, label : String, numbers : Array(Int32)) : Nil
        return if numbers.empty?

        io << "  " << label.ljust(20)
        io << "mean " << (numbers.sum / numbers.size.to_f).round(2)
        io << "   best " << numbers.max << '\n'
      end
    end

    # The first seed a set of runs plays.
    FIRST = 5000_u64

    # How many turns one run is given before it is stopped.
    TURNS = 1500

    # Plays *runs* games from *first* and answers how they went.
    #
    # *cautious* plays the bot that backs away when it is badly hurt rather
    # than the one that never retreats.
    def self.play(runs : Int32, first : UInt64 = FIRST,
                  turns : Int32 = TURNS, cautious : Bool = false) : Report
      Report.new (0...runs).map { |index| one first + index, turns, cautious }
    end

    # Plays one game from *seed* and answers how it went.
    def self.one(seed : UInt64, turns : Int32 = TURNS,
                 cautious : Bool = false) : Played
      bot = cautious ? Cautious.new(seed) : Bot.new(seed)

      turns.times do
        break if bot.game.over?

        bot.turn
      end

      game = bot.game
      Played.new seed, game.turn, game.player.level, game.player.gold,
        bot.reached, game.outcome, game.killer
    end

    # One game, played by a rule rather than by a person.
    #
    # The rule, in the order it is asked:
    #
    # 1. Take the staircase down when standing on it.
    # 2. Drink something when below `HURT` out of a hundred hit points.
    # 3. Swing at whatever is standing next to it.
    # 4. Pick up what is underfoot, and hold the heaviest hitting weapon it
    #    is carrying.
    # 5. Step to a neighbor, preferring one it has never stood on.
    #
    # It never retreats, never shuts a door behind it, never shoots and never
    # puts its torch out. Those are the things that keep a person alive, so
    # these numbers are the pessimistic end of what the game is.
    class Bot
      # The run being played.
      getter game : Game

      # Where the character started.
      getter start : {Int32, Int32}

      # Below this many hit points out of a hundred, it drinks.
      HURT = 40

      def initialize(seed : UInt64)
        @game = Game.dug Rng.new(seed)
        @rng = Rng.new(seed).derive "trial"
        @start = @game.player.at
        @been = Set({Int32, Int32}).new
      end

      # How far from where it started the character got, in squares walked
      # across and down.
      def reached : Int32
        here = @game.player.at

        (here[0] - @start[0]).abs + (here[1] - @start[1]).abs
      end

      # One turn.
      def turn : Nil
        return if @game.over?
        return if @game.descend
        return if drank
        return if swung
        return if took

        wander
      end

      # Whether it is below `HURT` out of a hundred hit points.
      protected def hurt? : Bool
        player = @game.player

        player.hit_points * 100 // player.max_hit_points < HURT
      end

      # Drinks something when badly hurt. Answers whether it did.
      protected def drank : Bool
        return false unless hurt?

        player = @game.player
        found = player.inventory.entries.find do |_letter, item|
          item.kind.item_class.potion?
        end
        return false unless found

        @game.quaff found[0]
        true
      end

      # Swings at whatever is standing next to it. Answers whether it did.
      protected def swung : Bool
        beside = @game.adjacent.first?
        return false unless beside

        here = @game.player.at
        way = Direction.values.find do |direction|
          direction.from(here[0], here[1]) == beside.at
        end
        return false unless way

        @game.step way
        true
      end

      # Takes what is underfoot. Answers whether it did.
      protected def took : Bool
        pile = @game.here
        return false if pile.empty?

        @game.pick_up pile.first
        hold_the_best
        true
      end

      # Holds the heaviest hitting weapon it is carrying.
      private def hold_the_best : Nil
        best = @game.player.inventory.select do |item|
          item.kind.item_class.melee?
        end.max_by? { |_letter, item| item.damage.average }
        return unless best

        held = @game.player.wielded
        return if held && held.damage.average >= best[1].damage.average

        @game.wield best[0]
      end

      # Steps to a neighbor, preferring one it has never stood on.
      #
      # Walking into a shut door opens it, so this is all the door handling
      # the bot needs.
      protected def wander : Nil
        here = @game.player.at
        @been << here

        ways = Direction.values.select do |direction|
          spot = direction.from here[0], here[1]
          @game.floor.contains?(spot[0], spot[1]) &&
            !@game.floor.terrain(spot[0], spot[1]).rock?
        end
        return if ways.empty?

        fresh = ways.reject do |direction|
          @been.includes? direction.from(here[0], here[1])
        end

        @game.step (fresh.empty? ? ways : fresh).sample(@rng)
      end
    end

    # A bot that backs away from a fight it is losing.
    #
    # The same rule as `Bot` with one step in front of the swing: when it is
    # below `Bot::HURT` out of a hundred hit points and something is standing
    # next to it, it steps to whichever square takes it furthest from that
    # creature.
    #
    # It is here to measure what a speed is worth. A bot that never retreats
    # takes the same beating whether it can outwalk what is hitting it or
    # not, so the gap between these two sets of runs is what being faster
    # buys somebody who uses it.
    class Cautious < Bot
      def turn : Nil
        return if @game.over?
        return if @game.descend
        return if drank
        return if fled
        return if swung
        return if took

        wander
      end

      # Steps away from whatever is beside it. Answers whether it did.
      #
      # It answers false when no square takes it further off, so a bot in a
      # corner turns and fights rather than standing still to be hit.
      private def fled : Bool
        return false unless hurt?

        beside = @game.adjacent.first?
        return false unless beside

        here = @game.player.at
        gap = Notice.apart here, beside.at

        away = Direction.values.select do |direction|
          spot = direction.from here[0], here[1]
          @game.floor.passable?(spot[0], spot[1]) &&
            !@game.floor.monster?(spot[0], spot[1])
        end.max_by? do |direction|
          Notice.apart direction.from(here[0], here[1]), beside.at
        end
        return false unless away

        return false unless Notice.apart(away.from(here[0], here[1]), beside.at) > gap

        @game.step away
        true
      end
    end
  end
end
