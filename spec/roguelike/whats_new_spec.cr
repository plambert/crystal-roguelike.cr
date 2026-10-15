require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::WhatsNew do
  alias WhatsNew = Roguelike::WhatsNew

  NEWS_TEXT = <<-NEWS
    # News

    Preamble that is not a release.

    ## [0.3.0] - 2026-10-10

    The lead sentence, which runs
    over two lines.

    ### New

    * A bullet that is long enough to need `wrapping` when the width is small.
    * A short one.

    ## [0.2.0] - 2026-10-01

    An older lead.

    * Old bullet.
    NEWS

  # A directory nothing else writes to.
  def root : Path
    made = Recording.directory / "whats-new-#{Random.rand UInt32}"
    Dir.mkdir_p made
    made
  end

  describe ".sections" do
    it "reads each release, newest first, and skips the preamble" do
      found = WhatsNew.sections NEWS_TEXT

      expect(found.map &.version).to eq %w[0.3.0 0.2.0]
      expect(found.first.date).to eq "2026-10-10"
      kinds = found.first.blocks.reject(&.text.empty?).map(&.kind)
      expect(kinds).to eq [
        WhatsNew::Kind::Paragraph, WhatsNew::Kind::Heading,
        WhatsNew::Kind::Bullet, WhatsNew::Kind::Bullet,
      ]
    end

    it "joins a paragraph that runs over two lines and drops backticks" do
      blocks = WhatsNew.sections(NEWS_TEXT).first.blocks

      expect(blocks.first.text).to eq "The lead sentence, which runs over two lines."
      expect(blocks.map(&.text)).to contain "A bullet that is long enough to need wrapping when the width is small."
    end

    it "reads the shipped NEWS.md" do
      expect(WhatsNew.sections.first.version).to eq Roguelike::VERSION
    end
  end

  describe ".since" do
    let(found) { WhatsNew.sections NEWS_TEXT }

    it "gives every section newer than the last run" do
      expect(WhatsNew.since("0.1.0", found).map &.version).to eq %w[0.3.0 0.2.0]
      expect(WhatsNew.since("0.2.0", found).map &.version).to eq %w[0.3.0]
    end

    it "gives the newest section when nothing is newer or nothing is known" do
      expect(WhatsNew.since("0.3.0", found).map &.version).to eq %w[0.3.0]
      expect(WhatsNew.since("9.9.9", found).map &.version).to eq %w[0.3.0]
      expect(WhatsNew.since(nil, found).map &.version).to eq %w[0.3.0]
    end
  end

  describe ".text" do
    it "wraps at the width and hangs a bullet's second line" do
      text = WhatsNew.text WhatsNew.sections(NEWS_TEXT).first(1), 30

      expect(text.lines.map(&.chomp).first).to eq "0.3.0 - 2026-10-10"
      expect(text.lines.all? { |line| line.chomp.size <= 30 }).to be_true
      expect(text).to contain "* A bullet that is long enough\n  to need wrapping when the\n  width is small.\n"
    end
  end

  describe ".arrive" do
    it "records the version, and shows what is newer than the one before" do
      where = WhatsNew::LastRun.new root
      where.record "0.2.0"

      shown = WhatsNew.arrive where, current: "0.3.0"
      expect(where.version).to eq "0.3.0"
      expect(shown).not_to be_empty
    end

    it "writes nothing when told not to" do
      where = WhatsNew::LastRun.new root
      WhatsNew.arrive where, record: false, current: "0.3.0"

      expect(where.version).to be_nil
      expect(File.exists? where.path).to be_false
    end
  end
end
