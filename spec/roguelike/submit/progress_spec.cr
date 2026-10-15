require "../../spec_helper"

# An output that refuses every write.
class SpecBrokenOutput < IO
  def read(slice : Bytes) : Int32
    0
  end

  def write(slice : Bytes) : Nil
    raise IO::Error.new "closed"
  end
end

Spectator.describe Roguelike::Submit::Progress do
  alias Progress = Roguelike::Submit::Progress

  describe Progress::Counter do
    it "counts what is read and hands on every byte" do
      totals = [] of Int64
      counter = Progress::Counter.new(IO::Memory.new("a" * 20_000)) { |sent| totals << sent }

      expect(counter.gets_to_end.bytesize).to eq(20_000)
      expect(counter.count).to eq(20_000)
      expect(totals.last).to eq(20_000)
      expect(totals).to eq(totals.sort)
    end

    it "reports each read as a running total" do
      totals = [] of Int64
      counter = Progress::Counter.new(IO::Memory.new("abcdef")) { |sent| totals << sent }
      buffer = Bytes.new 4

      counter.read buffer
      counter.read buffer

      expect(totals).to eq([4_i64, 6_i64])
    end

    it "refuses a write" do
      counter = Progress::Counter.new(IO::Memory.new) { }

      expect { counter.print "x" }.to raise_error(IO::Error)
    end
  end

  describe ".line" do
    it "draws an empty, a half and a full bar" do
      expect(Progress.line("replay", 0, 2048)).to eq("replay [------------------------] 0 B of 2.0 KB")
      expect(Progress.line("replay", 1024, 2048)).to eq("replay [############------------] 1.0 KB of 2.0 KB")
      expect(Progress.line("save", 2048, 2048)).to eq("save   [########################] 2.0 KB of 2.0 KB")
    end

    it "fills the bar for an empty piece" do
      expect(Progress.line("meta", 0, 0)).to eq("meta   [########################] 0 B of 0 B")
    end

    it "keeps the bar inside its cells when more is counted than expected" do
      expect(Progress.line("meta", 300, 200)).to start_with("meta   [########################]")
    end

    it "leaves the bar out when asked" do
      expect(Progress.line("meta", 10, 200, bar: false)).to eq("meta   10 B of 200 B")
    end
  end

  describe Progress::Reporter do
    it "redraws one line in place on a terminal" do
      output = IO::Memory.new
      reporter = Progress::Reporter.new output, tty: true

      reporter.piece("replay", IO::Memory.new("x" * 100), 100_i64) do |body|
        body.read Bytes.new(50)
        body.read Bytes.new(50)
      end

      lines = output.to_s.split('\r')
      expect(lines.first).to eq("")
      expect(lines.last).to eq("replay [########################] 100 B of 100 B\n")
      expect(output.to_s.count('\n')).to eq(1)
      expect(output.to_s).to contain("replay [############------------] 50 B of 100 B")
    end

    it "writes one line per piece when it is not a terminal" do
      output = IO::Memory.new
      reporter = Progress::Reporter.new output, tty: false

      reporter.piece("replay", IO::Memory.new("x" * 100), 100_i64) { |body| body.gets_to_end }
      reporter.piece("meta", IO::Memory.new("y" * 10), 10_i64) { |body| body.gets_to_end }

      expect(output.to_s).to eq("replay 100 B of 100 B\nmeta   10 B of 10 B\n")
    end

    it "treats a plain IO as not a terminal" do
      expect(Progress::Reporter.new(IO::Memory.new).tty?).to be_false
    end

    it "gives the block's answer back and ends the line when the block raises" do
      output = IO::Memory.new
      reporter = Progress::Reporter.new output, tty: false

      expect(reporter.piece("save", IO::Memory.new("z"), 1_i64) { 7 }).to eq(7)
      expect { reporter.piece("save", IO::Memory.new("z"), 1_i64) { raise "refused" } }.to raise_error(Exception, "refused")
      expect(output.to_s.lines.size).to eq(2)
    end

    it "lets the send go on when the output fails" do
      [true, false].each do |tty|
        reporter = Progress::Reporter.new SpecBrokenOutput.new, tty: tty

        sent = reporter.piece("replay", IO::Memory.new("x" * 100), 100_i64) { |body| body.gets_to_end }

        expect(sent.bytesize).to eq(100)
      end
    end
  end
end
