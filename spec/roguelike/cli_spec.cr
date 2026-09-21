require "../spec_helper"

Spectator.describe Roguelike::Cli do
  describe "--version" do
    it "reports the version out of shard.yml" do
      expect(described_class.version_string).to eq Roguelike::VERSION
    end

    it "reports the program name" do
      expect(described_class.version_name).to eq "crystal-roguelike"
    end
  end

  # A development tool. It works, and it is in neither the help nor the
  # completions: whoever plays the game has no use for it.
  describe "--debug-console" do
    it "is off unless it is passed" do
      expect(described_class.parse(%w[]).debug_console).to be_false
    end

    it "is on when it is passed" do
      expect(described_class.parse(%w[--debug-console]).debug_console).to be_true
    end

    it "is not in the help" do
      expect(described_class.help).not_to contain "--debug-console"
    end

    it "is not offered as a completion" do
      offered = described_class.completion_candidates(
        ["crystal-roguelike", "--"], 1, "--", "crystal-roguelike")

      expect(offered).not_to contain "--debug-console"
      expect(offered).not_to contain "--no-debug-console"
    end

    it "offers the flags that are not hidden" do
      offered = described_class.completion_candidates(
        ["crystal-roguelike", "--"], 1, "--", "crystal-roguelike")

      expect(offered).to contain "--seed"
    end
  end

  describe "--seed" do
    it "is nil when nobody asked for one" do
      expect(described_class.parse(%w[]).seed).to be_nil
    end

    it "takes the seed given" do
      expect(described_class.parse(%w[--seed 20260911]).seed).to eq 20260911_u64
    end

    it "refuses something that is not a number" do
      expect { described_class.parse(%w[--seed banana]) }
        .to raise_error Shell::AutoComplete::ParseError
    end
  end

  describe "--threads" do
    it "defaults to one" do
      expect(described_class.parse(%w[]).threads).to eq 1
    end

    it "takes a count" do
      expect(described_class.parse(%w[--threads 8]).threads).to eq 8
    end

    it "refuses a count outside the range" do
      expect { described_class.parse(%w[--threads 0]) }
        .to raise_error Shell::AutoComplete::ParseError
      expect { described_class.parse(%w[--threads 65]) }
        .to raise_error Shell::AutoComplete::ParseError
    end
  end

  describe "--help" do
    it "names every flag" do
      help = described_class.help

      expect(help).to contain "--seed"
      expect(help).to contain "--threads"
      expect(help).to contain "A terminal roguelike"
    end
  end

  describe "--shell-completion" do
    it "generates a script for each shell" do
      {:bash, :zsh, :fish}.each do |shell|
        expect(described_class.completion_script(shell)).to contain "crystal-roguelike"
      end
    end
  end
end
