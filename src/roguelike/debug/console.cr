require "../game"
require "./naming"

module Roguelike::Debug
  # A line typed into the debug console, and what it does.
  record Command,
    name : String,
    usage : String,
    summary : String,
    run : Proc(Console, Game, Array(String), Nil)

  # The commands the debug console runs, and what they have written.
  #
  # This class owns no widget and no terminal. `Ui::ConsolePane` draws what is
  # in `#lines` and hands typed lines to `#run`. A spec drives this class on
  # its own.
  #
  # Two rules hold for every command here.
  #
  # * A command takes no turn. Nothing else on the floor acts, so setting a
  #   test up does not change what is being tested.
  # * A command rolls nothing. No command touches an `Rng`, so `--seed N`
  #   plays out the same way whether or not the console was opened.
  class Console
    # How many lines are kept. Older ones are dropped.
    KEPT = 400

    # What the commands have written, oldest first.
    getter lines : Array(String) = [] of String

    # Runs *line* against *game* and writes what it did.
    #
    # A blank line does nothing at all, the way a shell treats one.
    def run(line : String, game : Game) : Nil
      words = line.split
      return if words.empty?

      say "> #{line}"

      name = words.shift.downcase
      found = TABLE.find { |command| command.name == name }
      unless found
        say "no such command: #{name}. Type help."
        return
      end

      found.run.call self, game, words
    end

    # Writes *line*.
    def say(line : String) : Nil
      @lines << line

      while @lines.size > KEPT
        @lines.shift
      end
    end

    # The number *words* start with. `nil` when they start with none.
    def self.number(words : Array(String)) : Int32?
      words.first?.try &.to_i?
    end

    # The square *words* name, as `x,y` or as `x y`. `nil` for neither.
    def self.square(words : Array(String)) : {Int32, Int32}?
      parts = words.join(' ').split(/[\s,]+/).reject &.empty?
      return unless parts.size == 2

      across = parts[0].to_i?
      down = parts[1].to_i?
      return unless across && down

      {across, down}
    end

    # ------------------------------------------------------------ the table

    # Every command, in the order `help` lists them.
    TABLE = [
      Command.new("help", "help", "list these commands",
        ->(console : Console, _game : Game, _words : Array(String)) : Nil do
          console.list_commands
        end),

      Command.new("heal", "heal [N]", "put N hit points back, or fill up",
        ->(console : Console, game : Game, words : Array(String)) : Nil do
          player = game.player
          put_back = player.heal(number(words) || player.max_hit_points)

          console.say "healed #{put_back}, now on " \
                      "#{player.hit_points}/#{player.max_hit_points}."
        end),

      Command.new("hurt", "hurt N", "take N hit points off, down to one",
        ->(console : Console, game : Game, words : Array(String)) : Nil do
          console.wound game, number(words)
        end),

      Command.new("spawn", "spawn <item>", "make an item and carry it",
        ->(console : Console, game : Game, words : Array(String)) : Nil do
          console.spawn game, words
        end),

      Command.new("identify", "identify <letter>", "learn one item, or a class",
        ->(console : Console, game : Game, words : Array(String)) : Nil do
          console.identify game, words
        end),

      Command.new("remove-curse", "remove-curse <letter>", "take a curse off",
        ->(console : Console, game : Game, words : Array(String)) : Nil do
          console.remove_curse game, words
        end),

      Command.new("kill", "kill <x>,<y>", "kill the creature on a square",
        ->(console : Console, game : Game, words : Array(String)) : Nil do
          console.slay game, square(words)
        end),

      Command.new("inspect", "inspect [<x>,<y>]", "print a creature, or you",
        ->(console : Console, game : Game, words : Array(String)) : Nil do
          console.inspect_at game, words
        end),

      Command.new("goto", "goto <x>,<y>", "put the character on a square",
        ->(console : Console, game : Game, words : Array(String)) : Nil do
          spot = square words
          console.say spot ? console.walk_to(game, spot) : "say a square, as x,y."
        end),

      Command.new("reveal", "reveal", "remember the whole floor",
        ->(console : Console, game : Game, _words : Array(String)) : Nil do
          floor = game.floor
          floor.each do |column, row, _tile|
            game.player.knowledge.touch floor, column, row, game.turn
          end

          console.say "remembered #{floor.columns * floor.rows} squares."
        end),

      Command.new("light", "light [N]", "set the floor's ambient light",
        ->(console : Console, game : Game, words : Array(String)) : Nil do
          wanted = number words
          game.floor.ambient = wanted if wanted

          console.say "ambient light is #{game.floor.ambient}."
        end),
    ]

    # --------------------------------------------------------- the long ones

    # Writes every command with its summary.
    #
    # This is a method rather than the body of `help`'s own proc. A proc in
    # `TABLE` that reads `TABLE` is a constant that refers to itself, and the
    # compiler recurses until it runs out of stack on one.
    def list_commands : Nil
      TABLE.each do |command|
        say "  #{command.usage.ljust 20} #{command.summary}"
      end
    end

    # Takes *amount* hit points off, leaving at least one.
    #
    # A character at zero is dead, and ending the run belongs to the blow that
    # killed them. The console deals no blows. So this stops at one and the
    # last point is left to something that can end a run.
    def wound(game : Game, amount : Int32?) : Nil
      return say "say how much to hurt for." unless amount

      player = game.player
      taken = player.hurt Math.min(amount, player.hit_points - 1)

      say "took #{taken} off, now on " \
          "#{player.hit_points}/#{player.max_hit_points}."
    end

    # Makes what *words* name and puts it in the pack.
    #
    # Gold is counted rather than carried, so it goes to the purse. Anything
    # else lands underfoot when every inventory letter is taken.
    def spawn(game : Game, words : Array(String)) : Nil
      made = Debug.item words
      return say made if made.is_a? String

      if made.kind.item_class.treasure?
        game.player.take_gold made.count
        return say "gave #{made.count} gold, now carrying #{game.player.gold}."
      end

      made.enrol game.next_id
      letter = game.player.inventory.add made
      unless letter
        game.floor.drop game.player.x, game.player.y, made
        return say "every letter is taken, so #{game.name made} is underfoot."
      end

      say "#{letter} - #{game.name made}"
    end

    # Learns one carried item, or every kind of one class.
    def identify(game : Game, words : Array(String)) : Nil
      wanted = words.first?.try &.downcase
      return say "say a letter, or potions, scrolls, wands or all." unless wanted

      classes = CLASSES[wanted]?
      return learn_classes game, classes if classes
      return say "say one letter, not #{wanted}." unless wanted.size == 1

      letter = wanted[0]
      item = game.player.inventory[letter]
      return say "nothing is under #{letter}." unless item

      game.lore.learn item.kind
      item.reveal_blessing
      say "#{letter} - #{game.name item}"
    end

    # What each word `identify` takes names.
    CLASSES = {
      "potions" => [ItemClass::Potion],
      "scrolls" => [ItemClass::Scroll],
      "wands"   => [ItemClass::Wand],
      "all"     => [ItemClass::Potion, ItemClass::Scroll, ItemClass::Wand],
    }

    # Learns every kind of each of *classes*.
    private def learn_classes(game : Game, classes : Array(ItemClass)) : Nil
      learned = classes.sum do |item_class|
        ItemKind.of_class(item_class).count { |kind| game.lore.learn kind }
      end

      say "learned #{learned} kinds."
    end

    # Takes the curse off one carried item, or off every one.
    def remove_curse(game : Game, words : Array(String)) : Nil
      wanted = words.first?.try &.downcase
      return say "say a letter, or all." unless wanted

      inventory = game.player.inventory

      if wanted == "all"
        lifted = inventory.entries.count { |_letter, item| item.uncurse }
        return say "lifted #{lifted} curses."
      end

      return say "say one letter, not #{wanted}." unless wanted.size == 1

      letter = wanted[0]
      item = inventory[letter]
      return say "nothing is under #{letter}." unless item
      return say "#{letter} was not cursed." unless item.uncurse

      say "#{letter} - #{game.name item}"
    end

    # Kills whatever stands on *spot*.
    def slay(game : Game, spot : {Int32, Int32}?) : Nil
      return say "say a square, as x,y." unless spot

      creature = game.floor.monster spot[0], spot[1]
      return say "nothing is standing on #{spot[0]},#{spot[1]}." unless creature

      game.kill creature
      say "killed the #{creature.label}."
    end

    # Prints the creature on the square *words* name, or the character.
    def inspect_at(game : Game, words : Array(String)) : Nil
      return describe_player game if words.empty?

      spot = Console.square words
      return say "say a square, as x,y." unless spot

      creature = game.floor.monster spot[0], spot[1]
      return say "nothing is standing on #{spot[0]},#{spot[1]}." unless creature

      describe game, creature
    end

    # Writes what *creature* is.
    private def describe(game : Game, creature : Monster) : Nil
      say "#{creature.label} at #{creature.x},#{creature.y}, " \
          "#{game.floor.awareness(creature).label}"
      say "  #{creature.hit_points}/#{creature.max_hit_points} hit points, " \
          "armor class #{creature.armor_class}, damage #{creature.damage}"
      say "  #{creature.attributes}, band #{creature.band}, " \
          "worth #{creature.species.experience}"

      describe_pack game, creature.carrying
    end

    # Writes what the character is.
    private def describe_player(game : Game) : Nil
      player = game.player

      say "you at #{player.x},#{player.y} on #{game.floor.id}, turn #{game.turn}"
      say "  #{player.hit_points}/#{player.max_hit_points} hit points, " \
          "armor class #{player.armor_class}, damage #{player.damage}"
      say "  #{player.attributes}, level #{player.level}, " \
          "#{player.experience} experience, #{player.gold} gold"

      describe_pack game, player.inventory.entries.map &.last
    end

    # Writes *carrying*, one item to a line.
    private def describe_pack(game : Game, carrying : Array(Item)) : Nil
      return say "  carrying nothing" if carrying.empty?

      say "  carrying:"
      carrying.each { |item| say "    #{game.name item}" }
    end

    # Puts the character on *spot*. Answers what to write.
    def walk_to(game : Game, spot : {Int32, Int32}) : String
      floor = game.floor
      unless floor.contains? spot[0], spot[1]
        return "#{spot[0]},#{spot[1]} is off the floor."
      end

      unless floor.passable? spot[0], spot[1]
        return "#{spot[0]},#{spot[1]} cannot be walked onto."
      end

      creature = floor.monster spot[0], spot[1]
      return "the #{creature.label} is standing there." if creature

      game.player.move_to spot
      "moved to #{spot[0]},#{spot[1]}."
    end
  end
end
