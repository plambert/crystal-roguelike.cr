require "compress/gzip"
require "../spec_helper"
require "../support/recording"

# A log packed the way a sent record is kept reads as the file it was.
Spectator.describe "a gzipped replay log" do
  alias Reading = Roguelike::Replay::Reading

  it "reads the same as the file it was packed from" do
    directory = Recording.directory / "gzip-#{Random.rand UInt32}"
    Dir.mkdir_p directory
    Recording.played directory.to_s, turns: 6

    plain = directory / Dir.children(directory).first
    packed = Path["#{plain}.gz"]
    File.open packed, "w" do |output|
      Compress::Gzip::Writer.open(output) { |gzip| File.open(plain) { |input| IO.copy input, gzip } }
    end

    from_plain = Reading.read plain
    from_packed = Reading.read packed

    expect(from_packed.header.seed).to eq(from_plain.header.seed)
    expect(from_packed.records.size).to eq(from_plain.records.size)
    expect(from_packed.footer.try(&.turn)).to eq(from_plain.footer.try(&.turn))
    expect(from_packed.path).to eq(packed)
  end
end
