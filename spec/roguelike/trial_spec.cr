require "../spec_helper"

Spectator.describe Roguelike::Trial do
  alias Outcome = Roguelike::Outcome
  alias Trial = Roguelike::Trial

  # How many runs the examples here play, and how long each is given.
  #
  # Small. This is a spec about the harness rather than a measurement, and a
  # measurement belongs on the command line where somebody is waiting for it.
  RUNS  =  4
  TURNS = 25

  # The report every example about one reads.
  #
  # Playing is most of the work, so it is played once and shared. Nothing
  # here writes to it.
  REPORT = Trial.play RUNS, Trial::FIRST, TURNS

  describe ".play" do
    it "plays the runs it was asked for" do
      expect(REPORT.runs).to eq RUNS
      expect(REPORT.played.size).to eq RUNS
    end

    it "plays a different seed for each" do
      expect(REPORT.played.map(&.seed).uniq!.size).to eq RUNS
    end

    it "gives up at the turn it was told to" do
      expect(REPORT.played.all? { |run| run.turns <= TURNS }).to be_true
    end

    it "names what killed the character on every death" do
      expect(REPORT.deaths.all? &.killer).to be_true
    end

    it "names nothing on a run that did not end in a death" do
      alive = REPORT.played.reject &.outcome.died?

      expect(alive.all? &.killer.nil?).to be_true
    end

    # The harness is for comparing one build against another, so the same
    # seeds have to give the same numbers.
    it "plays the same runs twice from the same seeds" do
      again = Trial.play RUNS, Trial::FIRST, TURNS

      expect(again.played).to eq REPORT.played
    end

    it "plays different runs from different seeds" do
      other = Trial.play RUNS, Trial::FIRST + 500, TURNS

      expect(other.played).not_to eq REPORT.played
    end

    # The bot walks. A run that took no step at all would mean the harness
    # measures nothing.
    it "walks the character about" do
      expect(REPORT.played.any? { |run| run.reached > 3 }).to be_true
      expect(REPORT.played.all? { |run| run.turns > 0 }).to be_true
    end
  end

  describe Roguelike::Trial::Report do
    it "counts the deaths" do
      expect(REPORT.deaths.size).to eq REPORT.played.count &.outcome.died?
    end

    it "says how many out of a hundred died" do
      expect(REPORT.death_rate).to eq 100.0 * REPORT.deaths.size / RUNS
    end

    it "says nothing died when nothing was played" do
      expect(Trial::Report.new([] of Trial::Played).death_rate).to eq 0.0
    end

    it "counts what killed the character, most often first" do
      counted = REPORT.killers

      expect(counted.sum { |_name, many| many }).to eq REPORT.deaths.size
      expect(counted).to eq counted.sort_by { |pair| -pair[1] }
    end

    it "writes a row for every line of the report" do
      written = REPORT.to_s

      expect(written).to contain "#{RUNS} runs"
      expect(written).to contain "died"
      expect(written).to contain "won"
      expect(written).to contain "gave up"
      expect(written).to contain "killed by"
    end

    it "writes a report for no runs at all" do
      expect(Trial::Report.new([] of Trial::Played).to_s).to contain "0 runs"
    end
  end

  describe Roguelike::Trial::Bot do
    it "starts where the character arrived" do
      bot = Trial::Bot.new Trial::FIRST

      expect(bot.start).to eq bot.game.player.at
      expect(bot.reached).to eq 0
    end

    it "takes a turn each time it is asked" do
      bot = Trial::Bot.new Trial::FIRST
      before = bot.game.turn

      10.times { bot.turn }

      expect(bot.game.turn).to be > before
    end

    it "does nothing once the run is over" do
      bot = Trial::Bot.new Trial::FIRST
      bot.game.ascend
      before = bot.game.turn

      10.times { bot.turn }

      expect(bot.game.turn).to eq before
    end
  end
end
