require "../../roguelike"

module Roguelike
  module Trial
    # Who beats whom.
    #
    # A fight is one character against one monster, side by side in an empty
    # room. The character always strikes first and both swing until one of
    # them dies. Nothing else is in the room, so a cell is the two creatures
    # and nothing more: no light, no doors, no retreat and no potion.
    #
    # A kind that comes in bands has a second row as well, where several of
    # it stand round the character from the first swing.
    #
    # The table has a row for each opponent and a column for each kit. A kit
    # is what a character has by the time they reach a given depth. Both
    # axes are read from tables, so a kind or a kit added to either shows
    # up here without an edit.
    #
    # Every fight rolls on a stream named for the seed, the kit and the
    # opponent, so a table is the same from run to run.
    module Matchup
      # One item a kit holds, readied where it belongs.
      record Gear, kind : ItemKind, enchantment : Int32 = 0 do
        # What the legend calls it, such as "+1 short sword".
        def label : String
          return @kind.label if @enchantment.zero?

          "#{@enchantment > 0 ? '+' : '-'}#{@enchantment.abs} #{@kind.label}"
        end

        # The item this stands for.
        def item : Item
          Item.new @kind, @enchantment, blessing_known: true
        end
      end

      # What a character has reached a given depth with.
      record Kit, depth : Int32, level : Int32, gear : Array(Gear) do
        # The column heading.
        def heading : String
          "D#{@depth}"
        end

        # What the legend says this kit is.
        def label : String
          "level #{@level}, #{@gear.map(&.label).join(", ")}"
        end

        # A character of this kit, with the gear readied.
        def character : Player
          player = Player.new "matchup", 0, 0, level: @level

          @gear.each do |piece|
            item = piece.item
            slot = Slot.for item
            letter = player.inventory.add item
            player.equipment.put slot, letter if slot && letter
          end

          player
        end
      end

      # One kit for each depth, from the first to the fifth.
      #
      # Level 1 is what the game starts a character with. Each later kit adds
      # what a character would plausibly have found and earned by going one
      # floor further down.
      KITS = [
        Kit.new(1, 1, [
          Gear.new(ItemKind::ShortSword),
          Gear.new(ItemKind::LeatherArmor),
        ]),
        Kit.new(2, 2, [
          Gear.new(ItemKind::ShortSword, 1),
          Gear.new(ItemKind::LeatherArmor),
        ]),
        Kit.new(3, 3, [
          Gear.new(ItemKind::ShortSword, 1),
          Gear.new(ItemKind::ChainMail),
        ]),
        Kit.new(4, 4, [
          Gear.new(ItemKind::LongSword, 1),
          Gear.new(ItemKind::ChainMail),
          Gear.new(ItemKind::Cap),
        ]),
        Kit.new(5, 5, [
          Gear.new(ItemKind::LongSword, 2),
          Gear.new(ItemKind::ChainMail, 1),
          Gear.new(ItemKind::Cap),
          Gear.new(ItemKind::Shield),
        ]),
      ]

      # How many fights a cell holds unless told otherwise.
      FIGHTS = 2000

      # The most ticks one fight is given.
      #
      # A landed swing does damage and a critical always lands, so every
      # fight ends. This is a bound for the loop, and a fight that reaches it
      # counts as not won.
      LIMIT = 1000

      # What one row of the table fights: *count* creatures of *kind*.
      record Opponent, kind : Kind, count : Int32 = 1 do
        # The row heading.
        def label : String
          return @kind.label if @count == 1

          "#{@count} #{@kind.plural}"
        end

        # What its stream is named for.
        def stream : String
          return "kind:#{@kind}" if @count == 1

          "kind:#{@kind}x#{@count}"
        end
      end

      # The rows with more than one creature in them.
      #
      # Three ants is the smallest band the generator places. Surrounding is
      # what ants do, so the three stand round the character from the start.
      BANDS = [Opponent.new(Kind::Ant, 3)]

      # Everyone the character is matched against: one row for each kind,
      # then each of `BANDS`.
      def self.opponents : Array(Opponent)
        Kind.values.map { |kind| Opponent.new kind } + BANDS
      end

      # How one fight came out.
      record Result, won : Bool, turns : Int32, damage : Int32

      # What a set of fights against one opponent came to.
      record Cell, fights : Int32, wins : Int32, turns : Int32, damage : Int32 do
        # The share of fights the character won, out of a hundred.
        def win_rate : Float64
          return 0.0 if @fights.zero?

          100.0 * @wins / @fights
        end

        # Turns a fight took, on average.
        def mean_turns : Float64
          return 0.0 if @fights.zero?

          @turns.to_f / @fights
        end

        # Hit points the character lost, on average.
        def mean_damage : Float64
          return 0.0 if @fights.zero?

          @damage.to_f / @fights
        end
      end

      # Plays one fight of *kit* against *kind*, rolled on *rng*.
      #
      # Time runs the way `Game` runs it. The character swings and pays what
      # its weapon costs. The world then ticks until the character can act
      # again, and on each tick the monster takes every action it has banked,
      # each paying what its kind's swing costs. A dagger at 75 swings four
      # times in three ticks, and an orc at speed 95 with a swing of 120
      # attacks a little under four times in five.
      #
      # The monster rolls its hit points from its kind's hit dice, as one the
      # generator places does. Turns are ticks of the world, counting the one
      # the fight ends in.
      #
      # Against a band the character swings at one creature until it dies
      # and then the next. Every creature left swings in turn. They stand in
      # opposite pairs, so while two or more are alive each member of a pair
      # adds `Combat::FLANKING`, and an odd one out does not.
      def self.fight(kit : Kit, opponent : Opponent, rng : Rng) : Result
        player = kit.character
        kind = opponent.kind
        band = Array.new opponent.count do
          health = kind.hit_dice.roll rng
          Monster.new kind, 1, 0, "matchup", hit_points: health, max_hit_points: health
        end
        start = player.hit_points
        swing = Costs.swing player.wielded
        ticks = 0

        while ticks < LIMIT
          target = band.first
          blow = Combat.swing rng, player.to_hit, target.armor_class, player.damage
          target.hurt blow.damage if blow.hit?
          band.shift unless target.alive?
          return Result.new true, ticks + 1, start - player.hit_points if band.empty?

          player.pace.spend swing

          until player.pace.ready?
            paired = band.size // 2 * 2
            band.each_with_index do |monster, index|
              bonus = index < paired ? Combat::FLANKING : 0
              while monster.pace.ready?
                monster.pace.spend kind.swing
                blow = Combat.swing rng, monster.to_hit + bonus, player.armor_class, monster.damage
                player.hurt blow.damage if blow.hit?
                return Result.new false, ticks + 1, start - player.hit_points unless player.alive?
              end
            end

            player.pace.gain
            band.each &.pace.gain
            ticks += 1
          end
        end

        Result.new false, ticks, start - player.hit_points
      end

      # :ditto: One creature of *kind*.
      def self.fight(kit : Kit, kind : Kind, rng : Rng) : Result
        fight kit, Opponent.new(kind), rng
      end

      # The stream the fights of one cell roll on.
      def self.stream(seed : UInt64, kit : Kit, opponent : Opponent) : Rng
        Rng.new(seed).derive("matchup").derive("kit:#{kit.depth}")
          .derive(opponent.stream)
      end

      # Plays *fights* fights of *kit* against *kind* and sums them.
      def self.cell(kit : Kit, kind : Kind, fights : Int32 = FIGHTS,
                    seed : UInt64 = FIRST) : Cell
        cell kit, Opponent.new(kind), fights, seed
      end

      # :ditto: Against *opponent*.
      def self.cell(kit : Kit, opponent : Opponent, fights : Int32 = FIGHTS,
                    seed : UInt64 = FIRST) : Cell
        rng = stream seed, kit, opponent
        wins = turns = damage = 0

        fights.times do |index|
          result = fight kit, opponent, rng.derive("fight", index)
          wins += 1 if result.won
          turns += result.turns
          damage += result.damage
        end

        Cell.new fights, wins, turns, damage
      end

      # Every cell, from *seed*.
      def self.play(fights : Int32 = FIGHTS, seed : UInt64 = FIRST,
                    kits : Array(Kit) = KITS,
                    opponents : Array(Opponent) = self.opponents) : Table
        cells = opponents.map do |opponent|
          kits.map { |kit| cell kit, opponent, fights, seed }
        end

        Table.new opponents, kits, cells, fights, seed
      end

      # The cells of a matchup, with the axes they sit on.
      record Table, opponents : Array(Opponent), kits : Array(Kit),
        cells : Array(Array(Cell)), fights : Int32, seed : UInt64 do
        # The cell for row *row* and column *column*.
        def [](row : Int32, column : Int32) : Cell
          @cells[row][column]
        end

        def to_s(io : IO) : Nil
          io << "matchup from seed " << @seed << ", " << @fights << " fights a cell\n"
          io << "the character strikes first, in an empty room, until one of them dies\n\n"

          @kits.each { |kit| io << "  " << kit.heading << "  " << kit.label << '\n' }

          section io, "win rate, out of a hundred" do |cell|
            cell.win_rate.round(1).to_s
          end

          section io, "mean turns to a decision" do |cell|
            cell.mean_turns.round(1).to_s
          end

          section io, "mean hit points the character lost" do |cell|
            cell.mean_damage.round(1).to_s
          end
        end

        # One table of one number, a row for each opponent.
        private def section(io : IO, title : String, & : Cell -> String) : Nil
          label = @opponents.max_of &.label.size
          label = Math.max label, 8

          io << '\n' << title << '\n'
          io << "  " << "".ljust(label)
          @kits.each { |kit| io << kit.heading.rjust(8) }
          io << '\n'

          @opponents.each_with_index do |opponent, row|
            io << "  " << opponent.label.ljust(label)
            @kits.each_index { |column| io << (yield self[row, column]).rjust(8) }
            io << '\n'
          end
        end
      end
    end
  end
end
