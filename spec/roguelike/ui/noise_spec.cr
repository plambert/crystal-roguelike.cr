require "../../spec_helper"

Spectator.describe "the character's noise on the screen" do
  alias Action = Roguelike::Action
  alias Direction = Roguelike::Direction
  alias Monster = Roguelike::Monster
  alias Noise = Roguelike::Noise
  alias Palette = Roguelike::Ui::Palette
  alias Play = Roguelike::Ui::Play
  alias Species = Roguelike::Species
  alias Style = TermBuf::Style
  alias Theme = Roguelike::Ui::Theme

  # A lit hall, with a goblin beside the character.
  HALL = [
    "####################",
    "#..................#",
    "#..................#",
    "#..................#",
    "####################",
  ]

  HERE   = {1, 2}
  BESIDE = {2, 2}

  def hall(clock : Bool = false, motion : Bool = false) : Playing::Run
    floor = Playing.daylight Roguelike::Floor.parse("hall", HALL)
    floor.place Monster.new(Species::Goblin, *BESIDE, "band-one", hit_points: 200)
    player = Roguelike::Player.new "hall", *HERE, hit_points: 500

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}), player),
      80, 24, clock: clock, motion: motion
  end

  # Swings at the goblin and draws the screen.
  def swing(run : Playing::Run) : Nil
    run.game.perform Action::Move.new(Direction::East)
    run.play.refresh
    run.render
  end

  # The background of the map square *x*, *y* as drawn.
  def ground_at(run : Playing::Run, x : Int32, y : Int32) : TermBuf::Color?
    found = run.buffer.hit(*run.on_map(x, y))
    found.try { |hit| run.buffer.styles[hit.cell.style].background }
  end

  describe "the bar" do
    it "is hidden while the character is quiet" do
      run = hall
      run.render

      expect(run.text).not_to contain "noise"
    end

    it "says how far the last noise carried" do
      run = hall

      swing run

      expect(run.text).to contain "♪"
      expect(run.text).to contain "noise #{run.game.noise}"
    end
  end

  describe "the tint" do
    it "covers the squares the sound reached, shaded by how far it went" do
      run = hall

      swing run

      expect(ground_at run, 3, 2).to eq Palette.noise_tints[Palette.noise_step(2, Noise::BLOW)]
      expect(ground_at run, 18, 2).to eq Palette.ground
    end

    it "goes away after an action that makes no noise" do
      run = hall
      swing run

      run.game.perform Action::Move.new(Direction::North)
      run.play.refresh
      run.render

      expect(run.map.echo).to be_empty
    end

    it "spreads a square at a time with motion on" do
      run = hall clock: true, motion: true

      swing run

      expect(run.map.echo_front).to eq 0
      run.tick Play::RIPPLE
      expect(run.map.echo_front).to eq 1

      run.run_timers
      expect(run.map.echo_front).to be_nil
    end

    it "draws the front of the spreading tint on its own color" do
      run = hall clock: true, motion: true

      swing run
      run.tick Play::RIPPLE
      run.tick Play::RIPPLE
      run.render

      expect(ground_at run, 3, 2).to eq Palette.noise_wave
      expect(ground_at run, 2, 1).to eq Palette.noise_tints[Palette.noise_step(1, Noise::BLOW)]
      expect(ground_at run, 4, 2).to eq Palette.ground
    end

    it "is drawn whole at once with motion off" do
      run = hall clock: true, motion: false

      swing run

      expect(run.map.echo_front).to be_nil
    end

    it "keeps every glyph readable on every step" do
      looks = [Palette.stone, Palette.dirt, Palette.granite, Palette.goblin_scout,
               Palette.orc, Palette.hero, Palette.faint]
      looks.each do |style|
        Palette::NOISE_STEPS.times do |step|
          heard = Palette.heard style, step
          expect(Palette.contrast heard.foreground, heard.background).to be >= Palette::NOISE_CONTRAST
        end
      end
    end

    it "fades from the source to the edge" do
      expect(Palette.noise_step 0, Noise::BLOW).to eq Palette::NOISE_STEPS - 1
      expect(Palette.noise_step Noise::BLOW, Noise::BLOW).to eq 0
    end
  end

  describe "a sound heard out of sight" do
    # A dark hall where an orc fights a slime out of the character's sight.
    def brawl(clock : Bool, motion : Bool) : Playing::Run
      floor = Roguelike::Floor.parse("hall", HALL)
      orc = Monster.new Species::Orc, 8, 2, "band-orcs", hit_points: 500
      slime = Monster.new Species::Slime, 9, 2, "band-slimes", hit_points: 500
      [orc, slime].each { |creature| floor.place creature }
      player = Roguelike::Player.new "hall", *HERE, hit_points: 500
      game = Roguelike::Game.new Roguelike::World.new(Playing::SEED, {"hall" => floor}), player
      run = Playing.open game, 80, 24, clock: clock, motion: motion

      band = game.floor.band "band-orcs"
      raise "no orcs" unless band
      band.awareness = Roguelike::Awareness::Hunting
      band.knowledge("hall").saw Roguelike::Knowledge.creature(slime.id), 9, 2, game.turn

      6.times do
        break if game.overheard.present?

        game.perform Action::Wait.new
      end
      run.play.refresh
      run.render
      run
    end

    # The glyph drawn on the map square *x*, *y*.
    def glyph_at(run : Playing::Run, x : Int32, y : Int32) : Char?
      run.buffer.hit(*run.on_map(x, y)).try &.cell.char
    end

    it "marks the last square in sight toward it" do
      run = brawl clock: false, motion: false
      spot = run.game.overheard.first.mark

      expect(run.map.heard).to contain spot
      expect(glyph_at run, *spot).to eq Palette::HEARD
    end

    it "blinks with motion on and ends lit" do
      run = brawl clock: true, motion: true
      spot = run.game.overheard.first.mark

      run.tick Play::BLINK
      run.render
      expect(glyph_at run, *spot).not_to eq Palette::HEARD

      run.tick Play::BLINK
      run.render
      expect(glyph_at run, *spot).to eq Palette::HEARD
    end

    it "holds still with motion off" do
      run = brawl clock: true, motion: false

      expect(run.armed_for Play::BLINK).to be_empty
      expect(run.map.heard_lit?).to be_true
    end
  end

  describe "the theme" do
    it "lists the noise colors for the theme editor" do
      keys = Theme::ENTRIES.map &.key

      expect(keys).to contain "noise_near", "noise_far", "noise_text", "noise_wave", "heard_mark",
        "noise_bar"
    end
  end
end
