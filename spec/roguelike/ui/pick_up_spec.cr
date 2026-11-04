require "../../spec_helper"

Spectator.describe "the pick-up menu and corpses" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::Kind
  alias Options = Roguelike::Options
  alias Sustenance = Roguelike::Sustenance

  HALL = [
    "############",
    "#<.........#",
    "#..........#",
    "############",
  ]

  after_each { Options.current = nil }

  # A game in a lit hall with the corpse of a *kind* underfoot and a
  # character *hunger* turns from their last meal.
  def over_corpse(kind : Kind, hunger : Int32 = 2000) : Roguelike::Game
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)
    player = Roguelike::Player.new floor.id, 1, 1
    player.sustenance.hunger = hunger
    game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {floor.id => floor}), player
    game.floor.drop 1, 1, Roguelike::Game.remains_of(kind).first
    game.enroll
    game
  end

  def traditional(game : Roguelike::Game) : Playing::Run
    Options.current = Options.new
    Playing.open game
  end

  def modern(game : Roguelike::Game) : Playing::Run
    options = Options.new
    options.control_scheme = Options::ControlScheme::Modern
    Options.current = options
    Playing.open game
  end

  describe "in the traditional scheme" do
    it "shows a humanoid corpse as a dimmed row that says when it can be eaten" do
      run = traditional over_corpse(Kind::Orc)
      run.press ","

      expect(run.menu.showing?).to be_true
      expect(run.menu.title.to_s).to eq "Pick up what?"
      row = run.menu.entries.first
      expect(row.text).to end_with "orc corpse (eat when starving)"
      expect(row.enabled).to be_false

      run.press "a"
      expect(run.game.here.size).to eq 1
      expect(run.turn).to eq 0
    end

    it "eats a humanoid corpse from its row while starving" do
      run = traditional over_corpse(Kind::Orc, Sustenance::STARVING)
      run.press ","

      row = run.menu.entries.first
      expect(row.text).to end_with "orc corpse - eat some (starving!)"
      expect(row.enabled).to be_true

      run.press "a"
      expect(run.game.events.any?(Roguelike::Event::Ate)).to be_true
      expect(run.turn).to eq 1
    end

    it "still cuts a lone fresh beast corpse without a menu" do
      run = traditional over_corpse(Kind::Wolf)
      run.press ","

      expect(run.menu.showing?).to be_false
      expect(run.game.player.food_bag.items.map &.kind).to eq [Roguelike::ItemKind::FreshMeat]
    end

    it "offers to cut or eat a fresh beast corpse while starving" do
      run = traditional over_corpse(Kind::Wolf, Sustenance::STARVING)
      run.press ","

      texts = run.menu.entries.map &.text
      expect(texts.size).to eq 2
      expect(texts[0]).to end_with "wolf corpse"
      expect(texts[1]).to end_with "wolf corpse - eat some (starving!)"

      run.press "b"
      expect(run.game.events.any?(Roguelike::Event::Ate)).to be_true
      expect(run.game.player.food_bag.empty?).to be_true
    end

    it "draws a dimmed row in the dimmed menu color" do
      run = traditional over_corpse(Kind::Orc)
      run.press ","

      expect(run.menu.disabled_style).to eq Roguelike::Ui::Palette.dimmed
    end
  end

  describe "in the modern scheme" do
    it "shows a humanoid corpse as a dimmed target" do
      run = modern over_corpse(Kind::Orc)
      run.press "g"

      expect(run.menu.title.to_s).to contain "choose a target"
      row = run.menu.entries.first
      expect(row.text).to end_with "orc corpse (eat when starving)"
      expect(row.enabled).to be_false
    end

    it "eats a corpse from its target while starving" do
      run = modern over_corpse(Kind::Wolf, Sustenance::STARVING)
      run.press "g"

      texts = run.menu.entries.map &.text
      expect(texts.size).to eq 2
      expect(texts[1]).to end_with "wolf corpse - eat some (starving!)"

      run.press "s", "f"
      expect(run.game.events.any?(Roguelike::Event::Ate)).to be_true
      expect(run.game.player.food_bag.empty?).to be_true
    end

    it "cuts a fresh beast corpse from the first target while starving" do
      run = modern over_corpse(Kind::Wolf, Sustenance::STARVING)
      run.press "g", "f"

      expect(run.game.player.food_bag.items.map &.kind).to eq [Roguelike::ItemKind::FreshMeat]
    end
  end
end
