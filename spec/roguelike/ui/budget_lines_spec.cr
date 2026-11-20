require "../../spec_helper"

Spectator.describe "the food and water lines" do
  alias Sustenance = Roguelike::Sustenance

  # A run on one open room with the counters set, drawn at *columns*.
  def fed(hunger : Int32 = 0, thirst : Int32 = 0, water : Int32 = Sustenance::Tuning::SKIN_UNITS,
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

  it "shows the time to each first effect and the skin out of 20" do
    run = fed

    expect(food_row run).to match /^food +6h$/
    expect(water_row run).to match /^water 20\/20 +7h$/
  end

  it "names the hunger stage and counts to the next one" do
    run = fed hunger: 6_000, water: 7

    expect(food_row run).to match /^hungry +7h20m$/
    expect(water_row run).to match /^water 7\/20 +7h$/
  end

  it "counts to the next stage in whole hours from ten hours up" do
    run = fed hunger: 3_000

    expect(food_row run).to match /^food +3h40m$/
    expect(food_row fed(hunger: Sustenance::Tuning::HUNGER_SERIOUS)).to match /^famished +36h$/
  end

  it "counts a starving character to death" do
    run = fed hunger: Sustenance::Tuning::HUNGER_DEATH - 3_600

    expect(food_row run).to match /^starving +10h$/
  end

  it "names the thirst stage and leaves the skin's units on the line" do
    run = fed thirst: 7_000, water: 3

    expect(water_row run).to match /^thirsty 3\/20 +4h30m$/
  end

  it "counts a character dying of thirst to death and fits the narrow panel" do
    run = fed hunger: Sustenance::Tuning::HUNGER_DEATH - 10, thirst: Sustenance::Tuning::THIRST_DEATH - 500,
      water: 0

    expect(food_row run).to match /^starving +<10m$/
    expect(water_row run).to match /^dying 0\/20 +1h20m$/
  end

  it "keeps the longest stage word and a full skin inside the narrow panel" do
    run = fed thirst: Sustenance::Tuning::THIRST_SEVERE, water: 20

    expect(water_row run).to match /^dehydrated 20\/20 +20h$/
  end

  it "draws a stage word in the style of its pill" do
    run = fed hunger: 6_000
    span = run.play.character.food.spans.find! &.column.==(0)

    expect(span.style).to eq Roguelike::Ui::Palette.pill(Roguelike::Event::Status::Hungry)
  end
end
