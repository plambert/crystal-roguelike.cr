require "shell-auto_complete"

module Roguelike
  # The command line.
  #
  # This class does not declare `--version`. The shard finds
  # `Roguelike::VERSION` in the enclosing namespace. The compiler reads that
  # constant out of `shard.yml` at build time.
  Shell::AutoComplete.command Cli,
    name: "crystal-roguelike",
    description: "A terminal roguelike" do
    flag seed : UInt64?, "--seed",
      "Start from this seed, which reproduces a run exactly"

    # Nothing reads this flag yet. Monster planning will run in a
    # `Fiber::ExecutionContext::Parallel` sized by it. The flag is declared now
    # so that a shell alias written today keeps working.
    flag threads : Int32 = 1, "--threads",
      "Threads for monster planning (not used yet)", range: 1..64

    flag flicker : Bool = true, "--flicker",
      "Let flames waver. --no-flicker holds them still"

    flag generate : Bool = true, "--generate",
      "Dig a floor from the seed. --no-generate plays the floor that ships"

    flag character : String?, "--character",
      "Play as this character, carrying on from their save if there is one"

    flag save : Bool = true, "--save",
      "Write the run to the saves directory. --no-save leaves it unwritten"

    flag saves : Bool = false, "--saves",
      "List the saved characters and where they are kept, then stop"

    # A development tool. It is off unless this is passed, so a normal run has
    # neither the box nor the key that opens it.
    flag debug_console : Bool = false, "--debug-console",
      "Open a console with ` for commands that change the running game"

    # A development tool. It takes no terminal and plays no game a person
    # sees. `Trial` says what the numbers mean and what they do not.
    flag trial : Int32 = 0, "--trial",
      "Play this many games with a bot and print how they went", range: 0..100_000

    flag trial_turns : Int32 = Trial::TURNS, "--trial-turns",
      "How many turns one --trial game is given", range: 1..1_000_000

    def run
      return listed if saves
      return played if trial > 0

      session = Session.open seed, flicker: flicker, generate: generate,
        console: debug_console, store: save ? Save::Store.default : nil,
        character: character

      exit 1 unless session

      # These lines run after the terminal is restored. The alternate screen
      # is gone by then. They stay in the scrollback.
      #
      # The last run is the one reported on. A person who played four rounds
      # is told how the fourth ended, and its seed, which is the one they
      # would pass to `--seed` to play it again.
      game = session.game
      puts case game.outcome
      in .won?     then "You escaped with your life. You win."
      in .left?    then "You climbed back out."
      in .died?    then "You died in the dungeon."
      in .playing? then "You left the dungeon where it was."
      end
      puts "seed #{game.world.seed}    turn #{game.turn}"
    end

    # Prints the saved characters and the ended ones, newest first.
    #
    # Both directories are printed whether or not there is anything in them,
    # so a person who wants to back the files up or edit one is told where to
    # look.
    private def listed : Nil
      store = Save::Store.default

      print_held store.directory, store.characters, "no saved characters"
      puts
      print_held store.ended, store.endings, "no characters have ended yet"
    end

    # Prints *held*, under the directory it came out of.
    private def print_held(where : Path, held : Array(Save::Held),
                           empty : String) : Nil
      puts where
      return puts empty if held.empty?

      held.each do |one|
        puts "#{one.name}\t#{Save.slug one.name}\tlevel #{one.level}" \
             "\tturn #{one.turn}\t#{one.outcome.to_s.downcase}\t#{one.saved}"
      end
    end

    # Plays `--trial` games and prints how they went.
    #
    # No terminal is opened. A run starts from `--seed` when one was named, so
    # two builds are compared over the same dungeons.
    private def played : Nil
      first = seed || Trial::FIRST

      puts "from seed #{first}, at most #{trial_turns} turns a run"
      print Trial.play(trial, first, trial_turns)
    end
  end
end
