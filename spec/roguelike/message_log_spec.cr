require "../spec_helper"

Spectator.describe Roguelike::MessageLog do
  subject(log) { described_class.new }

  describe "#add" do
    it "keeps messages oldest first" do
      log.add "first"
      log.add "second"

      expect(log.lines).to eq ["first", "second"]
    end

    it "answers the most recent one" do
      log.add "first"
      log.add "second"

      expect(log.last?).to eq "second"
    end

    # A wall bumped ten times reads better as one line than as ten.
    it "does not repeat the message it just added" do
      3.times { log.add "The granite blocks your way." }

      expect(log.size).to eq 1
    end

    it "counts a repeat on the line it repeats" do
      log.add "You organize your pack more efficiently."
      expect(log.last?).to eq "You organize your pack more efficiently."

      log.add "You organize your pack more efficiently."
      expect(log.last?).to eq "You organize your pack more efficiently. (x 2)"

      3.times { log.add "You organize your pack more efficiently." }
      expect(log.lines).to eq ["You organize your pack more efficiently. (x 5)"]
      expect(log.said?).to eq "You organize your pack more efficiently."
    end

    it "counts only the lines it added in #written" do
      log.add "blocked"
      log.add "blocked"
      log.add "moved"

      expect(log.written).to eq 2
    end

    it "moves a repeat into the round being written" do
      log.add "blocked"
      log.next_round
      log.next_round
      log.add "blocked"

      expect(log.round_of 0).to eq 2
    end

    it "starts a new count after another line" do
      log.add "blocked"
      log.add "blocked"
      log.add "moved"
      log.add "blocked"

      expect(log.lines).to eq ["blocked (x 2)", "moved", "blocked"]
    end

    it "adds a repeat that is not the last message" do
      log.add "blocked"
      log.add "moved"
      log.add "blocked"

      expect(log.lines).to eq ["blocked", "moved", "blocked"]
    end

    it "ignores an empty message" do
      log.add ""

      expect(log).to be_empty
    end

    it "drops the oldest once it is full" do
      (Roguelike::MessageLog::LIMIT + 10).times { |number| log.add "line #{number}" }

      expect(log.size).to eq Roguelike::MessageLog::LIMIT
      expect(log.lines.first).to eq "line 10"
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      log.add "first"
      log.add "second"

      expect(described_class.from_json(log.to_json).lines).to eq log.lines
    end
  end
end
