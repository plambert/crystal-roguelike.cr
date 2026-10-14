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

    # A count beside an item name reads as a quantity.
    it "adds a line said anew every time, with no count" do
      2.times { log.add "You see a scroll of identify here.", anew: true }

      expect(log.lines).to eq ["You see a scroll of identify here.",
                               "You see a scroll of identify here."]
      expect(log.written).to eq 2
    end

    it "still counts an ordinary line said twice" do
      2.times { log.add "The granite blocks your way." }

      expect(log.lines).to eq ["The granite blocks your way. (x 2)"]
    end

    it "does not merge two ordinary lines with a line said anew between them" do
      log.add "The granite blocks your way."
      log.add "You see a scroll of identify here.", anew: true
      log.add "The granite blocks your way."

      expect(log.lines).to eq ["The granite blocks your way.",
                               "You see a scroll of identify here.",
                               "The granite blocks your way."]
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
