require "file_utils"

# A run recorded to a file of its own, for the replay specs.
#
# `Roguelike::Replay::Log.pattern` is a setting on the class, because
# `--replay-log` holds for every run the process plays. A spec sets it, plays
# a run and puts it back.
module Recording
  # A seed with a floor worth walking about on.
  SEED = 4271_u64

  # What the character is called in a recorded run.
  PLAYER = "tester"

  # A directory nothing else writes to. It goes when the specs are over.
  def self.directory : Path
    @@directory ||= begin
      made = Path[File.tempname "roguelike-replay", nil]
      Dir.mkdir_p made
      at_exit { FileUtils.rm_rf made.to_s }
      made
    end
  end

  @@directory : Path? = nil

  # Plays a run of *turns* actions on *seed*, recorded to *pattern*.
  #
  # The actions are drawn from `Game#legal`, so every one of them is a verb
  # the run allowed at the moment it was chosen. Climbing out is left off the
  # list: it ends the run, and a spec wants the turns it asked for.
  def self.played(pattern : String, seed : UInt64 = SEED,
                  turns : Int32 = 40, player : String = PLAYER) : Roguelike::Game
    recording pattern do
      game = Roguelike::Game.dug Roguelike::Rng.new(seed)
      game.player.name = player
      rng = Roguelike::Rng.new seed, 99_u64

      turns.times do
        break if game.over?

        wanted = game.legal.reject Roguelike::Action::Ascend
        break if wanted.empty?

        game.perform wanted.sample(rng)
      end

      game
    end
  end

  # Runs *block* with `Replay::Log.pattern` set to *pattern*.
  #
  # Every log still open is closed before the setting goes back, so the file
  # a spec is about to read has its footer.
  def self.recording(pattern : String, & : -> Roguelike::Game) : Roguelike::Game
    Roguelike::Replay::Log.pattern = pattern
    yield
  ensure
    Roguelike::Replay::Log.ended nil
    Roguelike::Replay::Log.pattern = nil
  end

  # The lines of the file at *path*, as the objects they hold.
  def self.read(path : Path | String) : Roguelike::Replay::Reading
    Roguelike::Replay::Reading.read path
  end

  # Where the replay that ships with the specs is.
  GOLDEN = Path[__DIR__].parent / "fixtures" / "replay" / "golden.jsonl"

  # The replay that ships with the specs.
  #
  # It is recorded the first time it is wanted and checked into the
  # repository. `replay verify` on it says that this build plays the run the
  # file holds the same way the build that recorded it did.
  #
  # Delete the file and run the specs to record it again. A change to the
  # generator, to a rule or to anything the character is told asks for that,
  # because every one of the three is part of the fingerprint.
  def self.golden : Path
    return GOLDEN if File.exists? GOLDEN

    Dir.mkdir_p GOLDEN.parent.to_s
    played GOLDEN.to_s, turns: 80
    GOLDEN
  end

  # Writes *lines* to a file of its own under `.directory`, and answers it.
  def self.file(lines : Array(String), name : String = "edited") : Path
    where = directory / "#{name}-#{Random.rand UInt32}.jsonl"
    File.write where, lines.join('\n') + "\n"
    where
  end
end
