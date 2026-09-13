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

    # The keys the end screen answers.
    AGAIN_KEYS = "yn"

    # The one `Enter` answers with.
    #
    # Quitting. A person pressing `Enter` to get a screen out of the way is
    # not asking to start a whole new run.
    AGAIN_DEFAULT = 'n'

    # What the end screen says the keys do.
    AGAIN_FOOTER = "Play again? y starts a new run, n quits."

    # The title screen for a run on *seed*.
    def self.title(seed : UInt64) : Array(String)
      [
        "",
        "A dungeon dug from seed #{seed}.",
        "",
        "Press ? at any time for the list of keys.",
        "",
      ]
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
