require "../../spec_helper"

Spectator.describe "the box beside a pick-up list" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias Options = Roguelike::Options
  alias Scheme = Roguelike::Options::ControlScheme

  HALL = [
    "############",
    "#..........#",
    "#..........#",
    "############",
  ]

  after_each { Options.current = nil }

  # A lit hall with the character standing on a pile of *count* things.
  def pile(scheme : Scheme, count : Int32 = 3) : Playing::Run
    options = Options.new
    options.control_scheme = scheme
    Options.current = options

    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)
    [Kind::Dagger, Kind::HealingPotion, Kind::Torch].first(count).each do |kind|
      floor.drop 2, 1, Item.new(kind)
    end
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {floor.id => floor}),
      Roguelike::Player.new(floor.id, 2, 1)

    run = Playing.open game, 80, 44
    run.render
    run
  end

  # Opens the pick-up list and points at its second row until the box is up.
  # Answers the cell pointed at.
  def hover_second_row(run : Playing::Run, scheme : Scheme) : {Int32, Int32}
    run.press scheme.modern? ? "g" : ","
    list = run.menu.list.rect
    spot = {list.x + 2, list.y + 1}
    run.hover *spot
    spot
  end

  # Whether the box is up and drawn.
  def box_up?(run : Playing::Run) : Bool
    run.play.tooltip.showing? || run.text.includes?("weight ")
  end

  it "is up while a row of the list is pointed at" do
    run = pile Scheme::Traditional
    hover_second_row run, Scheme::Traditional

    expect(run.play.tooltip.written.first).to contain "potion"
    expect(box_up? run).to be_true
  end

  it "goes when a row is picked by its letter in the traditional scheme" do
    run = pile Scheme::Traditional
    hover_second_row run, Scheme::Traditional

    run.press "b"

    expect(run.game.here.size).to eq 2
    expect(box_up? run).to be_false
  end

  it "goes when a row is picked by its key in the modern scheme" do
    run = pile Scheme::Modern
    hover_second_row run, Scheme::Modern

    run.press "f"

    expect(run.game.here.size).to eq 2
    expect(box_up? run).to be_false
  end

  it "goes when a row is clicked in the traditional scheme" do
    run = pile Scheme::Traditional
    spot = hover_second_row run, Scheme::Traditional

    run.click *spot

    expect(run.game.here.size).to eq 2
    expect(box_up? run).to be_false
  end

  it "goes when a row is clicked in the modern scheme" do
    run = pile Scheme::Modern
    spot = hover_second_row run, Scheme::Modern

    run.click *spot

    expect(run.game.here.size).to eq 2
    expect(box_up? run).to be_false
  end

  it "goes when taking a row leaves one thing, in the traditional scheme" do
    run = pile Scheme::Traditional, 2
    hover_second_row run, Scheme::Traditional

    run.press "b"

    expect(run.game.here.size).to eq 1
    expect(box_up? run).to be_false
  end

  it "goes when taking a row leaves one thing, in the modern scheme" do
    run = pile Scheme::Modern, 2
    hover_second_row run, Scheme::Modern

    run.press "f"

    expect(run.game.here.size).to eq 1
    expect(box_up? run).to be_false
  end

  it "goes on Escape in the traditional scheme" do
    run = pile Scheme::Traditional
    hover_second_row run, Scheme::Traditional

    run.press "Escape"

    expect(run.menu.showing?).to be_false
    expect(box_up? run).to be_false
  end

  it "goes on Escape in the modern scheme" do
    run = pile Scheme::Modern
    hover_second_row run, Scheme::Modern

    run.press "Escape"

    expect(run.menu.showing?).to be_false
    expect(box_up? run).to be_false
  end

  # Nothing that closes the menu has to know about the box. Closing it
  # directly runs no hook of Play's at all.
  it "goes in the same frame when the menu is closed by anything else" do
    run = pile Scheme::Modern
    hover_second_row run, Scheme::Modern

    run.menu.close
    run.render

    expect(box_up? run).to be_false
  end

  it "stays down when a pointer report for the old row comes after the pick" do
    run = pile Scheme::Traditional
    spot = hover_second_row run, Scheme::Traditional

    run.press "b"
    run.hover *spot

    expect(box_up? run).to be_false
  end

  it "stays down when a pointer report for the old row comes after the pick, modern" do
    run = pile Scheme::Modern
    spot = hover_second_row run, Scheme::Modern

    run.press "f"
    run.hover *spot

    expect(box_up? run).to be_false
  end

  describe "beside a Here row" do
    # Points at the Here row about the dagger and answers the cell.
    def hover_dagger_row(run : Playing::Run) : {Int32, Int32}
      row = run.nearby.here.children.compact_map(&.as?(Roguelike::Ui::Line))
        .find(&.text.includes?("dagger")) || raise "No dagger row"
      spot = {row.rect.x + 1, row.rect.y}
      run.hover *spot
      spot
    end

    # Whether a box about the dagger is up or drawn.
    def dagger_box?(run : Playing::Run) : Bool
      tooltip = run.play.tooltip
      (tooltip.showing? && tooltip.written.first? == "a dagger") ||
        run.text.includes?("damage 1d4")
    end

    it "is up while the row is pointed at" do
      run = pile Scheme::Traditional, 1
      hover_dagger_row run

      expect(dagger_box? run).to be_true
    end

    it "goes when the one thing there is picked up, in the traditional scheme" do
      run = pile Scheme::Traditional, 1
      hover_dagger_row run

      run.press ","

      expect(run.game.here).to be_empty
      expect(dagger_box? run).to be_false
    end

    it "goes when the one thing there is picked up, in the modern scheme" do
      run = pile Scheme::Modern, 1
      hover_dagger_row run

      run.press "g"

      expect(run.game.here).to be_empty
      expect(dagger_box? run).to be_false
    end

    it "goes when its thing is picked from a pile of two, in the traditional scheme" do
      run = pile Scheme::Traditional, 2
      hover_dagger_row run

      run.press ",", "a"

      expect(run.game.here.map &.kind).to eq [Kind::HealingPotion]
      expect(dagger_box? run).to be_false
    end

    it "goes when its thing is picked from a pile of two, in the modern scheme" do
      run = pile Scheme::Modern, 2
      hover_dagger_row run

      run.press "g", "f"

      expect(run.game.here.map &.kind).to eq [Kind::HealingPotion]
      expect(dagger_box? run).to be_false
    end
  end
end
