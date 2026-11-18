require "../../spec_helper"

Spectator.describe "the food and water lines" do
  alias Sustenance = Roguelike::Sustenance

  # A run on one open room with the counters set, drawn at *columns*.
  def fed(hunger : Int32 = 0, thirst : Int32 = 0, water : Int32 = Sustenance::WATER_MAX,
          columns : Int32 = 80) : Playing::Run
    game = Playing.field 30, 16
    sustenance = game.player.sustenance
    sustenance.hunger = hunger
    sustenance.thirst = thirst
    sustenance.water = water
    Playing.open game, columns, 40
  end

  # Row *y* of the screen, cut at the right edge of the info panel.
  def info_row(run : Playing::Run, y : Int32) : String
    box = run.screen.info.rect
    run.row(y).ljust(box.right)[box.x, box.width]
  end

  def food_row(run : Playing::Run) : String
    info_row(run, run.play.character.food.rect.y).strip
  end

  def water_row(run : Playing::Run) : String
    info_row(run, run.play.character.water.rect.y).strip
  end

  it "puts the food line above the water line" do
    run = fed
    expect(run.play.character.food.rect.y).to eq run.play.character.water.rect.y - 1
  end

  it "shows a fed character's time to hungry and a full skin's time" do
    run = fed

    expect(food_row run).to match /^food +4h10m$/
    expect(water_row run).to match /^water 10\/10 +9h40m$/
  end

  it "names the hunger stage and counts to the next one" do
    run = fed hunger: 2_000, water: 7

    expect(food_row run).to match /^hungry +2h40m$/
    expect(water_row run).to match /^water 7\/10 +7h10m$/
  end

  it "counts a starving character to death" do
    run = fed hunger: 6_000

    expect(food_row run).to match /^starving +8h20m$/
  end

  it "names the thirst stage and leaves the skin's units on the line" do
    run = fed thirst: 600, water: 3

    expect(water_row run).to match /^thirsty 3\/10 +3h50m$/
  end

  it "counts a character dying of thirst to death and fits the narrow panel" do
    run = fed hunger: 8_990, thirst: 5_500, water: 0

    expect(food_row run).to match /^starving +<10m$/
    expect(water_row run).to match /^dying 0\/10 +1h20m$/
  end

  it "keeps the longest stage word inside the narrow panel" do
    run = fed thirst: Sustenance::DEHYDRATED, water: 10

    expect(water_row run).to match /^dehydrated 10\/10 +4h10m$/
  end

  it "draws a stage word in the style of its pill" do
    run = fed hunger: 2_000
    span = run.play.character.food.spans.find! &.column.==(0)

    expect(span.style).to eq Roguelike::Ui::Palette.pill(Roguelike::Event::Status::Hungry)
  end
end
