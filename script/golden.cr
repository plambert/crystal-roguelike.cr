# Records the replay the specs check. `script/record-golden` runs this.
#
# The run is the actions already in the file. They are read out of it,
# performed again, and written back with the fingerprints this build
# produces. A change to the generator, to a rule or to anything the character
# is told changes those fingerprints and nothing else.
#
# A file that is not there is recorded from scratch instead, from the seed
# and the length below, with the actions drawn from `Game#legal`.
require "../src/crystal-roguelike"

# Where the replay lives.
GOLDEN = Path[ARGV[0]? || "spec/fixtures/replay/golden.jsonl"]

# The seed a replay recorded from scratch is played on.
SEED = 4271_u64

# What the character is called in it.
PLAYER = "tester"

# How many actions one is played for.
TURNS = 80

# The run the file already holds, played again.
def replayed(read : Roguelike::Replay::Reading) : Roguelike::Game
  game = Roguelike::Replay::Verifier.rebuild read.header

  read.records.each do |record|
    next unless record.is_a? Roguelike::Replay::Act
    next unless game.perform(record.action).refused?

    abort "turn #{record.turn}: #{record.action.t} was refused"
  end

  game
end

# A run of `TURNS` actions on `SEED`, drawn from `Game#legal`.
#
# Climbing out is left off the list. It ends the run, and a replay wants the
# actions it asked for.
def sampled : Roguelike::Game
  game = Roguelike::Game.dug Roguelike::Rng.new(SEED)
  game.player.name = PLAYER
  rng = Roguelike::Rng.new SEED, 99_u64

  TURNS.times do
    break if game.over?

    wanted = game.legal.reject Roguelike::Action::Ascend
    break if wanted.empty?

    game.perform wanted.sample(rng)
  end

  game
end

# The actions are what is wanted here. The fingerprints beside them are the
# values being written afresh, so a file this build would refuse to check is
# still one it reads the actions out of.
read = File.exists?(GOLDEN) ? Roguelike::Replay::Reading.read(GOLDEN, fingerprints: false) : nil
wanted = Path[File.tempname "golden", ".jsonl"]

Roguelike::Replay::Log.pattern = wanted.to_s
Roguelike::Replay::Log.every = Roguelike::Replay::Log::EVERY
Roguelike::Replay::Log.generate = read ? read.header.generate? : true

read ? replayed(read) : sampled
Roguelike::Replay::Log.ended nil

Dir.mkdir_p GOLDEN.parent.to_s
File.rename wanted, GOLDEN

report = Roguelike::Replay::Verifier.check GOLDEN
abort report.to_s unless report.ok?
puts report
