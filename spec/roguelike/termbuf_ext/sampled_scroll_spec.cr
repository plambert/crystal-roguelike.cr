require "../../spec_helper"

Spectator.describe TermBuf::Widgets::SampledScroll do
  alias Sampled = TermBuf::Widgets::SampledScroll

  it "plans nothing for a scroll up or nowhere" do
    expect(Sampled.frames(10, 10, 4, 6)).to be_empty
    expect(Sampled.frames(10, 3, 4, 6)).to be_empty
  end

  it "ends on the final rows, in order" do
    planned = Sampled.frames 40, 300, 4, 6

    expect(planned.last).to eq [297, 298, 299, 300]
  end

  it "inserts the final rows last, after the sampled ones" do
    inserted = Sampled.inserts 40, 300, 4, 6

    expect(inserted.last(4)).to eq [297, 298, 299, 300]
    expect(inserted.first(inserted.size - 4).all? { |row| row > 40 && row < 297 }).to be_true
  end

  it "skips rows on a long way" do
    inserted = Sampled.inserts 40, 300, 4, 6
    gaps = inserted.each_cons_pair.map { |(above, below)| below - above }

    expect(gaps.max).to be > 1
  end

  it "only ever moves down" do
    Sampled.frames(40, 300, 4, 6).each do |frame|
      expect(frame).to eq frame.sort
      expect(frame.uniq).to eq frame
    end
  end

  it "keeps at least half the rows of the frame before" do
    planned = Sampled.frames 40, 300, 4, 6
    previous = (37..40).to_a

    planned.each do |frame|
      expect((frame & previous).size).to be >= 2
      previous = frame
    end
  end

  it "takes at most the frames it is given" do
    expect(Sampled.frames(40, 300, 4, 6).size).to eq 6
  end

  it "scrolls a short way row by row" do
    planned = Sampled.frames 10, 12, 4, 6

    expect(planned).to eq [[8, 9, 10, 11], [9, 10, 11, 12]]
  end

  it "lists a taller window's rows when the window is shrinking" do
    planned = Sampled.frames 40, 300, 4, 6, window: 6

    expect(planned.first.size).to eq 6
    expect(planned.last.last(4)).to eq [297, 298, 299, 300]
  end

  it "starts from the top of a short list" do
    planned = Sampled.frames 1, 5, 4, 6

    expect(planned.first.first).to eq 0
    expect(planned.last).to eq [2, 3, 4, 5]
  end

  it "spreads a sample evenly" do
    expect(Sampled.sample(0, 10, 2)).to eq [2, 7]
    expect(Sampled.sample(5, 3, 5)).to eq [5, 6, 7]
  end
end
