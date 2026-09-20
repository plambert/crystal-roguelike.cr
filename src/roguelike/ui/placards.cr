module Roguelike::Ui
  # What goes on the title screen and on the screen a run ends with.
  #
  # These are lines of text and nothing else. `Placard` draws them and `Play`
  # decides when. Keeping the wording here leaves one place to read what a
  # person is told at the start and at the end of a run.
  module Placards
    # What the title screen is headed with.
    NAME = "crystal-roguelike"

    # The keys the title screen answers.
    START_KEYS = "pq"

    # The one `Enter` answers with.
    START_DEFAULT = 'p'

    # What the title screen says the keys do.
    START_FOOTER = "p plays, q quits."

    # What the name question asks.
    #
    # The empty line holds a name the game rolled, dimmed. `Enter` takes it,
    # which is what "or take this one" points at.
    NAME_QUESTION = "Who is playing? Enter takes the name offered."

    # The most saved characters the title screen lists.
    MOST_SAVED = 8

    # What the name question asks again when the name has nothing in it that
    # makes a file name.
    NAME_UNUSABLE = "That name has no letters or digits in it. Try another."

    # What it asks again when the file that name would be written to belongs
    # to somebody else.
    #
    # The character in the way is named, so a person who meant to carry them
    # on can see how their name is spelled.
    def self.taken(whose : String) : String
      "#{whose} is saved already. Try another name."
    end

    # The keys the end screen answers.
    AGAIN_KEYS = "yn"

    # The one `Enter` answers with.
    #
    # Quitting. A person pressing `Enter` to get a screen out of the way is
    # not asking to start a whole new run.
    AGAIN_DEFAULT = 'n'

    # What the end screen says the keys do.
    AGAIN_FOOTER = "Play again? y starts a new run, n quits."

    # What the title screen says the build is.
    #
    # `Roguelike::VERSION` is read out of `shard.yml` when the game is
    # compiled. A released binary carries the tag it was built from, so a
    # person reporting a run can say which build they played.
    def self.build : String
      "version #{Roguelike::VERSION}"
    end

    # The title screen for a run on *seed*, with *saved* offered to carry on.
    #
    # The saved characters are listed so that a person can see which names
    # are taken before the name question asks for one. Typing one of them
    # carries that character on and the dug dungeon is thrown away, so the
    # seed is worth saying only for a run that is about to start fresh.
    def self.title(seed : UInt64, saved : Array(Save::Held) = [] of Save::Held) : Array(String)
      lines = [
        "",
        build,
        "A dungeon dug from seed #{seed}.",
        "",
      ]

      lines.concat carrying_on saved unless saved.empty?
      lines << "Press ? at any time for the list of keys."
      lines << ""

      lines
    end

    # The saved characters, one to a line, newest first.
    private def self.carrying_on(saved : Array(Save::Held)) : Array(String)
      lines = ["Saved characters:"]

      saved.first(MOST_SAVED).each do |held|
        lines << "  #{held.name}  #{standing held}"
      end

      left = saved.size - MOST_SAVED
      lines << "  and #{left} more" if left > 0
      lines << ""

      lines
    end

    # How one saved character stood when it was written.
    private def self.standing(held : Save::Held) : String
      return "level #{held.level}, turn #{held.turn}" unless held.outcome.over?

      "#{heading(held.outcome).downcase} on turn #{held.turn}"
    end

    # What the screen a run ends with is headed with.
    def self.heading(outcome : Outcome) : String
      case outcome
      in .won?     then "You win"
      in .died?    then "You died"
      in .left?    then "You left the dungeon"
      in .playing? then "The run goes on"
      end
    end

    # The screen *game* ends with.
    def self.ending(game : Game) : Array(String)
      lines = [ended(game), ""]
      lines.concat standing game
      lines << ""
      lines.concat carrying game
      lines << ""
      lines << "seed #{game.world.seed}"

      lines
    end

    # The first line: how the run ended.
    private def self.ended(game : Game) : String
      case game.outcome
      in .won?
        "You climbed down and out of the dungeon with your life."
      in .died?
        killer = game.killer
        killer ? "Killed by #{Lore.article killer} #{killer}." : "You were killed."
      in .left?
        "You climbed out the way you came in."
      in .playing?
        "The run has not ended."
      end
    end

    # What the character was when the run ended.
    private def self.standing(game : Game) : Array(String)
      player = game.player

      [
        "turn #{game.turn}",
        "level #{player.level}, #{player.experience} experience",
        "#{player.gold} gold",
      ]
    end

    # What the character was carrying, one item to a line.
    #
    # Everything is named as though it were known. A run is over, and a
    # person who died holding a wand they never zapped should be told what it
    # was.
    private def self.carrying(game : Game) : Array(String)
      entries = game.player.inventory.entries
      return ["You were carrying nothing."] if entries.empty?

      lore = game.lore.revealed
      lines = ["You were carrying:"]

      entries.each do |letter, item|
        slot = game.slot_of letter
        name = lore.name item
        name = "#{name} (#{slot.note})" if slot

        lines << "  #{name}"
      end

      lines
    end
  end
end
