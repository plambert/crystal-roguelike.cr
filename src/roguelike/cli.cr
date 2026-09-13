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

    # A development tool. It is off unless this is passed, so a normal run has
    # neither the box nor the key that opens it.
    flag debug_console : Bool = false, "--debug-console",
      "Open a console with ` for commands that change the running game"

    def run
      rng = Rng.for seed
      session = Session.open rng, flicker: flicker, generate: generate,
        console: debug_console

      exit 1 unless session

      # These lines run after the terminal is restored. The alternate screen
      # is gone by then. They stay in the scrollback.
      game = session.game
      puts case game.outcome
      in .won?     then "You escaped with your life. You win."
      in .left?    then "You climbed back out."
      in .died?    then "You died in the dungeon."
      in .playing? then "You left the dungeon where it was."
      end
      puts "seed #{rng.seed}    turn #{game.turn}"
    end
  end
end
