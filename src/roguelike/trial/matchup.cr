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
    # A kind that shoots starts `RANGE` squares off with `ROOM` squares behind
    # it. The character walks in. The monster shoots, backs away as
    # `Pursuit` says, and closes to melee once its ammunition is gone.
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

      # How many squares off a kind that shoots starts.
      RANGE = Pursuit::FARTHEST

      # How many squares a kind that shoots can back away before a wall stops
      # it.
      ROOM = 4

      # Everyone the character is matched against, one row for each kind.
      def self.opponents : Array(Kind)
        Kind.values
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
      # A kind that shoots then rolls its ammunition. The character spends a
      # turn on each step while it is more than a square away.
      def self.fight(kit : Kit, kind : Kind, rng : Rng) : Result
        player = kit.character
        health = kind.hit_dice.roll rng
        monster = Monster.new kind, 1, 0, "matchup",
          hit_points: health, max_hit_points: health
        arm monster, rng
        start = player.hit_points
        swing = Costs.swing player.wielded
        field = Field.new(monster.ranged_weapon ? RANGE : 1, ROOM)
        ticks = 0

        while ticks < LIMIT
          if field.distance > 1
            field.distance -= 1
            player.pace.spend Costs::TURN
          else
            blow = Combat.swing rng, player.to_hit, monster.armor_class, player.damage
            monster.hurt blow.damage if blow.hit?
            return Result.new true, ticks + 1, start - player.hit_points unless monster.alive?

            player.pace.spend swing
          end

          until player.pace.ready?
            while monster.pace.ready?
              monster.pace.spend act(monster, player, field, rng)
              return Result.new false, ticks + 1, start - player.hit_points unless player.alive?
            end

            player.pace.gain
            monster.pace.gain
            ticks += 1
          end
        end

        Result.new false, ticks, start - player.hit_points
      end

      # How far apart the two stand, and how far the monster can still back
      # away.
      class Field
        property distance : Int32
        property room : Int32

        def initialize(@distance : Int32, @room : Int32)
        end
      end

      # Gives *monster* its kind's ranged weapon and ammunition, rolled on
      # *rng*. Plain pieces, with no plus.
      def self.arm(monster : Monster, rng : Rng) : Nil
        ranged_weapon = monster.kind.ranged_weapon
        ammunition = ranged_weapon.try &.ammunition
        return unless ranged_weapon && ammunition

        count = Math.max monster.kind.quiver.roll(rng), 1
        monster.carry [Item.new(ranged_weapon), Item.new(ammunition, count: count)]
      end

      # What *monster* does with one action. Answers what it cost.
      #
      # It follows `Pursuit`. Closer than `Pursuit::NEAREST` it backs away
      # while the room lets it. It shoots from farther than a square. Out of
      # ammunition, or cornered beside the character, it walks in and swings.
      def self.act(monster : Monster, player : Player, field : Field, rng : Rng) : Int32
        weapon = monster.ranged_weapon
        ammunition = monster.ammunition

        if weapon && ammunition
          if field.distance < Pursuit::NEAREST && field.room > 0
            field.distance += 1
            field.room -= 1
            return Costs::TURN
          end

          if field.distance > 1
            bonus = monster.to_shoot weapon, ammunition
            damage = Combat.shot weapon, ammunition
            monster.draw_shot 0
            blow = Combat.swing rng, bonus, player.armor_class, damage
            player.hurt blow.damage if blow.hit?
            return Costs.loose weapon
          end
        end

        if field.distance > 1
          field.distance -= 1
          return Costs::TURN
        end

        blow = Combat.swing rng, monster.to_hit, player.armor_class, monster.damage
        player.hurt blow.damage if blow.hit?
        monster.kind.swing
      end

      # The stream the fights of one cell roll on.
      def self.stream(seed : UInt64, kit : Kit, kind : Kind) : Rng
        Rng.new(seed).derive("matchup").derive("kit:#{kit.depth}")
          .derive("kind:#{kind}")
      end

      # Plays *fights* fights of *kit* against *kind* and sums them.
      def self.cell(kit : Kit, kind : Kind, fights : Int32 = FIGHTS,
                    seed : UInt64 = FIRST) : Cell
        rng = stream seed, kit, kind
        wins = turns = damage = 0

        fights.times do |index|
          result = fight kit, kind, rng.derive("fight", index)
          wins += 1 if result.won
          turns += result.turns
          damage += result.damage
        end

        Cell.new fights, wins, turns, damage
      end

      # Every cell, from *seed*.
      def self.play(fights : Int32 = FIGHTS, seed : UInt64 = FIRST,
                    kits : Array(Kit) = KITS,
                    opponents : Array(Kind) = self.opponents) : Table
        cells = opponents.map do |kind|
          kits.map { |kit| cell kit, kind, fights, seed }
        end

        Table.new opponents, kits, cells, fights, seed
      end

      # The cells of a matchup, with the axes they sit on.
      record Table, opponents : Array(Kind), kits : Array(Kit),
        cells : Array(Array(Cell)), fights : Int32, seed : UInt64 do
        # The cell for row *row* and column *column*.
        def [](row : Int32, column : Int32) : Cell
          @cells[row][column]
        end

        def to_s(io : IO) : Nil
          io << "matchup from seed " << @seed << ", " << @fights << " fights a cell\n"
          io << "the character strikes first, in an empty room, until one of them dies\n"
          shooters = @opponents.select &.ranged_weapon
          unless shooters.empty?
            io << "these start " << RANGE << " squares off with " << ROOM
            io << " to back into, and shoot until their ammunition is gone:\n"
            shooters.each do |kind|
              io << "  " << kind.label << ", " << kind.ranged_weapon.try(&.label)
              io << " and " << kind.quiver << ' ' << kind.ranged_weapon.try(&.ammunition).try(&.plural) << '\n'
            end
          end
          io << '\n'

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

          @opponents.each_with_index do |kind, row|
            io << "  " << kind.label.ljust(label)
            @kits.each_index { |column| io << (yield self[row, column]).rjust(8) }
            io << '\n'
          end
        end
      end
    end
  end
end
