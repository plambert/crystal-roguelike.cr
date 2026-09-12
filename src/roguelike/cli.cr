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

    def run
      rng = Rng.for seed

      exit 1 unless Session.open rng

      # This line runs after the terminal is restored. The alternate screen is
      # gone by then. The seed stays in the scrollback.
      puts "seed #{rng.seed}"
    end
  end
end
