require "shell-auto_complete"

module Roguelike
  # The command line.
  #
  # `--version` is not declared here: the shard finds `Roguelike::VERSION` in
  # the enclosing namespace and answers with it, and that constant is read out
  # of `shard.yml` at build time.
  Shell::AutoComplete.command Cli,
    name: "crystal-roguelike",
    description: "A terminal roguelike" do
    flag seed : UInt64?, "--seed",
      "Start from this seed, which reproduces a run exactly"

    # Nothing reads this yet. It is declared now because monster planning is
    # meant to run in a `Fiber::ExecutionContext::Parallel` sized by it, and a
    # flag that appears later is a flag somebody's shell alias has to learn.
    flag threads : Int32 = 1, "--threads",
      "Threads for monster planning (not used yet)", range: 1..64

    def run
      rng = Rng.for seed

      puts "seed #{rng.seed}"
      STDERR.puts "no game yet: the terminal arrives in phase 1"
    end
  end
end
