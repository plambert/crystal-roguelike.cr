module Roguelike::Ui
  # What goes on the title screen and on the screen a run ends with.
  #
  # These are lines of text and nothing else. `Placard` draws them and `Play`
  # decides when. Keeping the wording here leaves one place to read what a
  # person is told at the start and at the end of a run.
  module Placards
    # What the title screen is headed with.
    NAME = "crystal-roguelike"

    # The key the row that starts a new character takes.
    #
    # It is the first row, so a person who presses `Enter` at the title
    # screen starts a new character.
    NEW_KEY = 'a'

    # What that row says.
    NEW_ROW = "new character"

    # The key the row that leaves takes.
    #
    # Upper case, so it is never handed to a saved character however many of
    # them there are. `Escape` does the same thing.
    QUIT_KEY = 'Q'

    # What that row says.
    QUIT_ROW = "quit"

    # What the name question asks.
    #
    # The empty line holds a name the game rolled, dimmed. `Enter` takes it,
    # which is what "or take this one" points at.
    NAME_QUESTION = "Who is playing? Enter takes the name offered."

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

    # What the title menu is headed with.
    #
    # The seed goes in it, because that is what a bug report needs and the
    # title screen is where somebody reads it.
    def self.title_bar(seed : UInt64) : String
      "#{NAME} #{build} · seed #{seed}"
    end

    # What one saved character's row says.
    def self.saved_row(held : Save::Held) : String
      "#{held.name} — #{standing held}"
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
