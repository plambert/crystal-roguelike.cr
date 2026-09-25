require "../../spec_helper"

Spectator.describe TermBuf::Widgets::Ramp do
  alias Color = TermBuf::Color
  alias Style = TermBuf::Style

  # A mid gray, far enough from both ends to see a step either way.
  GRAY = Style::DEFAULT.fg Color.rgb(0x80, 0x80, 0x80)

  subject(ramp) { described_class.linear 5, Color.rgb(0, 0, 0) }

  it "refuses a ramp with no steps" do
    expect { described_class.new [] of Float64 }.to raise_error ArgumentError
    expect { described_class.linear 0 }.to raise_error ArgumentError
  end

  describe "the ends" do
    it "answers the style itself at the top" do
      expect(ramp[GRAY, ramp.top]).to eq GRAY
    end

    it "answers something darker at the bottom" do
      expect(ramp[GRAY, 0].foreground.red).to be < GRAY.foreground.red
    end

    # A step past either end is clamped rather than an error. A light level
    # off the end of the scale is a reading, not a mistake.
    it "clamps a step past either end" do
      expect(ramp[GRAY, 99]).to eq ramp[GRAY, ramp.top]
      expect(ramp[GRAY, -5]).to eq ramp[GRAY, 0]
    end

    it "leaves the deepest step readable" do
      expect(ramp.fraction(0)).to eq ramp.deepest
      expect(ramp[GRAY, 0].foreground).not_to eq ramp.toward
    end
  end

  describe "between the ends" do
    it "gets darker one step at a time" do
      reds = (0..ramp.top).map { |step| ramp[GRAY, step].foreground.red }

      expect(reds).to eq reds.sort
      expect(reds.uniq.size).to eq reds.size
    end

    it "moves a fixed fraction at each step" do
      expect(ramp.fraction ramp.top).to eq 0.0
      expect(ramp.fraction 2).to be_close ramp.deepest / 2, 0.001
    end
  end

  describe "what it leaves alone" do
    # A default color is whatever the terminal draws. A ramp has nothing to
    # move it toward.
    it "leaves a default foreground alone" do
      expect(ramp[Style::DEFAULT, 0]).to eq Style::DEFAULT
    end

    it "moves a background that is set" do
      style = Style::DEFAULT.bg Color.rgb(0x80, 0x80, 0x80)

      expect(ramp[style, 0].background.red).to be < 0x80
    end

    # A bold dim color reads as lit, which is what the dimming is there to
    # say it is not.
    it "drops bold below the top" do
      style = GRAY.bold

      expect(ramp[style, ramp.top].attributes.bold?).to be_true
      expect(ramp[style, 0].attributes.bold?).to be_false
    end

    it "keeps every other attribute" do
      style = GRAY.copy_with attributes: TermBuf::Attributes::Italic

      expect(ramp[style, 0].attributes.italic?).to be_true
    end
  end

  describe "a ramp of one step" do
    it "answers the style itself" do
      one = described_class.linear 1

      expect(one[GRAY, 0]).to eq GRAY
      expect(one.fraction 0).to eq 0.0
    end
  end

  # A blend computing a color per cell interns a style per cell, and a style
  # table only grows. Bounding that count is what the type is for.
  describe "how many styles it makes" do
    it "makes one per style and step, and no more" do
      3.times { (0..ramp.top).each { |step| ramp[GRAY, step] } }

      expect(ramp.size).to eq ramp.steps
    end

    it "stops growing once every step has been asked for" do
      (0..ramp.top).each { |step| ramp[GRAY, step] }
      settled = ramp.size

      1000.times { ramp[GRAY, Random.rand(ramp.steps)] }

      expect(ramp.size).to eq settled
    end

    it "takes its steps from the fractions it was given" do
      given = described_class.new [0.9, 0.4, 0.0], Color.rgb(0, 0, 0)

      expect(given.steps).to eq 3
      expect(given.top).to eq 2
      expect(given.fraction 0).to eq 0.9
      expect(given.fraction 1).to eq 0.4
      expect(given[GRAY, 2]).to eq GRAY
    end

    # This is why the fractions are given rather than worked out from two
    # ends. A square drawn from memory sits well below the dimmest lit one.
    it "lets one step sit well below the rest" do
      given = described_class.new [0.9, 0.4, 0.25, 0.0], Color.rgb(0, 0, 0)
      reds = (0..given.top).map { |step| given[GRAY, step].foreground.red }

      expect(reds[1] - reds[0]).to be > reds[2] - reds[1]
    end

    it "counts each base style apart" do
      other = Style::DEFAULT.fg Color.rgb(0x40, 0x80, 0xC0)

      ramp[GRAY, 0]
      ramp[other, 0]

      expect(ramp.size).to eq 2
    end

    it "throws away what it has made on #clear" do
      ramp[GRAY, 0]
      ramp.clear

      expect(ramp.size).to eq 0
    end
  end
end
