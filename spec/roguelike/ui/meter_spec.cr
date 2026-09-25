require "../../spec_helper"

Spectator.describe Roguelike::Ui::Meter do
  alias Meter = Roguelike::Ui::Meter
  alias Palette = Roguelike::Ui::Palette

  # A meter drawn on its own, and what came out.
  def drawn(meter : Meter, columns : Int32 = 22) : Headless::Session
    root = TermBuf::Widgets::Panel.new(
      width: TermBuf::Widgets::Layout::Sizing.grow,
      height: TermBuf::Widgets::Layout::Sizing.grow)
    root.add meter

    session = Headless.open root, columns, 1
    session.render
    session
  end

  # The background color of every cell of the row.
  def backgrounds(meter : Meter, columns : Int32 = 22) : Array(TermBuf::Color?)
    session = drawn meter, columns
    (0...columns).map do |column|
      session.buffer.hit(column, 0).try do |found|
        session.buffer.styles[found.cell.style].background
      end
    end
  end

  describe "#percent" do
    it "counts how full it is" do
      expect(Meter.new("HP", 23, 34).percent).to eq 67
      expect(Meter.new("HP", 34, 34).percent).to eq 100
      expect(Meter.new("HP", 0, 34).percent).to eq 0
    end

    # A bar with nowhere to go is empty rather than full. A full one would
    # say the opposite of what is true.
    it "is empty when it goes nowhere" do
      expect(Meter.new("MP", 0, 0).percent).to eq 0
    end

    it "does not go over full or under empty" do
      expect(Meter.new("HP", 99, 34).percent).to eq 100
      expect(Meter.new("HP", -5, 34).percent).to eq 0
    end
  end

  describe "#reading" do
    it "is the count over the most it goes to" do
      expect(Meter.new("HP", 23, 34).reading).to eq "23/34"
    end

    it "is whatever it was told to say instead" do
      meter = Meter.new "XP"
      meter.show 20, 160, "180/320"

      expect(meter.reading).to eq "180/320"
    end
  end

  describe "the fill" do
    it "walks from green to red as it empties" do
      full = Meter.new "HP", 100, 100
      half = Meter.new "HP", 50, 100
      gone = Meter.new "HP", 5, 100

      expect(full.fill).to eq Palette::GREEN
      expect(gone.fill).to eq Palette::RED
      expect(half.fill).not_to eq Palette::GREEN
      expect(half.fill).not_to eq Palette::RED
    end

    it "is exactly the named color at each level" do
      {100 => Palette::GREEN, 80 => Palette::LIGHT_GREEN,
       60 => Palette::YELLOW, 40 => Palette::ORANGE,
       20 => Palette::RED}.each do |percent, color|
        expect(Meter.new("HP", percent, 100).fill).to eq color
      end
    end

    it "shades between two levels rather than stepping" do
      steps = (0..100).map { |percent| Meter.new("HP", percent, 100).fill }

      expect(steps.uniq.size).to be > 20
    end

    # Running out of magic does not end a run, so the bar never goes red.
    it "never goes red on the magic levels" do
      (0..100).each do |percent|
        meter = Meter.new "MP", percent, 100, Palette::MAGIC

        expect(meter.fill).not_to eq Palette::RED
      end
    end

    it "stays one color on the experience levels" do
      steps = (0..100).map do |percent|
        Meter.new("XP", percent, 100, Palette::LEARNING).fill
      end

      expect(steps.uniq).to eq [Palette::LIGHT_GREEN]
    end
  end

  describe "#draw" do
    it "writes the label outside the bar" do
      expect(drawn(Meter.new "HP", 23, 34).text).to start_with "HP"
    end

    it "writes the count inside the bar" do
      expect(drawn(Meter.new "HP", 23, 34).text).to contain "23/34"
    end

    it "fills as many cells as it is full" do
      found = backgrounds Meter.new("HP", 50, 100)
      bar = found[Meter::LABEL..]

      expect(bar.count &.==(Palette::EMPTY)).to eq bar.size // 2
    end

    it "fills every cell when it is full" do
      found = backgrounds Meter.new("HP", 100, 100)

      expect(found[Meter::LABEL..].includes? Palette::EMPTY).to be_false
    end

    it "fills no cell when it is empty" do
      found = backgrounds Meter.new("HP", 0, 100)

      expect(found[Meter::LABEL..].uniq).to eq [Palette::EMPTY]
    end

    # The count crosses the boundary between the two halves of the bar, so
    # the cells on each side take a foreground that reads on that side.
    it "draws the count over both halves of the bar" do
      session = drawn Meter.new("HP", 50, 100)
      row = session.text

      expect(row).to contain "50/100"
    end
  end
end
