require "../../spec_helper"

Spectator.describe "how a flame is drawn" do
  alias Item = Roguelike::Item
  alias Kind = Roguelike::ItemKind
  alias LightKind = Roguelike::LightKind
  alias Ui = Roguelike::Ui

  # A long dark hall. The character stands at one end with a lit torch, so
  # the pool has an edge inside the room.
  HALL = [
    "####################",
    "#..................#",
    "#.<................#",
    "#..................#",
    "####################",
  ]

  def burning : Playing::Run
    floor = Roguelike::Floor.parse "hall", HALL
    player = Roguelike::Player.new "hall", *Roguelike::Game.entrance(floor)
    player.inventory.add Playing.torch

    Playing.open Roguelike::Game.new(
      Roguelike::World.new(Playing::SEED, {"hall" => floor}), player), 40, 16
  end

  def drawn_style(run : Playing::Run, x : Int32, y : Int32) : TermBuf::Style
    found = run.buffer.hit x, y
    raise "nothing is drawn at #{x},#{y}" unless found

    run.buffer.styles[found.cell.style]
  end

  describe "the tint" do
    # Firelight reads as warm and a magically lit room as cold. Stone under a
    # torch is still stone.
    it "warms a square a flame lights" do
      plain = Ui::Palette.shaded Ui::Palette[Roguelike::Terrain::StoneFloor], 3
      warm = Ui::Palette.shaded Ui::Palette[Roguelike::Terrain::StoneFloor], 3,
        LightKind::Flame

      expect(warm.style.foreground.red).to be > plain.style.foreground.red
      expect(warm.style.foreground.blue).to be < plain.style.foreground.blue
    end

    it "cools a square a magic light reaches" do
      plain = Ui::Palette.shaded Ui::Palette[Roguelike::Terrain::StoneFloor], 3
      cold = Ui::Palette.shaded Ui::Palette[Roguelike::Terrain::StoneFloor], 3,
        LightKind::Glimmer

      expect(cold.style.foreground.blue).to be > plain.style.foreground.blue
    end

    # What lights a square now says nothing about what it looked like when it
    # was last seen.
    it "leaves a remembered square alone" do
      base = Ui::Palette[Roguelike::Terrain::StoneFloor]
      plain = Ui::Palette.shaded base, Ui::Palette::REMEMBERED
      lit = Ui::Palette.shaded base, Ui::Palette::REMEMBERED, LightKind::Flame

      expect(lit).to eq plain
    end

    it "leaves stone looking like stone" do
      base = Ui::Palette[Roguelike::Terrain::StoneFloor].style.foreground
      warm = Ui::Palette.shaded(Ui::Palette[Roguelike::Terrain::StoneFloor], 4,
        LightKind::Flame).style.foreground

      expect((warm.red - base.red).abs).to be < 40
      expect((warm.green - base.green).abs).to be < 40
    end
  end

  describe "what the lighting says is on a square" do
    it "calls a torch pool firelight" do
      run = burning

      expect(run.game.sight.light_kind(3, 2)).to eq LightKind::Flame
    end

    it "calls a floor lit throughout a glimmer" do
      floor = Playing.daylight Roguelike::Floor.parse("room", HALL)
      game = Roguelike::Game.new Roguelike::World.new(1_u64, {"room" => floor}),
        Roguelike::Player.new("room", 2, 2)

      expect(game.sight.light_kind(6, 2)).to eq LightKind::Glimmer
    end

    it "says nothing about a square with no light" do
      run = burning

      expect(run.game.sight.light_kind(18, 2)).to be_nil
    end

    # A torch beside a lit room leaves the squares nearest it reading as
    # firelight and the rest as the room's.
    it "takes the stronger of two sources" do
      floor = Roguelike::Floor.parse "room", ["#########", "#*******#", "#########"]
      lighting = Roguelike::Lighting.over floor,
        [Roguelike::LightSource.new(1, 1, 6)]

      expect(lighting.kind_at 1, 1).to eq LightKind::Flame
      expect(lighting.kind_at 7, 1).to eq LightKind::Glimmer
    end
  end

  describe "a tick of the flame" do
    # A row of the pool, as it is drawn now.
    def pool(run : Playing::Run) : Array(TermBuf::Color)
      (0...20).map { |column| drawn_style(run, column, 2).foreground }
    end

    it "changes what some square is drawn in" do
      run = burning
      frames = [pool run]

      24.times do
        run.play.waver
        run.render
        frames << pool run
      end

      expect(frames.uniq!.size).to be > 1
    end

    # One flame lights this pool, so a tick either moves the whole of it or
    # none of it. Two flames overlapping is what `Flicker` covers.
    it "moves the whole pool or none of it" do
      run = burning
      still = pool run

      moved = (0...40).map do
        run.play.waver
        run.render
        pool run
      end

      whole = moved.count { |frame| frame == still }
      expect(whole).to be > 0
      expect(whole).to be < 40
    end

    # A tick moves the pool as one. The ends of the ramp hold some squares
    # back: one already at the top cannot flare and one at the bottom of the
    # lit range cannot gutter, so a frame moves most of the pool rather than
    # all of it.
    it "moves most of the pool at once or none of it" do
      run = burning
      still = pool run

      apart = (0...40).map do
        run.play.waver
        run.render
        pool(run).zip(still).count { |now, before| now != before }
      end

      expect(apart.any? &.zero?).to be_true
      expect(apart.reject(&.zero?).min).to be > 3
    end

    # It shifts which shade a square draws at and no more.
    it "leaves what can be seen alone" do
      run = burning
      before = run.game.sight.size

      20.times { run.play.waver; run.render }

      expect(run.game.sight.size).to eq before
    end

    it "takes no turn" do
      run = burning

      20.times { run.play.waver; run.render }

      expect(run.turn).to eq 0
    end

    it "remembers nothing new" do
      run = burning
      before = run.game.knowledge.size

      20.times { run.play.waver; run.render }
      run.play.refresh
      run.render

      expect(run.game.knowledge.size).to eq before
    end

    it "leaves the glyphs alone" do
      run = burning
      before = run.rows

      20.times { run.play.waver; run.render }

      expect(run.rows).to eq before
    end
  end

  # A blend computing a color per cell interns a style per cell. The ramps
  # cache, so the table settles even with the flame moving.
  describe "the style table under a flame" do
    it "stops growing once the flame has been through its shades" do
      run = burning

      200.times { run.play.waver; run.render }
      settled = run.buffer.styles.size

      400.times { run.play.waver; run.render }

      expect(run.buffer.styles.size).to eq settled
    end

    it "settles at a size a person could count" do
      run = burning

      200.times { run.play.waver; run.render }

      expect(run.buffer.styles.size).to be < 80
    end
  end

  # A dark hall with a lit sconce on the east wall and a goblin standing
  # between it and the character. The goblin's own square has no light on it,
  # so the only flame that can move it is the one lighting the square behind.
  BACKLIT = [
    "###############",
    "#<...g.......!#",
    "###############",
  ]

  # Where the goblin stands, and where the light it shows against is.
  SHAPE  = {5, 1}
  BEHIND = {7, 1}

  describe "a shape against a flame" do
    def watching(lines : Array(String) = BACKLIT) : Playing::Run
      floor = Roguelike::Floor.parse "hall", lines
      run = Playing.open Roguelike::Game.new(
        Roguelike::World.new(Playing::SEED, {"hall" => floor}),
        Roguelike::Player.new("hall", 1, 1)), 40, 16
      run.play.refresh
      run.render
      run
    end

    # What the shape is drawn in now.
    def shading(run : Playing::Run) : TermBuf::Color
      spot = run.map.screen_of SHAPE[0], SHAPE[1]
      raise "the shape is off the screen" unless spot

      drawn_style(run, spot[0], spot[1]).foreground
    end

    # Every color the shape is drawn in over *ticks* ticks.
    def shadings(run : Playing::Run, ticks : Int32) : Array(TermBuf::Color)
      found = [shading run]
      ticks.times do
        run.play.waver
        run.render
        found << shading run
      end

      found
    end

    it "is a shape rather than a letter" do
      run = watching

      expect(run.game.sight.includes? *SHAPE).to be_false
      expect(run.game.sight.backlit? run.game.floor, *SHAPE).to be_true
      expect(run.game.sight.backlight run.game.floor, *SHAPE).to eq BEHIND
    end

    it "stands on a square with no flame of its own" do
      run = watching

      expect(run.game.sight.flames_at *SHAPE).to be_empty
      expect(run.game.sight.flames_at *BEHIND).not_to be_empty
    end

    it "changes what it is drawn in as the flame behind it moves" do
      expect(shadings(watching, 40).uniq!.size).to be > 1
    end

    # One flame lights the square behind it, so it has one step to move to
    # and one to come back to.
    it "moves between two shades and no more" do
      expect(shadings(watching, 120).uniq!.size).to eq 2
    end

    # A shape drawn below `SHAPE_STEP` would be drawn the way a remembered
    # square is drawn, and a flame guttering must not do that.
    it "is never drawn darker than a shape that holds still" do
      base = Ui::Palette.shaded(
        Ui::Palette.shape(Roguelike::Size::Small), Ui::Palette::SHAPE_STEP)
        .style.foreground

      expect(shadings(watching, 120).min_of(&.red)).to eq base.red
    end

    it "is never drawn brighter than one step above that" do
      top = Ui::Palette.shaded(Ui::Palette.shape(Roguelike::Size::Small),
        Ui::Palette::SHAPE_STEP + Ui::Palette::SHAPE_WAVER).style.foreground

      expect(shadings(watching, 120).max_of(&.red)).to eq top.red
    end

    it "holds still with no flicker" do
      run = watching
      run.map.flicker = nil

      expect(shadings(run, 40).uniq!.size).to eq 1
    end

    # Nothing is burning in a magically lit room, so nothing behind the shape
    # wavers and the shape does not either.
    it "holds still against a light with no flame in it" do
      run = watching ["###############", "#<...g..******#", "###############"]

      expect(run.game.sight.backlit? run.game.floor, *SHAPE).to be_true
      expect(shadings(run, 40).uniq!.size).to eq 1
    end
  end

  describe "a pane with no flicker" do
    it "draws the same map every time" do
      run = burning
      run.map.flicker = nil
      run.render
      before = (0...20).map { |column| drawn_style(run, column, 2).foreground }

      20.times { run.play.waver; run.render }

      expect((0...20).map { |column| drawn_style(run, column, 2).foreground }).to eq before
    end
  end
end
