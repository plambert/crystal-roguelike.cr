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

    flag replay_log : String?, "--replay-log",
      "Write every run to this file. %s is the character, %d a rising number"

    flag replay_every : Int32 = Replay::Log::EVERY, "--replay-every",
      "Turns between two checkpoints in a replay log", range: 1..1_000_000

    flag save : Bool = true, "--save",
      "Write the run to the saves directory. --no-save leaves it unwritten"

    flag saves : Bool = false, "--saves",
      "List the saved characters and where they are kept, then stop"

    # A development tool. It is off unless this is passed, so a normal run has
    # neither the box nor the key that opens it.
    #
    # It is hidden, so it is in neither the help nor the shell completions. It
    # is for whoever works on the game rather than for whoever plays it.
    flag debug_console : Bool = false, "--debug-console",
      "Open a console with ` for commands that change the running game",
      hidden: true

    # A development tool. It takes no terminal and plays no game a person
    # sees. `Trial` says what the numbers mean and what they do not.
    flag trial : Int32 = 0, "--trial",
      "Play this many games with a bot and print how they went", range: 0..100_000

    flag trial_turns : Int32 = Trial::TURNS, "--trial-turns",
      "How many turns one --trial game is given", range: 1..1_000_000

    flag trial_cautious : Bool = false, "--trial-cautious",
      "Play --trial with the bot that backs away when it is badly hurt"

    # A measurement rather than a game. Every species moves at this instead
    # of its own speed, which is how the death rate is read as a curve
    # against how fast the floor is.
    flag trial_speed : Int32 = 0, "--trial-speed",
      "Move every species at this speed during --trial. 100 is the character",
      range: 0..300

    def run
      return listed if saves
      return played if trial > 0

      Replay::Log.pattern = replay_log
      Replay::Log.every = replay_every
      Replay::Log.generate = generate

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

    # Prints the saved characters, the dead ones and the ones who came out,
    # newest first.
    #
    # Every directory is printed whether or not there is anything in it, so a
    # person who wants to back the files up or edit one is told where to look.
    private def listed : Nil
      store = Save::Store.default

      print_held store.directory, store.characters, "nobody is playing"
      puts
      print_held store.deaths, store.died, "nobody has died"
      puts
      print_held store.wins, store.won, "nobody has come out alive"
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
      Kinds.override = trial_speed if trial_speed > 0

      puts "from seed #{first}, at most #{trial_turns} turns a run"
      puts "every species at speed #{trial_speed}" if trial_speed > 0
      puts "the bot backs away when it is badly hurt" if trial_cautious

      print Trial.play(trial, first, trial_turns, trial_cautious)
    end
  end
end

module Roguelike
  class Cli
    # `crystal-roguelike replay`, which works on recorded runs.
    #
    # It does nothing on its own. `replay verify` is the one thing under it.
    # `bots/PROTOCOL.md` section 3.3 has two more, which are a viewer and an
    # export for analysis. Neither is built.
    Shell::AutoComplete.command Replaying,
      name: "replay",
      description: "Work on a run recorded with --replay-log" do
      def run
        puts self.class.help
      end
    end

    # `crystal-roguelike replay verify`, which plays recorded runs again.
    #
    # It exits 1 when any file differs from the run it recorded, so it is
    # what a build checks its golden replays with.
    Shell::AutoComplete.command Verifying,
      name: "verify",
      description: "Play recorded runs again and check them" do
      flag force : Bool = false, "--force",
        "Check a replay recorded by a build whose draw sequences have moved"

      positionals files : Array(Path), "The replay files to check", min: 1

      def run
        wrong = files.count do |file|
          report = Replay::Verifier.check file, force
          puts report
          !report.ok?
        end

        exit 1 if wrong > 0
      end
    end

    subcommand Replaying
  end

  class Cli::Replaying
    subcommand Verifying
  end

  # The flags that belong to whoever works on the game rather than to whoever
  # plays it.
  class Cli
    # The spellings kept out of the shell completions.
    #
    # `hidden: true` takes a flag out of `--help`. The completion candidates
    # are generated from the same declarations and do not read it yet, so the
    # ones named here come off the list afterwards. This goes when the shard
    # reads `hidden` in both places.
    UNLISTED = ["--debug-console", "--no-debug-console"]

    def self.completion_candidates(words : Array(String), cword : Int32,
                                   current : String, prev : String) : Array(String)
      previous_def.reject { |found| UNLISTED.includes? found }
    end
  end
end
