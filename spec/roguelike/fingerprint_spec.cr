require "../spec_helper"
require "../support/scripted"

# The second process the cross-process specs read fingerprints from.
#
# A fingerprint has to be the same in two processes. No spec running in one
# process can show that. A fork will not do either. Crystal
# seeds `Object#hash` once at startup, and a child inherits the seed its
# parent was given, so anything built from it would agree for the wrong
# reason.
module SecondProcess
  @@built : Path? = nil

  # The project's own directory, which is where the compiler is run from so
  # that it finds `lib`.
  ROOT = Path[__DIR__].parent.parent

  # Where the built program is.
  #
  # It is built the first time it is wanted and kept for the rest of the
  # spec run. The compile takes a few seconds, and every spec here would
  # otherwise wait for it again.
  def self.binary : Path
    @@built ||= build
  end

  private def self.build : Path
    source = ROOT / "spec" / "support" / "fingerprints.cr"
    wanted = Path[File.tempname "roguelike-fingerprints", nil]

    said = IO::Memory.new
    status = Process.run "crystal",
      ["build", "--no-debug", "-o", wanted.to_s, source.to_s],
      output: said, error: said, chdir: ROOT.to_s
    raise "building #{source} failed:\n#{said}" unless status.success?

    at_exit { File.delete? wanted }
    wanted
  end

  # What the program printed when it was run with *arguments*.
  def self.fingerprints(*arguments : String) : Array(String)
    said = IO::Memory.new
    trouble = IO::Memory.new
    status = Process.run binary.to_s, arguments.to_a,
      output: said, error: trouble, chdir: ROOT.to_s
    raise "#{binary} #{arguments.join ' '} failed:\n#{trouble}" unless status.success?

    said.to_s.lines
  end
end

Spectator.describe Roguelike::Fingerprint do
  alias Game = Roguelike::Game
  alias Rng = Roguelike::Rng

  # A seed with a floor worth walking about on.
  SEED = 4271_u64

  describe "the value" do
    it "says which algorithm made it" do
      expect(Game.dug(Rng.new(SEED)).fingerprint)
        .to match /\Asha256:[0-9a-f]{64}\z/
    end

    it "is the digest of the canonical form" do
      game = Game.dug Rng.new(SEED)

      expect(game.fingerprint)
        .to eq described_class.digest(described_class.canonical(game))
    end
  end

  describe "the canonical form" do
    it "puts the fields of an object in order by name" do
      expect(described_class.canonical %({"b":1,"a":{"z":2,"y":3}}))
        .to eq %({"a":{"y":3,"z":2},"b":1})
    end

    it "leaves the order of an array alone" do
      expect(described_class.canonical %([3,1,2])).to eq "[3,1,2]"
    end

    it "keeps a number too large for Int64" do
      expect(described_class.canonical %({"seed":18446744073709551615}))
        .to eq %({"seed":18446744073709551615})
    end

    it "answers the same string for two hashes filled in different orders" do
      kinds = [Roguelike::ItemKind::HealingPotion, Roguelike::ItemKind::HastePotion]
      looks = ["bubbling", "cloudy"]

      one = Roguelike::Lore.new
      other = Roguelike::Lore.new
      kinds.each_with_index { |kind, index| one.appearances[kind] = looks[index] }
      kinds.reverse.each_with_index { |kind, index| other.appearances[kind] = looks[1 - index] }

      expect(one.appearances.to_a).not_to eq other.appearances.to_a
      expect(described_class.of one).to eq described_class.of(other)
    end
  end

  describe "a run played twice in one process" do
    it "answers the same fingerprint at every turn of a list of moves" do
      expect(Scripted.walked SEED).to eq Scripted.walked(SEED)
    end

    it "answers the same fingerprint at every turn of a bot's run" do
      expect(Scripted.played SEED).to eq Scripted.played(SEED)
    end

    it "takes a fingerprint before the first move and after each one" do
      walked = Scripted.walked SEED

      expect(walked.size).to eq Scripted::MOVES.size + 1
      expect(walked.first).not_to eq walked.last
    end
  end

  describe "a run played in another process" do
    it "answers the same fingerprint at every turn of a list of moves" do
      expect(SecondProcess.fingerprints "walk", SEED.to_s, Scripted::MOVES)
        .to eq Scripted.walked(SEED)
    end

    it "answers the same fingerprint at every turn of a bot's run" do
      expect(SecondProcess.fingerprints "play", SEED.to_s, Scripted::TURNS.to_s)
        .to eq Scripted.played(SEED)
    end
  end

  describe "a state that differs" do
    it "answers a different fingerprint for a different seed" do
      expect(Game.dug(Rng.new(SEED)).fingerprint)
        .not_to eq Game.dug(Rng.new(SEED + 1)).fingerprint
    end

    it "answers a different fingerprint after one more turn" do
      game = Game.dug Rng.new(SEED)
      before = game.fingerprint

      game.wait

      expect(game.fingerprint).not_to eq before
    end

    it "answers a different fingerprint when a number in the run changes" do
      game = Game.dug Rng.new(SEED)
      before = game.fingerprint

      game.player.hurt 1

      expect(game.fingerprint).not_to eq before
    end
  end

  describe "drawing" do
    # A game drawn in a window, with its flames held still or wavering.
    def drawn(flicker : Bool) : Playing::Run
      run = Playing.open Game.start(Rng.new(Playing::SEED))
      run.play.flicker.burning = flicker
      run
    end

    it "does not change the fingerprint" do
      run = drawn true
      before = run.game.fingerprint

      run.render
      run.hover 10, 5
      run.resize 100, 30

      expect(run.game.fingerprint).to eq before
    end

    it "gives the same fingerprints with the flames wavering as without" do
      wavering = drawn true
      still = drawn false
      moves = %w[l . j . k .]

      found = moves.map do |move|
        wavering.press move
        wavering.play.waver
        wavering.render

        still.press move
        still.render

        {wavering.game.fingerprint, still.game.fingerprint}
      end

      found.each { |both| expect(both[0]).to eq both[1] }
      expect(found.first[0]).not_to eq found.last[0]
    end
  end
end
